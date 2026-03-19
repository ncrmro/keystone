# Agent Module Architecture

Split from the monolithic `agents.nix` into focused sub-modules for maintainability.

## Directory Structure

```
agents/
  AGENTS.md          -- this file
  default.nix        -- options declaration + barrel imports
  lib.nix            -- shared helpers, constants, filtered agent sets
  types.nix          -- agentSubmodule type definition
  base.nix           -- user creation, groups, tmpfiles, sudo, home dirs, activation
  agentctl.nix       -- agentctl CLI + alias wrappers + MCP config publishing
  desktop.nix        -- labwc + wayvnc services
  chrome.nix         -- Chromium remote debugging services
  dbus.nix           -- D-Bus socket race fix
  mail-client.nix    -- himalaya + mail assertions
  tailscale.nix      -- per-agent Tailscale (currently disabled)
  ssh.nix            -- ssh-agent + assertions
  notes.nix          -- notes-sync, task-loop, scheduler services + timers
  home-manager.nix   -- home-manager terminal integration
  scripts/
    agent-svc.sh     -- per-agent service helper
    task-loop.sh     -- task loop script
    scheduler.sh     -- scheduler script
    agentctl.sh      -- agentctl CLI
```

## How `lib.nix` Works

`lib.nix` is a plain function, not a NixOS module:

```nix
# Each sub-module imports it in its let block:
let agentsLib = import ./lib.nix { inherit lib config pkgs; };
```

It exports: `osCfg`, `cfg`, `keysCfg`, `topDomain`, `agentPublicKey`, `allKeysForAgent`, `agentsWithUids`, `localAgents`, `desktopAgents`, `chromeAgents`, `mailAgents`, `sshAgents`, `tailscaleAgents`, port resolution functions, `agentSvcHelper`, `labwcConfigScript`, `agentMcpConfig`, and all `has*` booleans.

This avoids circular imports. All sub-modules read from the same shared state.

## Shell Script Extraction

Scripts use `pkgs.replaceVars` with `@placeholder@` substitutions (same pattern as `tpm.nix` + `scripts/enroll-tpm.sh`):

- **Coreutils paths** (`@date@`, `@mkdir@`, etc.): Full Nix store paths to avoid PATH dependency
- **Dynamic Nix-computed values** (`@agentHelperCases@`, `@knownAgents@`): String-interpolated at build time
- **All path placeholders** are assigned in double-quoted strings at the script top for valid shell syntax

## Agent Filtering Model

- `cfg` (all agents): Used for user accounts, home dirs, agentctl, dbus fix
- `localAgents` (host-filtered): Used for desktop, chrome, mail, SSH
- `desktopAgents`, `chromeAgents`, `mailAgents`, `sshAgents`: Currently equal to `localAgents`
- `tailscaleAgents`: Currently `{}` (disabled)

## Adding a New Sub-Module

1. Create `new-feature.nix` as a NixOS module: `{ lib, config, pkgs, ... }: ...`
2. Import `lib.nix`: `let agentsLib = import ./lib.nix { inherit lib config pkgs; };`
3. Return `{ config = mkIf (osCfg.enable && cfg != { }) { ... }; }`
4. Add import to `default.nix`

## Security: Claude/Gemini Flag Separation

In agentctl's tool dispatch and task-loop:
- `claude` commands: `--dangerously-skip-permissions --mcp-config "$MCP_CONFIG"`
- `gemini` commands: `--yolo`
- `codex` commands: `--full-auto`

These are mutually exclusive per-tool case branches — never combined on a single tool invocation.
