# Self-hosted GitHub Actions runner image for musicbox.
#
# Same toolchain as .dev-agent/Dockerfile.sandbox, plus the GitHub Actions
# runner agent. Registers with the musicbox repo using label
# `musicbox-builder`, which is what .github/workflows/build-apk.yml targets.
#
# Build:
#   docker build -t musicbox-runner -f .dev-agent/runner/Dockerfile .
#
# Run (long-lived; first start needs RUNNER_TOKEN, subsequent starts don't):
#   podman run --rm \
#     -v musicbox-runner-state:/home/agent/actions-runner:Z \
#     -e REPO_URL=https://github.com/<owner>/musicbox \
#     -e RUNNER_TOKEN=<token from repo Settings → Actions → Runners> \
#     -e RUNNER_NAME=musicbox-runner-1 \
#     -e RUNNER_LABELS=musicbox-builder \
#     musicbox-runner
#
# This image deliberately reuses the sandbox image as its base so we have
# exactly one toolchain definition. Build the sandbox image first:
#   docker build -t musicbox-sandbox -f .dev-agent/Dockerfile.sandbox .

FROM musicbox-sandbox:latest

USER root

ARG RUNNER_VERSION=2.319.1
ENV RUNNER_HOME=/home/agent/actions-runner

RUN apt-get update && apt-get install -y --no-install-recommends \
        sudo libicu72 jq \
    && rm -rf /var/lib/apt/lists/* \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent

USER agent
WORKDIR ${RUNNER_HOME}

RUN ARCH=$(uname -m) \
 && case "$ARCH" in \
        x86_64)  RUNNER_ARCH=x64 ;; \
        aarch64) RUNNER_ARCH=arm64 ;; \
        *) echo "unsupported arch $ARCH" && exit 1 ;; \
    esac \
 && curl -fsSL -o runner.tar.gz \
      https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
 && tar -xzf runner.tar.gz \
 && rm runner.tar.gz

COPY --chown=agent:agent runner/entrypoint.sh /home/agent/entrypoint.sh
RUN chmod +x /home/agent/entrypoint.sh

ENTRYPOINT ["/home/agent/entrypoint.sh"]
