# Cloud Dev Agent — Plan (historical)

> **This was the original planning document.** The system is now implemented
> across two repos. For current documentation see:
>
> - **Contracts:** `AGENT_CONTRACTS.md` (this repo) — shared interfaces
> - **Server:** `~/projects/dev-agent-server/README.md` — deploy runbook
> - **Integration:** `.dev-agent/README.md` — how musicbox plugs into the server
> - **Bug capture:** `app/lib/bug_report/` — Flutter capture module

## Summary

A self-hosted Claude agent that you chat with via an authenticated web UI
(Cloudflare Access). You paste a structured bug report (captured by the app
and copied to clipboard) into the chat. The agent works in a sandboxed
container against a git worktree of this repo, opens a PR, and CI builds a
sideloadable APK.

## Architecture

```
Flutter app (capture only)
   │   "Copy report" → clipboard
   ▼
You paste into ──►  Web UI (chat)
                       │  HTTPS via Cloudflare Tunnel
                       │  Cloudflare Access (Zero Trust)
                       ▼
               dev-agent-server  ──►  Claude  ──►  sandboxed worktree
                       │                                │
                       │                                │ git push agent/<id>
                       │                                │ gh pr create
                       │                                ▼
                       │                     GitHub Actions: build-apk on PR
                       │                                │
                       └──── chat surfaces APK URL ◄────┘
```

## Key decisions

- **No app→backend networking.** The app copies to clipboard; you paste.
- **Auth:** Cloudflare Access on the tunnel hostname.
- **Deploy:** Fedora + rootless Podman + Quadlet/systemd (primary).
  `docker-compose.yml` exists as a fallback.
- **Repos:** `dev-agent-server` (generic, project-agnostic) is standalone.
  musicbox ships `.dev-agent/` for project-specific config + toolchain.

## Components

| # | What | Where |
|---|------|-------|
| 1 | dev-agent-server | `~/projects/dev-agent-server/` |
| 2 | Bug report capture | `app/lib/bug_report/` (this repo) |
| 3 | CI: build & publish APK | `.github/workflows/build-apk.yml` + `.dev-agent/runner/` (this repo) |
