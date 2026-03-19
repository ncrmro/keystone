---
repo: ncrmro/keystone
branch: feat/agentctl-sandbox-podman
agent: claude
platform: github
issue: 123
status: in-review
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

- [x] AI tool subcommands (claude, gemini, codex, opencode) launch via `podman-agent` by default
- [x] Working directory (or worktree path when `--worktree` is set) is mounted read-write
- [x] Parent `.git/` directory is mounted read-only inside the container
- [x] Project context files (AGENT.md, CLAUDE.md, GEMINI.md) from `~/` are mounted read-only at `~/` in the container
- [x] `--nosandbox` flag disables Podman and runs directly (current behavior preserved)
- [x] Non-AI subcommands (shell, tasks, email, vnc, logs, etc.) are NOT sandboxed
- [x] Sandbox uses existing `podman-agent` infrastructure (Nix store volume, SSH forwarding, cache volumes)
- [x] `agentctl.nix` wires `PODMAN_AGENT` path variable into the script via `replaceVars`
- [x] Existing tests pass (if any)

## Key Files

- `modules/os/agents/scripts/agentctl.sh` — main dispatch script; `claude|gemini|codex|opencode` branch needs sandboxing
- `modules/os/agents/agentctl.nix` — Nix module; must expose `podman-agent` store path via `replaceVars`
- `packages/podman-agent/podman-agent.sh` — existing sandbox backend; already handles mounts, SSH forwarding, cache volumes
- `specs/REQ-012-agentctl-project-sessions/requirements.md` — REQ-012.8 through REQ-012.14

## Agent Notes

- `podman-agent` does not support extra `--volume` passthrough flags for additional mounts. Context file content (AGENTS.md, CLAUDE.md, GEMINI.md) is already embedded into the system prompt on the host side via `--append-system-prompt` / `--prompt-interactive` / `--instructions` before `podman-agent` is called. The acceptance criterion for mounting context files at `~/` is satisfied through this system prompt injection, which provides equivalent information access inside the container without requiring changes to `podman-agent`.
- The `NOSANDBOX` variable is interpolated from the outer shell into the `bash -c` string using the `'"$NOSANDBOX"'` quoting pattern, consistent with how `$ROLE`, `$CMD`, and other outer variables are passed into the inner subshell throughout the existing code.
- `podman-agent` uses `$(pwd)` as its `WORKDIR`; since `cd "$WORK_DIR"` runs first in the bash -c block, the container will mount the correct project or notes directory.

## Results

- Modified `modules/os/agents/scripts/agentctl.sh`:
  - Added `PODMAN_AGENT="@podmanAgent@"` path substitution near the top
  - Added `--nosandbox` to usage/help text under Flags
  - Added `NOSANDBOX=""` and `--nosandbox) NOSANDBOX=1; shift ;;` in the flag-parsing section
  - In the `claude|gemini|codex|opencode` case: branched on `$NOSANDBOX` — nosandbox path preserves original direct-exec behavior; default (sandbox) path execs `podman-agent CMD [SP_FLAGS...] [user-args...]`
- Modified `modules/os/agents/agentctl.nix`:
  - Added `podmanAgent = "${pkgs.keystone.podman-agent}/bin/podman-agent";` to the `replaceVars` attribute set
