#!/usr/bin/env bash
# Entrypoint for the musicbox self-hosted GitHub Actions runner.
#
# This is a long-lived (non-ephemeral) runner: it registers once and stays
# registered across container restarts. State lives in a persistent volume
# mounted at /home/agent/actions-runner; on subsequent starts the entrypoint
# detects existing registration and skips straight to ./run.sh.
#
# First-time registration env vars (only needed when the volume is empty):
#   REPO_URL       e.g. https://github.com/<owner>/musicbox
#   RUNNER_TOKEN   short-lived registration token from
#                  repo Settings → Actions → Runners → New self-hosted runner
# Optional env:
#   RUNNER_NAME    default: musicbox-runner-<hostname>
#   RUNNER_LABELS  default: musicbox-builder
#   RUNNER_GROUP   default: Default
#
# Once registered, RUNNER_TOKEN is no longer used (and may be removed from
# the host env file). The runner will keep its registration until you
# manually remove it via ./config.sh remove --token <fresh-token> or by
# deleting the runner from the GitHub UI and wiping the volume.

set -euo pipefail

cd "${RUNNER_HOME:-/home/agent/actions-runner}"

if [[ -f .runner ]]; then
    echo "Runner already registered. Skipping config; starting run.sh."
else
    : "${REPO_URL:?REPO_URL is required for first-time registration}"
    : "${RUNNER_TOKEN:?RUNNER_TOKEN is required for first-time registration}"

    RUNNER_NAME="${RUNNER_NAME:-musicbox-runner-$(hostname)}"
    RUNNER_LABELS="${RUNNER_LABELS:-musicbox-builder}"
    RUNNER_GROUP="${RUNNER_GROUP:-Default}"

    echo "Registering runner '${RUNNER_NAME}' with ${REPO_URL}..."
    ./config.sh \
        --unattended \
        --url "${REPO_URL}" \
        --token "${RUNNER_TOKEN}" \
        --name "${RUNNER_NAME}" \
        --labels "${RUNNER_LABELS}" \
        --runnergroup "${RUNNER_GROUP}" \
        --replace
fi

exec ./run.sh
