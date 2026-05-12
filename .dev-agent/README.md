# `.dev-agent/` — musicbox integration with `dev-agent-server`

This directory is the integration point between this repo and a
[`dev-agent-server`](https://github.com/jackrr/dev-agent-server) instance.
It is read by the server at session start; this repo (musicbox) does not
depend on the server beyond the contracts documented in `AGENT_CONTRACTS.md`.

## Files

| File | Purpose |
|------|---------|
| `config.yaml` | Server-facing manifest. Identity, sandbox build instructions, PR/artifact integration. |
| `prompt.md` | Appended to the agent's system prompt. Project-specific guidance. |
| `allowlist.txt` | Egress hostnames the sandbox proxy should allow. Used by Component 1's proxy. |
| `Dockerfile.sandbox` | Toolchain image used by per-session agent containers (Flutter + Rust + Android NDK). |
| `runner/Dockerfile` | Self-hosted GitHub Actions runner image. Reuses the sandbox image as its base. |
| `runner/entrypoint.sh` | Registers the runner on first start; on subsequent starts skips straight to `run.sh`. |

## How it fits together

1. The server clones this repo, reads `config.yaml`, and on first session
   build builds `Dockerfile.sandbox` into an image used to spawn per-session
   agent containers.
2. When the agent opens a PR on `agent/<session-id>`, GitHub fires the
   `pull_request` event into `.github/workflows/build-apk.yml`.
3. That workflow runs on a self-hosted runner with label `musicbox-builder`
   (see `runner/Dockerfile`), builds the APK, creates a pre-release tagged
   `pr-<num>-<sha>`, and posts a QR-coded download link to the PR.
4. The server polls GitHub for that release (using
   `ship.release_tag_pattern` and `ship.artifact_asset_pattern` from
   `config.yaml`) and surfaces the APK URL + QR into the chat UI.

## Setting up the runner

```sh
# 1. Build the sandbox base image (once, in this repo's root).
podman build -t musicbox-sandbox:latest -f .dev-agent/Dockerfile.sandbox .

# 2. Build the runner image (extends the sandbox).
podman build -t musicbox-runner:latest -f .dev-agent/runner/Dockerfile .dev-agent

# 3. Get a runner registration token from:
#      GitHub → repo Settings → Actions → Runners → New self-hosted runner
#    Then start the runner. The named volume persists registration across
#    restarts; RUNNER_TOKEN is only consulted on first start.
podman run --rm \
  -v musicbox-runner-state:/home/agent/actions-runner:Z \
  -e REPO_URL=https://github.com/<owner>/musicbox \
  -e RUNNER_TOKEN=<token> \
  -e RUNNER_LABELS=musicbox-builder \
  musicbox-runner:latest
```

## Required GitHub repo secrets

| Secret | Value |
|--------|-------|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 release.keystore` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |
