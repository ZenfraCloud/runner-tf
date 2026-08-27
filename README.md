# runner-tf

The Zenfra runner image — the execution environment OpenTofu and Terraform runs
execute inside.

```
ghcr.io/zenfracloud/runner-tf:latest
```

## What this image is (and is not)

It is a **toolbox with no entrypoint**. It deliberately contains no OpenTofu or
Terraform binary, because the version is chosen per stack, not per image.

At run time the Zenfra worker:

1. downloads the tofu/terraform version pinned on the stack, verifies its
   SHA256, and caches it under `ZENFRA_TOOLS_REMOTE_CACHE_DIR`;
2. starts a container from this image with the binary bind-mounted read-only at
   `/usr/local/bin/<tool>`;
3. appends the command *after* the image name.

The resulting invocation looks like:

```bash
docker run --rm --network <mode> --user 1000:1000 -e ... \
  -v <workspace>:/workspace \
  -v <cached-binary>:/usr/local/bin/tofu:ro \
  -w /workspace \
  ghcr.io/zenfracloud/runner-tf:latest \
  /usr/local/bin/tofu apply
```

Because the command is appended, **this image must never declare an
`ENTRYPOINT`** — one would prepend itself to every tofu invocation and corrupt
it. See `BuildDockerArgs` in
`zenfra-worker/internal/worker/tools/remote_executor.go`.

## Contents

| Tool | Version | Why |
|---|---|---|
| Debian trixie (slim) | digest-pinned | glibc: official aws-cli v2 has no musl build, and some Terraform providers are cgo-linked and fail on Alpine |
| aws-cli | 2.36.31 | `local-exec`, credential_process, EKS auth |
| terragrunt | 1.1.3 | Terragrunt-based stacks |
| infracost | 2.16.2 | cost estimation |
| git, curl, jq, bash, openssh-client, python3, python3-pip, tzdata, ca-certificates | distro | the usual `local-exec` / external-data-source surface |

Runs as uid **1000** (`zenfra`), matching the `zenfra-worker` container user so a
workspace written by the worker needs no `chown`.

Built for `linux/amd64` and `linux/arm64`.

## Using it

Only workers in `docker` execution mode consult this image — in `host` mode the
worker execs the binary in its own container and this image is never pulled.

```bash
ZENFRA_TOOLS_EXECUTION_MODE=docker
ZENFRA_TOOLS_CONTAINER_BASE_IMAGE=ghcr.io/zenfracloud/runner-tf@sha256:<digest>
ZENFRA_TOOLS_IMAGE_USER=1000:1000
```

Pin by digest. The worker logs a warning for any base image without `@sha256:`,
because a mutable tag is a supply-chain hole in something that executes with
live cloud credentials.

## Bumping a tool

Versions and their SHA256 hashes are pinned together — the pin is only
meaningful if bumping one forces you to update the other.

```bash
# terragrunt
curl -sL https://github.com/gruntwork-io/terragrunt/releases/download/v<NEW>/SHA256SUMS \
  | grep -E 'terragrunt_linux_(amd64|arm64)$'

# infracost   (note: v2+ lives in infracost/cli, not infracost/infracost —
#              the old repo's "latest" still serves the abandoned v0.10.x line)
for a in amd64 arm64; do
  curl -sL "https://github.com/infracost/cli/releases/download/v<NEW>/infracost-linux-$a.tar.gz.sha256"
done
```

aws-cli is pinned by version only; AWS serves it over HTTPS from
`awscli.amazonaws.com` and publishes a detached GPG signature rather than a
plain checksum.

## Cloud variants

Only the `aws` stage is built today, because `CloudProviderAWS` is the sole
provider in `zenfra-api/internal/models/cloud_integration.go`. Add `gcp` and
`azure` stages here when the API grows them — the Dockerfile is already split so
a new stage is `FROM base AS <cloud>` plus its CLI.
