# REQ-019: ks CLI

The `ks` CLI is the primary interface for building, deploying, and
managing keystone NixOS infrastructure. This spec consolidates
requirements previously scattered across inline comments in `ks.sh`,
REQ-016, and REQ-018.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Affected Modules
- `packages/ks/ks.sh` — CLI script
- `packages/ks/default.nix` — Nix packaging

## Commands

| Command | Description |
|---------|-------------|
| `ks build [--home-only] [--lock] [--config-path PATH] [--keystone-path PATH] [HOSTS]` | Build full system (default), home-manager only (`--home-only`), or full system + lock (`--lock`) |
| `ks update [--home-only] [--boot] [--pull] [--lock] [--config-path PATH] [--keystone-path PATH] [HOSTS]` | Deploy to hosts |
| `ks sync-host-keys` | Populate `hostPublicKey` in `hosts.nix` from live hosts |
| `ks agent [--local [MODEL]] [args...]` | Launch AI agent with keystone OS context |
| `ks doctor [--local [MODEL]] [args...]` | Launch diagnostic AI agent with system state |

`HOSTS` is a comma-separated list of host names. Defaults to the current
machine's hostname as resolved from `hosts.nix`.

## Requirements

### Repo Discovery

**REQ-019.1** `ks` MUST discover the nixos-config repository root using
the following priority chain:
1. `$NIXOS_CONFIG_DIR` environment variable (if it contains `hosts.nix`)
2. Git repository root of the current working directory (if it contains `hosts.nix`)
3. `~/nixos-config` as fallback

**REQ-019.2** All discovered paths MUST be resolved via `readlink -f`
to eliminate symlinks, because Nix `path:` flake URIs break on symlinks.

### Build

**REQ-019.3** `ks build` without flags MUST build the full NixOS system
toplevel for all target hosts (no side effects — no lock, commit, or push).

**REQ-019.4** `ks build --home-only` MUST build only home-manager
activation packages for all managed users and agents on each target host
(fast iteration, no sudo required). `--dev` is a deprecated alias for
`--home-only`.

**REQ-019.5** `ks` MUST always use local repo checkouts (per REQ-018)
as `--override-input` when those directories exist, regardless of mode.

**REQ-019.6** `ks` MUST build all target hosts before deploying any of
them (fail-fast ordering).

**REQ-019.7** `ks` MUST pass `--no-link` to `nix build` to prevent
`./result` symlinks in the caller's working directory.

### Lock Mode (repo management)

**REQ-019.8** Lock mode (`ks build --lock`, `ks update` default) MUST:
1. Pull nixos-config, keystone, and agenix-secrets before building
2. Verify keystone and agenix-secrets are clean and fully pushed
3. Push keystone (with fork fallback per REQ-016.9)
4. Update `flake.lock` via `nix flake update` BEFORE building (not after)
5. Build all target hosts
6. Commit and push `flake.lock` only AFTER a successful build

**REQ-019.9** `ks update --pull` MUST pull all managed repos (per REQ-018.12)
without building or deploying.

### Deployment

**REQ-019.10** `ks` MUST deploy hosts sequentially (not in parallel) to
limit blast radius.

**REQ-019.11** `ks` MUST obtain sudo credentials before any other work
(pull, lock, build) when a local host is targeted, so the user is not
interrupted mid-run.

**REQ-019.12** `ks` SHOULD keep sudo credentials alive for the duration
of the run.

**REQ-019.13** `ks update --home-only` MUST build and activate only home-manager
profiles (users + agents) across all target hosts, skipping the full
NixOS system rebuild. Home-only mode deploy SHOULD NOT require sudo.
`--dev` is a deprecated alias for `--home-only`.

**REQ-019.14** `ks update --boot` MUST set the NixOS configuration for
next boot without activating it (uses `nixos-rebuild boot` instead of
`switch`).

### Dev Mode

**REQ-019.15** Home-only mode (`ks build --home-only`, `ks update --home-only`)
MUST skip pull, flake-update, commit, and push phases.

