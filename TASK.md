---
repo: ncrmro/keystone
branch: feat/agentctl-sandbox-podman
agent: claude
platform: github
issue: 123
status: ready
created: 2026-03-19
---

# Sandbox agentctl AI Tool Launches in Podman by Default

## Description

AI tool subcommands in `agentctl` (claude, gemini, codex, opencode) currently
run directly as the agent user. They must be wrapped in a Podman container by
default to provide filesystem and network isolation. A `--nosandbox` flag opts
out to the current direct-exec behavior.

Tech stack: Bash, NixOS, Podman, `podman-agent.sh` (existing sandbox backend).
Modified files: `modules/os/agents/scripts/agentctl.sh`,
`modules/os/agents/agentctl.nix`.

## Acceptance Criteria

- [ ] AI tool subcommands (claude, gemini, codex, opencode) launch via `podman-agent` by default
- [ ] Working directory (or worktree path when `--worktree` is set) is mounted read-write
- [ ] Parent `.git/` directory is mounted read-only inside the container
- [ ] Project context files (AGENT.md, CLAUDE.md, GEMINI.md) from `~/` are mounted read-only at `~/` in the container
- [ ] `--nosandbox` flag disables Podman and runs directly (current behavior preserved)
- [ ] Non-AI subcommands (shell, tasks, email, vnc, logs, etc.) are NOT sandboxed
- [ ] Sandbox uses existing `podman-agent` infrastructure (Nix store volume, SSH forwarding, cache volumes)
- [ ] `agentctl.nix` wires `PODMAN_AGENT` path variable into the script via `replaceVars`
- [ ] Existing tests pass (if any)

## Key Files

- `modules/os/agents/scripts/agentctl.sh` — main dispatch script; `claude|gemini|codex|opencode` branch needs sandboxing
- `modules/os/agents/agentctl.nix` — Nix module; must expose `podman-agent` store path via `replaceVars`
- `packages/podman-agent/podman-agent.sh` — existing sandbox backend; already handles mounts, SSH forwarding, cache volumes
- `specs/REQ-012-agentctl-project-sessions/requirements.md` — REQ-012.8 through REQ-012.14
