# ARG BASE_IMAGE=alpine:3.21
ARG BASE_IMAGE=ubuntu:latest

FROM ${BASE_IMAGE} AS base

ARG TARGETARCH

# RUN apk -U upgrade && apk add --no-cache \
RUN apt-get update && apt-get install -y \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
    python3 \
    tzdata \ 
    file
# openssh-keygen \

RUN [ -e /usr/bin/python ] || ln -s python3 /usr/bin/python

# Download infracost
ADD "https://github.com/infracost/infracost/releases/latest/download/infracost-linux-${TARGETARCH}.tar.gz" /tmp/infracost.tar.gz
RUN tar -xzf /tmp/infracost.tar.gz -C /bin && \
    mv "/bin/infracost-linux-${TARGETARCH}" /bin/infracost && \
    chmod 755 /bin/infracost && \
    rm /tmp/infracost.tar.gz

# Download Terragrunt.
ADD "https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_${TARGETARCH}" /bin/terragrunt
RUN chmod 755 /bin/terragrunt

# RUN echo "hosts: files dns" > /etc/nsswitch.conf \
#     && adduser --disabled-password --uid=1983 zenfra

# FROM base AS aws

# COPY --from=ghcr.io/spacelift-io/aws-cli-alpine /usr/local/aws-cli/ /usr/local/aws-cli/
# COPY --from=ghcr.io/spacelift-io/aws-cli-alpine /aws-cli-bin/ /usr/local/bin/

# RUN aws --version && \
#     terragrunt --version && \
#     python --version && \
#     infracost --version

# USER zenfra

# FROM base AS gcp

# RUN gcloud components install gke-gcloud-auth-plugin

# RUN gcloud --version && \
#     terragrunt --version && \
#     python --version && \
#     infracost --version

# USER zenfra

# FROM base AS azure-build

# RUN apk add --no-cache py3-pip gcc musl-dev python3-dev libffi-dev openssl-dev cargo make

# RUN python3 -m venv /opt/venv
# ENV PATH="/opt/venv/bin:$PATH"

# RUN pip install --no-cache-dir azure-cli

# FROM base AS azure

# ENV PATH="/opt/venv/bin:$PATH"

# COPY --from=azure-build /opt/venv /opt/venv

# RUN apk add --no-cache py3-pip && \
#     az --version && \
#     terragrunt --version && \
#     python --version && \
#     infracost --version

# USER zenfra