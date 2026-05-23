---
title: OS Agents
description: Non-interactive NixOS user accounts for autonomous LLM-driven operation
---

# OS Agents (`keystone.os.agents`)

> **Note (2026-05):** the autonomous task-loop, scheduler, notes-sync, and
> `.agents`-submodule scaffolding have been removed. The replacement layout
> (per-agent state symlinks into the consumer flake plus a portable
> `task-loop` skill) is being introduced in a follow-up PR; see the layout
> plan referenced by the PR that removed this content for the new model.
> Sections below describe the surviving surface: user provisioning,
> mail/calendar/contacts, SSH, browser, MCP, and debugging.

OS agents are non-interactive NixOS user accounts designed for autonomous LLM-driven operation. Each agent gets an isolated home directory, SSH keys, mail, and browser.

## Quick Start

```nix
keystone.os.agents.drago = {
  fullName = "Drago";
  email = "drago@example.com";
};

# SSH public key is registered in the keys registry, not on the agent
keystone.keys."agent-drago".hosts.myhost.publicKey = "ssh-ed25519 AAAAC3...";
```

## Architecture Overview

Each agent is provisioned by a focused set of sub-modules under
`modules/os/agents/`:

| Sub-module        | Responsibility                                         |
| ----------------- | ------------------------------------------------------ |
| `base.nix`        | User account, home dir, groups, ACL fixups             |
| `ssh.nix`         | ssh-agent + agenix key + git signing                   |
| `desktop.nix`     | Headless Wayland (labwc + wayvnc)                      |
| `chrome.nix`      | Chromium with remote debugging + DevTools MCP          |
| `mail-client.nix` | himalaya CLI + Stalwart assertions                     |
| `home-manager.nix`| Terminal environment (zsh, helix, AI CLIs, MCP wiring) |
| `agentctl.nix`    | `agentctl` CLI + per-agent helper sudoers              |
| `dbus.nix`        | D-Bus socket activation race fix                       |
| `perception.nix`  | Document/voice/screenshot perception layer             |
| `tailscale.nix`   | Per-agent tailscaled (currently disabled)              |

## Two-Agent Coordination

The system deploys two agents with complementary roles:

| Agent                       | Role                       | Responsibility                           | Runs On                      |
| --------------------------- | -------------------------- | ---------------------------------------- | ---------------------------- |
| **Product agent** (CPO)     | Business analysis, scoping | Press releases, milestones, user stories | VPS / headless server        |
| **Engineering agent** (CTO) | Implementation, delivery   | Code, PRs, deployments, code review      | Workstation with dev tooling |

### Artifact Handoff Chain

The agents collaborate through a structured artifact chain using GitHub/Forgejo as the shared coordination surface:

```
context → lean canvas → KPIs → market analysis → press release
  → milestone → user stories (issues) → branches → pull requests
```

1. **Product agent** produces a press release via the `press_release/write` workflow
2. **Product agent** converts it to a milestone + issues via the `product_engineering_handoff/handoff` workflow
3. **Engineering agent** picks up the resulting issues
4. **Engineering agent** creates branches, PRs, and delivers code via dedicated engineering workflows

## Forgejo SSH URL Format

When using Forgejo's built-in SSH server, the SSH username must match the system user running Forgejo — typically `forgejo`, **not** `git`.

```
# CORRECT — Forgejo built-in SSH server
ssh://forgejo@git.example.com:2222/owner/repo.git

# WRONG — will fail with "Permission denied (publickey)"
ssh://git@git.example.com:2222/owner/repo.git
git@git.example.com:owner/repo.git
```

The `git@` convention is GitHub/GitLab-specific. Forgejo's built-in SSH server (`START_SSH_SERVER = true`) runs as the `forgejo` user and only accepts connections with that username.

If using Forgejo with OpenSSH (passthrough mode) instead of the built-in server, `git@` may work depending on configuration — but the built-in server always requires `forgejo@`.

## Required Agenix Secrets

Each agent with SSH configured needs:

- `agent-{name}-ssh-key` — Private SSH key (ed25519)
- `agent-{name}-ssh-passphrase` — Passphrase for the key

