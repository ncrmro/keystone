---
title: ks CLI reference
description: Command reference for the Keystone infrastructure CLI
---

# ks CLI reference

The `ks` command is the primary interface for building, deploying, and inspecting Keystone-managed infrastructure.

## Help

Use any of these forms to view help:

```bash
ks --help
ks -h
ks help
ks help update
ks update --help
ks update -h
```

## Global behavior

- `HOSTS` is a comma-separated list such as `workstation,ocean`.
- When `HOSTS` is omitted, `ks` resolves the current host from `hosts.nix`.
- Repo discovery checks `$NIXOS_CONFIG_DIR`, the current git repo root, `~/.keystone/repos/*/`, then `~/nixos-config`.

## Commands

### `ks build`

```bash
ks build [--lock] [--user USERS] [--all-users] [HOSTS]
```

Build Keystone configurations for one or more hosts.

- `--lock`: Build full NixOS system closures instead of home-manager profiles.
- `--user USERS`: Limit home-manager builds to a comma-separated user list.
- `--all-users`: Build all home-manager users on each target host.

Examples:

```bash
ks build
ks build workstation,ocean
ks build --user alice,agent-coder workstation
ks build --lock ocean
```

### `ks update`

```bash
ks update [--debug] [--dev] [--boot] [--pull] [--lock] [--user USERS] [--all-users] [HOSTS]
```

Pull, verify, build, and deploy Keystone hosts.

- `--debug`: Show warnings from `git` and `nix` commands.
- `--dev`: Build and deploy the current unlocked checkout without pull, lock, or push.
- `--boot`: Register the new generation for next boot without switching now.
- `--pull`: Pull managed repos only, then stop.
- `--lock`: Force lock mode explicitly. This is the default unless `--dev` is set.
- `--user USERS`: Limit home-manager activation to a comma-separated user list.
- `--all-users`: Activate all home-manager users on each target host.

Examples:

```bash
ks update
ks update --dev workstation
ks update --boot ocean
ks update --pull --dev
```

### `ks agents`

```bash
ks agents <pause|resume|status> <agent|all> [reason]
```

Control task-loop pause state for one agent or the full agent fleet.

- `pause`: Create the pause marker so scheduled task-loop runs exit before ingest and execution.
- `resume`: Remove the pause marker and allow scheduled task-loop runs again.
- `status`: Show whether the target agent task loop is paused.

Examples:

```bash
ks agents pause drago "waiting for human review"
ks agents pause all "human focus block"
ks agents status luce
ks agents resume all
```

### `ks switch`

```bash
ks switch [--boot] [HOSTS]
```

Build and deploy the current local state without pull, lock, or push steps.

- `--boot`: Register the new generation for next boot without switching now.

Examples:

```bash
ks switch
ks switch workstation,ocean
ks switch --boot ocean
```

### `ks sync-agent-assets`

```bash
ks sync-agent-assets
```

Refresh generated Keystone agent assets for the current user from the current
profile manifest.

- Rewrites generated instruction files, curated command files, and managed
  Codex skills from the live keystone checkout in development mode.
- This is the supported no-sudo refresh path for development-mode agent assets.

Example:

```bash
ks sync-agent-assets
```

### `ks sync-host-keys`

```bash
ks sync-host-keys
```

Fetch SSH host public keys from live hosts and write them into `hosts.nix`.

- Hosts without `sshTarget` are skipped.
- If `sshTarget` is unreachable and `fallbackIP` exists, `ks` retries over `fallbackIP`.

Example:

```bash
ks sync-host-keys
```

### `ks grafana dashboards`

```bash
ks grafana dashboards <apply|export> [uid]
```

Manage checked-in Keystone Grafana dashboards through the Grafana API.

- `apply`: Push every checked-in dashboard JSON file to Grafana, and delete stale keystone-managed dashboards that are no longer in the repo.
- `export <uid>`: Pull one dashboard by UID into its checked-in JSON file.
- `GRAFANA_URL`: Override the Grafana base URL.
- `GRAFANA_API_KEY`: Override the Grafana API key.
- In development mode, `ks update --dev`, `ks update`, and `ks switch` automatically sync keystone dashboards after deployment.

Examples:

```bash
ks grafana dashboards apply
ks grafana dashboards export keystone-host-overview
```

### `ks agent`

```bash
ks agent [--local [MODEL]] [args...]
```

Launch an AI coding agent with Keystone conventions and host context.

`ks agent` launches `claude` by default. Its static base prompt comes from the
generated `~/.keystone/AGENTS.md`, then `ks` appends live host and fleet context.
The generated command surface inside the session is curated to `/ks`, optional
`/ks.dev` in development mode, and `/deepwork`.

- `--local [MODEL]`: Use the local Ollama-backed model, or the configured default model.
- Remaining args are passed through to the underlying `claude` invocation.

Examples:

```bash
ks agent
ks agent --local
ks agent --local qwen2.5-coder:14b --continue
```

### `ks doctor`

```bash
ks doctor [--local [MODEL]] [args...]
```

Launch a diagnostic AI agent with fleet and local system state.

- `--local [MODEL]`: Use the local Ollama-backed model, or the configured default model.
- Remaining args are passed through to the underlying `claude` invocation.

Examples:

```bash
ks doctor
ks doctor --local
ks doctor --local mistral --continue
```
