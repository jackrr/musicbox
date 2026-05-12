# AGENTS.md — musicbox

## What this is

Offline-first mobile music-making app (Flutter + Rust). Integrates with
[dev-agent-server](https://github.com/jackrr/dev-agent-server) for
AI-assisted bug fixing via a self-hosted Claude agent.

## Quick reference

```sh
# Rust engine
cd engine && cargo check          # fast type-check
cd engine && cargo test           # unit tests
./scripts/build_android.sh        # rebuild native lib for Android

# Flutter app
cd app && flutter pub get
cd app && flutter run              # requires device/emulator
cd app && flutter analyze
cd app && flutter test
```

## Dev-agent integration

This repo provides three things to the dev-agent-server:

1. **`.dev-agent/`** — config, sandbox Dockerfile, agent prompt, egress
   allowlist. The server reads `config.yaml` at boot. See
   `.dev-agent/README.md`.

2. **`app/lib/bug_report/`** — Flutter module that captures bug reports and
   copies a `<bug-report>` XML blob to clipboard. No networking; the user
   pastes into the server's web UI.

3. **`.github/workflows/build-apk.yml`** — CI that builds signed APKs on
   PRs. For `agent/*` branches, creates a GitHub pre-release with the APK
   and posts a QR download link to the PR.

Cross-repo contracts are documented in `AGENT_CONTRACTS.md`.

## Deploy target

The dev-agent-server runs on **Fedora + rootless Podman + Quadlet/systemd**.
See `~/projects/dev-agent-server/README.md` for the deploy runbook.