**REQ-019.16** Home-only mode MAY be used with uncommitted local repo changes.

### Path Overrides

**REQ-019.16.1** `ks build` and `ks update` MUST support `--config-path PATH`
to override the nixos-config repo root. When provided, repo discovery
(REQ-019.1) is bypassed and `PATH` is used directly (resolved via
`readlink -f`).

**REQ-019.16.2** `ks build` and `ks update` MUST support `--keystone-path PATH`
to override the keystone flake input. When provided, an additional
`--override-input keystone path:PATH` is passed to all `nix build` and
`nixos-rebuild` invocations (resolved via `readlink -f`).

### Dev Mode — Local Script Execution

**REQ-019.17** `ks` MUST be runnable directly from the local keystone
checkout at `~/.keystone/repos/{owner}/keystone/packages/ks/ks.sh`
(per REQ-018) without requiring a Nix rebuild. This enables testing
changes to the script immediately.

**REQ-019.18** `ks` MUST NOT depend on Nix-time variable substitutions
(`replaceVars` / `@placeholder@` patterns). All dependencies MUST be
resolved at runtime via `PATH` or explicit discovery functions.

**REQ-019.19** The keystone terminal module SHOULD add the local keystone
`packages/ks/` directory to the user's `PATH` when a local checkout
exists at the REQ-018 standard location, so the dev version of `ks`
takes precedence over the Nix-built version.

**REQ-019.20** Scripts that require Nix-time substitutions (e.g.,
`agentctl` with `replaceVars` for agent metadata and tool paths) MUST
be rebuilt via `ks build` (home-manager) or `nixos-rebuild` (system-level)
to pick up changes. This distinction MUST be documented in the project's
`CLAUDE.md`.

### Agent / Doctor Prompt Handling

**REQ-019.21** `ks agent` and `ks doctor` MUST launch Claude Code with
a system prompt containing host tables, agent status, conventions, and
(for doctor) live system state.

**REQ-019.22** The system prompt MUST NOT be passed as a single
command-line argument to `claude` or `agentctl`, because large prompts
(fleet health + agent tasks + conventions) exceed the Linux execve
`ARG_MAX` limit (~4MB including environment). Prompts MUST be written
to a temp file and passed via a mechanism that avoids `ARG_MAX`:
- Write to a checksummed temp file (`/tmp/ks-prompt-{hash}`)
- Read back via `$(cat "$file")` in the `--append-system-prompt` flag

**REQ-019.23** `ks agent` MUST pass through additional arguments to the
underlying claude invocation.

**REQ-019.24** `ks doctor` MUST gather current system state (NixOS
generation, failed units, disk usage, fleet health, agent health, agent
tasks) and include it in the prompt context.

**REQ-019.25** `ks agent` and `ks doctor` MUST support `--local [MODEL]`
to use Ollama instead of Claude Code (REQ-014.12-13).

### Host Key Sync

**REQ-019.26** `ks sync-host-keys` MUST SSH to each host in `hosts.nix`
that has an `sshTarget`, read `/etc/ssh/ssh_host_ed25519_key.pub`, and
update the `hostPublicKey` field in `hosts.nix`.

## Edge Cases

- If `gh` CLI is not available, lock mode MUST fall back to direct
  `git push` and emit a warning if push fails.
- If no home-manager users exist for a target host, `ks build --home-only`
  MUST succeed with a warning rather than error.
- Risky hosts SHOULD be deployed last when multiple hosts are targeted
  (user convention, not enforced).
- Remote URL parsing MUST handle both `git@github.com:owner/repo.git`
  and `ssh://git@host/owner/repo.git` formats, stripping `.git` suffix
  correctly (no double `.git.git`).

## Supersedes

- Inline RFC 2119 comments in `ks.sh` (lines 31-54) — formalized here
- REQ-016.7-10 (lock workflow) — consolidated into REQ-019.8
- REQ-014.1-13 (ks agent/doctor) — consolidated into REQ-019.21-25
- REQ-018.6-12 (dev mode + lock mode repo behavior) — referenced, not duplicated
