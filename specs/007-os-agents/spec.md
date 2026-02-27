# SPEC-007: OS Agents

## Overview

- **Goal**: Enable LLM-driven agents to operate as first-class OS users with their own Wayland desktop, email, credentials, and SSH identity — all managed declaratively through Keystone's NixOS module system.
- **Scope**: User provisioning, headless Wayland desktop, Stalwart email, Bitwarden, Tailscale, Chrome + DevTools MCP, SSH key lifecycle, and agenix secrets management.
## Problem Statement

LLM-driven agents currently lack persistent OS-level identity. They cannot:

1. Browse the web with a real browser session
2. Send or receive email
3. Authenticate to third-party services with their own credentials
4. Sign git commits with a verifiable identity
5. Be observed in real-time by a human operator viewing their desktop

OS agents need a persistent identity and environment that survives reboots, integrates with the host's service stack, and can be remotely observed over the mesh network.

## Functional Requirements

### FR-001: Agent User Provisioning

- The system MUST create each agent as a standard NixOS user at `/home/agent-{name}`
- The system MUST expose a `keystone.os.agents.{name}` option parallel to `keystone.os.users`
- Agent users MUST NOT have interactive password login at the console
- Agent users MUST belong to a shared `agents` group
- The system MUST allocate agent UIDs from a reserved range (e.g., 4000+) to avoid collision with human users
- The system MUST create the home directory per storage backend (ZFS dataset or ext4 directory), matching existing `keystone.os.users` patterns
- Each agent MUST have a home-manager configuration managed at the OS level (NixOS module, not standalone home-manager)
- Agent and human user home-manager configs MUST share common modules (terminal, git, shell) to avoid duplicating configuration
- Agent-specific home-manager options (e.g., `desktop.compositor`, MCP tools) SHOULD be layered on top of the shared base
- The `keystone.os.agents.{name}.terminal.enable` option MUST reuse the same `keystone.terminal` home-manager module used by `keystone.os.users`

### FR-002: Headless Wayland Desktop

