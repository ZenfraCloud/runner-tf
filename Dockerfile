# Zenfra runner image — the execution environment for OpenTofu/Terraform runs.
#
# This image deliberately contains NO IaC binary and NO entrypoint. The Zenfra
# worker bind-mounts the tofu/terraform binary it downloaded (version pinned per
# stack) at /usr/local/bin/<tool>:ro and appends the command after the image
# name, so an ENTRYPOINT here would corrupt every invocation. See
# zenfra-worker/internal/worker/tools/remote_executor.go:BuildDockerArgs.
#
# Debian rather than Alpine: the official aws-cli v2 ships glibc-only (Alpine
# needs a from-source build), and a minority of Terraform providers are cgo-
# linked and fail on musl.

# Pulled via Google's pull-through cache, not Docker Hub directly: the shared
# CI runners egress from one IP and hit Docker Hub's anonymous pull-rate limit.
# mirror.gcr.io serves the identical digest.
ARG BASE_IMAGE=mirror.gcr.io/library/debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

FROM ${BASE_IMAGE} AS base

ARG TARGETARCH
ARG TERRAGRUNT_VERSION=1.1.3
ARG INFRACOST_VERSION=2.16.2

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        jq \
        openssh-client \
        python3 \
        python3-pip \
        tzdata \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Terragrunt. Version and checksum are pinned: bumping the version requires
# updating the matching hash, which is what makes the pin meaningful.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) sha256=d5da6a66741f4ee752aa3b502b57e47fd6d5c178942861b2507f14f083e7606e ;; \
        arm64) sha256=5e9b388402ab7075e907e8d8511662e2a828008129746e4e5e23de04c7b78ef4 ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/terragrunt \
        "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_${TARGETARCH}"; \
    echo "${sha256}  /usr/local/bin/terragrunt" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/terragrunt

# Infracost. Note the repo: v2 releases moved to infracost/cli, and
# infracost/infracost's "latest" still serves the abandoned v0.10.x line.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) sha256=f3ac38ca0a30464a5f3ba78c10a29927baf8c2d97d310a91c553f37389afc4da ;; \
        arm64) sha256=a8787ec2712363ddfe0796a5c706e46368debd182b8c7ec6f02a7664c6d830e0 ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/infracost.tar.gz \
        "https://github.com/infracost/cli/releases/download/v${INFRACOST_VERSION}/infracost-linux-${TARGETARCH}.tar.gz"; \
    echo "${sha256}  /tmp/infracost.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/infracost.tar.gz -C /usr/local/bin infracost; \
    chmod 0755 /usr/local/bin/infracost; \
    rm -f /tmp/infracost.tar.gz

# uid 1000 matches the zenfra-worker container user, so a workspace written by
# the worker is writable by the runner without a chown.
RUN useradd --uid 1000 --user-group --create-home --shell /bin/bash zenfra


# --- AWS -------------------------------------------------------------------
# The only cloud stage built today: CloudProviderAWS is the sole provider in
# zenfra-api/internal/models/cloud_integration.go. Add gcp/azure stages here
# when the API grows them.
FROM base AS aws

ARG TARGETARCH
ARG AWS_CLI_VERSION=2.36.31

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) awsarch=x86_64 ;; \
        arm64) awsarch=aarch64 ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/awscliv2.zip \
        "https://awscli.amazonaws.com/awscli-exe-linux-${awsarch}-${AWS_CLI_VERSION}.zip"; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli; \
    rm -rf /tmp/aws /tmp/awscliv2.zip; \
    rm -rf /usr/local/aws-cli/v2/current/dist/aws_completer \
           /usr/local/aws-cli/v2/current/dist/awscli/data/ac.index \
           /usr/local/aws-cli/v2/current/dist/awscli/examples

RUN aws --version \
    && terragrunt --version \
    && infracost --version \
    && python3 --version \
    && git --version \
    && jq --version \
    && ssh -V

USER zenfra

# No ENTRYPOINT by design — see header. CMD is a convenience for `docker run -it`
# and is overridden by the worker on every real invocation.
CMD ["/bin/bash"]