Agents that provision a Stalwart mailbox additionally need:

- `agent-{name}-mail-password` — IMAP/SMTP password (must list both the agent's
  host and the mail server host as recipients)

## What Each Agent Gets

| Feature        | Service/Config                    | Details                                      |
| -------------- | --------------------------------- | -------------------------------------------- |
| User account   | `agent-{name}`                    | UID 4001+, group `agents`, no sudo           |
| Home directory | `/home/agent-{name}`              | chmod 2770, readable by `agent-admins` group |
| SSH agent      | `agent-{name}-ssh-agent.service`  | Auto-loads agenix key with passphrase        |
| Git signing    | `agent-{name}-git-config.service` | SSH-based commit signing                     |
| Desktop        | `agent-{name}-labwc.service`      | Headless Wayland (labwc + wayvnc)            |
| Browser        | `agent-{name}-chromium.service`   | Chromium with remote debugging               |
| Mail           | himalaya CLI                      | Stalwart IMAP/SMTP via agenix password       |
| Calendar       | calendula CLI                     | Stalwart CalDAV (auto-configured from mail)  |
| Contacts       | cardamum CLI                      | Stalwart CardDAV (auto-configured from mail) |
| Bitwarden      | `bw` CLI                          | Configured for Vaultwarden instance          |

## Debugging

### Git push fails with "Permission denied (publickey)"

1. **Check the SSH username** in any Forgejo remote — must be `forgejo@` for
   Forgejo's built-in SSH server.
2. **Verify the key is registered** in Forgejo under the correct user's SSH
   keys (auto-populated by `provision-agent-git.service` when `git.provision
   = true`).
3. **Check the SSH agent is running:**
   ```bash
   agentctl {name} status agent-{name}-ssh-agent
   ```
4. **Test manually:**
   ```bash
   sudo runuser -u agent-{name} -- ssh -vvv \
     -o StrictHostKeyChecking=accept-new \
     -p 2222 -T forgejo@git.example.com
   ```
5. **Check key fingerprint matches:**

   ```bash
   # Fingerprint of the agenix private key
   ssh-keygen -lf /run/agenix/agent-{name}-ssh-key

   # Compare with the public key in your config
   echo "ssh-ed25519 AAAAC3..." | ssh-keygen -lf -
   ```

## Terminal Environment Requirement

Any agent systemd service MUST have access to the full home-manager terminal
environment. The convention is to set each service's `PATH` to:

```
/etc/profiles/per-user/agent-{name}/bin:<nix>/bin:/run/current-system/sw/bin
```

so that bare commands (`yq`, `jq`, `bash`, `git`, `claude`, etc.) resolve via
the agent's home-manager profile rather than being individually pinned to Nix
store paths. This matches the pattern used by `agentSvcHelper` in `lib.nix`.

## Operational Conventions

### Email, Calendar, and Contacts

Agents have the full Pimalaya tool suite — himalaya (email), calendula (calendar), and cardamum (contacts). All auto-configured from the agent's mail credentials. See [Personal Information Management](personal-info-management.md) for usage details.

**Email (himalaya):**

- Always pipe email content via stdin, never use inline body arguments
- Use ASCII only — no unicode characters in email bodies
- Use `printf` with `\r\n` line endings (SMTP standard)
- Preview mode (`-p`) avoids marking messages as read

### Nested Claude Sessions

When spawning a nested Claude session from within a Claude process, unset the tracking variable to avoid conflicts:

```bash
unset CLAUDECODE
claude --print -p "prompt here"
```

### Nix Dev Shell

All agent tools are managed via the `flake.nix` dev shell. Never install tools globally — use `nix develop --command <cmd>` or direnv integration.

## Monitoring & Observability

Agents are monitored via **Loki** (for structured events and logs) and
**Prometheus** (for real-time health and success metrics). A standard
"Keystone OS Agents" dashboard is provisioned by the server-side Grafana
module.

Per-agent scripts emit structured logfmt events with fields like `event`,
`agent`, `host`, `unit`, `status`, and `duration_seconds`. The specific
metric and field surface tracks whichever runtime services are wired up on
the host — see the follow-up task-loop module documentation for the current
metric catalog.