- Each agent MUST have its own Wayland compositor session (Cage, Sway headless, or similar minimal compositor)
- The compositor MUST run as a systemd user service under the agent's account
- A VNC or RDP server (wayvnc or similar) MUST expose the desktop for remote viewing
- The human operator MUST be able to connect to the agent's desktop from:
  - The same machine (local VNC/RDP client)
  - A remote machine over Headscale (via the agent's tailnet IP)
- The desktop MUST auto-start on boot and restart on crash
- Resolution and display settings SHOULD be configurable per-agent

### FR-003: Chrome Browser with DevTools MCP

- The system MUST install Google Chrome (or Chromium) and auto-launch it on the agent's desktop
- Chrome MUST start with remote debugging enabled (`--remote-debugging-port`)
- The Chrome DevTools Protocol MCP server MUST be configured and available to the LLM process
- The Chrome profile MUST persist in the agent's home directory
- Extensions SHOULD be pre-installable declaratively (e.g., Bitwarden browser extension)

### FR-004: Email via Stalwart

- Each agent MUST have a Stalwart mail account (e.g., `agent-{name}@{domain}`)
- IMAP/SMTP credentials MUST be generated and stored in agenix
- A CLI mail client (himalaya or similar) MUST be configured in the agent's environment
- The agent MUST be able to send and receive email programmatically
- CalDAV/CardDAV access SHOULD be provisioned alongside the mail account

### FR-005: Bitwarden Account

- Each agent MUST have a Bitwarden account on the org's Vaultwarden instance
- API credentials (client ID, client secret) MUST be stored in agenix
- The Bitwarden CLI (`bw`) MUST be installed and pre-configured for the agent
- The agent MUST be able to retrieve credentials programmatically without human intervention
- A dedicated Bitwarden collection MUST scope the agent's accessible secrets

### FR-006: Tailscale Identity

- Each agent MUST have its own Tailscale auth key (pre-auth, reusable)
- The agent MUST join the Headscale/Tailscale network with a unique hostname (`agent-{name}`)
- The agent's desktop MUST be reachable over the tailnet for remote viewing
- Auth keys MUST be stored in agenix and SHOULD be rotated on a configurable schedule
- Firewall rules MUST restrict the agent's network access to declared services only

### FR-007: SSH Key Management

- The system MUST generate an ed25519 SSH keypair for each agent at provisioning time
- The private key MUST be encrypted with a passphrase stored in agenix
- An `ssh-agent` systemd user service MUST auto-start and unlock the key using the passphrase from agenix
- The agent's SSH key MUST be added to its own `~/.ssh/authorized_keys` (for sandbox access)
- Git MUST be configured to use the SSH key for signing commits (`user.signingkey`, `gpg.format = ssh`)
- The public key MUST be exported for registration on GitHub/GitLab/etc.

### FR-008: Agenix Secrets Management

The system MUST manage all agent secrets via agenix with a consistent structure:

- `/run/agenix/agent-{name}-ssh-key` — SSH private key
- `/run/agenix/agent-{name}-ssh-passphrase` — SSH key passphrase
- `/run/agenix/agent-{name}-mail-password` — Stalwart IMAP/SMTP password
- `/run/agenix/agent-{name}-bitwarden-client-secret` — Bitwarden API secret
- `/run/agenix/agent-{name}-tailscale-auth-key` — Tailscale pre-auth key

Secrets:
- MUST be encrypted to the host's SSH host key and the admin's personal key
- MUST be readable only by the agent's user account (via agenix `owner`/`group`)
- MUST be rotatable without reboot (systemd reload triggers re-decryption)

### FR-009: Agent Space — Workspace Structure

- The system MUST scaffold `/home/agent-{name}/agent-space/` as the agent's primary working directory
- The agent-space MUST be git-initialized with a Forgejo remote on the host (or configurable remote)
- The agent-space MUST contain the following standard files:
  - `TASKS.yaml` — Current task queue
  - `PROJECTS.yaml` — Projects the agent is responsible for
  - `ISSUES.yaml` — Known issues and incident log (see FR-014)
  - `SCHEDULES.yaml` — Recurring and scheduled work
  - `SOUL.md` — Agent identity, purpose, and behavioral guidelines
  - `HUMAN.md` — Human operator contact info, escalation procedures, and preferences
  - `AGENTS.md` — Operational context, conventions, and bespoke learnings
  - `ARCHITECTURE.md` — System architecture the agent operates within
  - `REQUIREMENTS.md` — Standing requirements and constraints
  - `SERVICES.md` — Services the agent can access (URLs, credentials references, MCP endpoints)
- The agent-space MUST contain a `.repos/` directory for cloned repositories
- The agent-space MUST contain a `logs/` directory for task execution logs
- The agent-space SHOULD contain a `flake.nix` providing the agent's dev shell
- Identity documents (`SOUL.md`, `HUMAN.md`) MUST be auto-populated from the `keystone.os.agents.{name}` configuration
- The agent MUST be able to commit and push changes to its agent-space repository

### FR-010: Task Loop — Autonomous Work Orchestration

- The system MUST provide a two-tier systemd timer architecture:
  - A scheduler timer (daily by default) that ingests new work from external sources
  - A task-loop timer (configurable interval, default every 15 minutes) that processes the task queue
- The scheduler MUST ingest tasks from configurable sources:
  - GitHub/Forgejo issues assigned to the agent
  - Email (via the agent's Stalwart account)
  - `SCHEDULES.yaml` recurring entries
- The task loop MUST follow an ingest → prioritize → execute cycle driven by the LLM
- The task loop MUST use lock management to prevent concurrent executions
- The task loop MUST implement configurable stop conditions (max tasks per run, max wall time, error threshold)
- The task loop MUST handle failures gracefully (log failure, mark task as failed, continue to next)
- The system SHOULD support a two-tier model strategy: a fast model for ingest/prioritize and a capable model for execute
- The task loop interval, stop conditions, and model configuration MUST be configurable per-agent

### FR-011: Audit Trail — Security Logging

- The system MUST maintain an immutable append-only audit log at `/var/log/agent-{name}/audit.jsonl`
- The audit log MUST record the following event types:
  - Git operations (clone, commit, push, fetch)
  - Email activity (send, receive)
  - Credential access (Bitwarden unlock, SSH key use)
  - Browser activity (URL navigations, downloads)
  - File modifications outside the agent's home directory (if any are permitted)
- Each log entry MUST use JSON Lines format with at minimum: `timestamp`, `event_type`, `details`, `outcome`
- The audit log file MUST be owned by root with the append-only attribute (`chattr +a`), preventing the agent from modifying or deleting entries
- Log rotation MUST be configured with a configurable retention period (default 90 days)
- The system SHOULD forward audit logs to Loki via Grafana Alloy when monitoring is enabled
- The system SHOULD define alert rules for suspicious patterns (e.g., credential access spikes, unexpected network egress)
- A NixOS assertion MUST prevent disabling audit logging when any agent is enabled

### FR-012: Security Testing — Isolation Verification

- The system MUST include a NixOS VM test that provisions 2+ agents and verifies:
  - Cross-agent home directory isolation (agent-a MUST NOT read agent-b's files)
  - Agenix secret isolation (agent-a MUST NOT read agent-b's secrets)
  - No sudo or wheel group membership
  - No write access to system paths (`/etc`, `/nix/store`, `/usr`)
  - Correct UID/GID assignment from the reserved range
  - Systemd cgroup resource limits are enforced
- The test MUST verify network isolation:
  - Egress firewall rules block undeclared destinations
  - VNC ports are accessible only from authorized sources
  - Each agent's Tailscale identity is distinct
- The test MUST verify credential scoping:
  - Each agent can only access its own Bitwarden collection
  - Each agent can only use its own SSH key
  - Each agent can only authenticate to its own IMAP/SMTP account
- The security test SHOULD run in CI on PRs that touch `modules/os/agents/`

### FR-013: Coding Subagent — Structured Code Contribution

- The system MUST provide a `keystone.os.agents.{name}.codingAgent.enable` option
- When enabled, the system MUST install a script at `~/bin/agent.coding-agent`
- The coding-agent script MUST perform pre-flight checks (repo exists, clean working tree, remote accessible)
- Branch naming MUST follow a configurable pattern (default: `agent-{name}/{slug}`)
- The agent contract MUST permit: creating commits, reading files, running tests
- The agent contract MUST NOT permit: pushing to remote, creating PRs, switching branches (the orchestrator handles these)
- The system SHOULD support automated review cycles (run linter/tests after each commit, retry on failure)
- PRs created by the orchestrator MUST be draft by default
- The coding-agent MUST support provider abstraction (Claude, Gemini, Codex, or other LLM backends)
- The coding-agent MUST clean up working state on exit (stash uncommitted changes, report summary)

### FR-014: Incident Log — Operational Learning

- Each agent's `ISSUES.yaml` MUST follow a structured schema with fields:
  - `name` — Short identifier
  - `description` — What happened
  - `discovered_during` — Task or context where the issue was found
  - `status` — `open`, `mitigated`, `resolved`
  - `severity` — `low`, `medium`, `high`, `critical`
  - `workaround` — Temporary mitigation (if any)
  - `fix` — Permanent resolution (if known)
- The agent's `AGENTS.md` MUST include a section referencing active incidents from `ISSUES.yaml`
- Agents on the same host SHOULD share a common incident database at `/var/lib/agent-incidents/`
- Critical incidents MUST trigger auto-escalation (email to operator via the agent's mail account, or configurable webhook)
- Known open issues MUST be injected into the agent's LLM context at task-loop startup

### FR-015: MCP Configuration — Tool Access

- The system MUST generate a `.mcp.json` in the agent's home directory from `keystone.os.agents.{name}.mcp` configuration
- The Chrome DevTools MCP server MUST run as a systemd user service that starts after Chrome and binds to localhost only
- Chrome MUST be started as a separate process outside the MCP server (the MCP server connects to an existing Chrome instance)
- The system MUST support configurable additional MCP servers via `keystone.os.agents.{name}.mcp.servers`
- MCP server processes MUST have health checks with automatic restart on failure
- MCP tool calls SHOULD be logged to the audit trail (FR-011)
- The `.mcp.json` MUST NOT contain secrets inline; credentials MUST be referenced from agenix paths

## Non-Functional Requirements

### NFR-001: Observability

- The system MUST allow the human operator to list all running agent desktops and their connection URLs
- Desktop sessions MUST be logged (session start/stop, crash restarts)
- A systemd target (`agent-desktops.target`) MUST group all agent desktop services

### NFR-002: Isolation

- Agents MUST NOT access other agents' home directories
- Agents MUST NOT read other agents' agenix secrets
- Agents MUST NOT be able to escalate to root (no sudo, no wheel group)
- Network egress MUST be restricted per-agent via firewall rules

### NFR-003: Declarative Everything

- Adding a new agent MUST require only adding an entry to `keystone.os.agents.{name}`
- All provisioning (user, desktop, secrets, services) MUST happen automatically on `nixos-rebuild switch`
- The system MUST NOT require imperative setup steps beyond initial agenix secret encryption

### NFR-004: Resource Limits

- Each agent's desktop session MUST have configurable CPU and memory limits (via systemd resource control)
- Chrome's disk cache and memory MUST be bounded
- Total agent resource consumption SHOULD be capped at the system level

## Open Questions

1. ~~**Compositor choice**: Cage is simplest (single-app kiosk), but Sway headless allows multi-window. Should agents have multi-window desktops or a Chrome-only kiosk?~~ **Resolved**: labwc — better wlroots headless backend support than Cage or Sway. Runs with `WLR_BACKENDS=headless` + `WLR_RENDERER=pixman`. Multi-window capable for future Chrome + other apps.
2. ~~**VNC vs RDP**: wayvnc is lightweight but RDP (via wlfreerdp) offers better performance. Which protocol to prioritize?~~ **Resolved**: wayvnc (VNC). Lightweight, Wayland-native, localhost-only by default. Remote access via SSH tunnel (`ssh -L 5901:127.0.0.1:5901`) or Tailscale. TLS support available but not yet configured.
3. ~~**Chrome vs Chromium**: Google Chrome includes proprietary codecs and sync. Chromium is pure open-source but lacks some features. Preference?~~ **Deferred**: Chrome/Chromium not yet implemented (Task 4). Decision will be made when FR-003 work begins.
4. **Agent-to-agent communication**: Should agents be able to communicate with each other (e.g., shared mailbox, shared Bitwarden collection)?
5. **Lifecycle management**: Should there be a CLI (`keystone-agent-os`) for imperative operations (restart desktop, rotate keys, view logs)?

## Future Considerations

- GPU passthrough for agents that need rendering or ML inference
- Audio capture/playback for agents that interact with voice interfaces
- Screen recording for audit trails of agent activity
- Multi-monitor support for agents working with complex UIs
