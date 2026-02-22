# SPEC-007: OS Agents

## Overview

- **Goal**: Enable LLM-driven agents to operate as first-class OS users with their own Wayland desktop, email, credentials, and SSH identity — all managed declaratively through Keystone's NixOS module system.
- **Scope**: User provisioning, headless Wayland desktop, Stalwart email, Bitwarden, Tailscale, Chrome + DevTools MCP, SSH key lifecycle, and agenix secrets management.
- **Relationship to SPEC-012**: SPEC-012 (Agent Sandbox) provides isolated MicroVM environments for code execution. SPEC-007 (OS Agents) provisions agents as native OS users on the host, giving them a full desktop, network identity, and service accounts. An OS agent may launch MicroVM sandboxes for code work, but the OS agent itself lives on the host.

## Problem Statement

Current agent sandboxes (SPEC-012) run in isolated MicroVMs with no persistent identity. They cannot:

1. Browse the web with a real browser session
2. Send or receive email
3. Authenticate to third-party services with their own credentials
4. Sign git commits with a verifiable identity
5. Be observed in real-time by a human operator viewing their desktop

OS agents need a persistent identity and environment that survives reboots, integrates with the host's service stack, and can be remotely observed over the mesh network.

## Functional Requirements

### FR-001: Agent User Provisioning

- Each agent is a standard NixOS user at `/home/agent-{name}`
- Created via `keystone.os.agents.{name}` option (parallel to `keystone.os.users`)
- Agent users are non-interactive (no password login at console)
- Agent users belong to a shared `agents` group
- UID allocation from a reserved range (e.g., 4000+) to avoid collision with human users
- Home directory created per storage backend (ZFS dataset or ext4 directory), matching existing `keystone.os.users` patterns

### FR-002: Headless Wayland Desktop

- Each agent gets its own Wayland compositor session (Cage, Sway headless, or similar minimal compositor)
- The compositor runs as a systemd user service under the agent's account
- A VNC or RDP server (wayvnc or similar) exposes the desktop for remote viewing
- The human operator can connect to the agent's desktop from:
  - The same machine (local VNC/RDP client)
  - A remote machine over Headscale (via the agent's tailnet IP)
- The desktop auto-starts on boot and restarts on crash
- Resolution and display settings are configurable per-agent

### FR-003: Chrome Browser with DevTools MCP

- Google Chrome (or Chromium) is installed and auto-launched on the agent's desktop
- Chrome starts with remote debugging enabled (`--remote-debugging-port`)
- The Chrome DevTools Protocol MCP server is configured and available to the LLM process
- Chrome profile is persistent in the agent's home directory
- Extensions can be pre-installed declaratively (e.g., Bitwarden browser extension)

### FR-004: Email via Stalwart

- Each agent gets a Stalwart mail account (e.g., `agent-{name}@{domain}`)
- IMAP/SMTP credentials are generated and stored in agenix
- A CLI mail client (himalaya or similar) is configured in the agent's environment
- The agent can send and receive email programmatically
- CalDAV/CardDAV access is provisioned alongside the mail account

### FR-005: Bitwarden Account

- Each agent has a Bitwarden account on the org's Vaultwarden instance
- API credentials (client ID, client secret) are stored in agenix
- The Bitwarden CLI (`bw`) is installed and pre-configured for the agent
- The agent can retrieve credentials programmatically without human intervention
- A dedicated Bitwarden collection scopes the agent's accessible secrets

### FR-006: Tailscale Identity

- Each agent has its own Tailscale auth key (pre-auth, reusable)
- The agent joins the Headscale/Tailscale network with a unique hostname (`agent-{name}`)
- The agent's desktop is reachable over the tailnet for remote viewing
- Auth keys are stored in agenix and rotated on a configurable schedule
- Firewall rules restrict the agent's network access to declared services only

### FR-007: SSH Key Management

- An ed25519 SSH keypair is generated for each agent at provisioning time
- The private key is encrypted with a passphrase (stored in agenix)
- An `ssh-agent` systemd user service auto-starts and unlocks the key using the passphrase from agenix
- The agent's SSH key is added to its own `~/.ssh/authorized_keys` (for sandbox access)
- Git is configured to use the SSH key for signing commits (`user.signingkey`, `gpg.format = ssh`)
- The public key is exported for registration on GitHub/GitLab/etc.

### FR-008: Agenix Secrets Management

All agent secrets are managed via agenix with a consistent structure:

- `/run/agenix/agent-{name}-ssh-key` - SSH private key
- `/run/agenix/agent-{name}-ssh-passphrase` - SSH key passphrase
- `/run/agenix/agent-{name}-mail-password` - Stalwart IMAP/SMTP password
- `/run/agenix/agent-{name}-bitwarden-client-secret` - Bitwarden API secret
- `/run/agenix/agent-{name}-tailscale-auth-key` - Tailscale pre-auth key

Secrets are:
- Encrypted to the host's SSH host key and the admin's personal key
- Readable only by the agent's user account (via agenix `owner`/`group`)
- Rotatable without reboot (systemd reload triggers re-decryption)

## Non-Functional Requirements

### NFR-001: Observability

- The human operator can list all running agent desktops and their connection URLs
- Desktop sessions are logged (session start/stop, crash restarts)
- A systemd target (`agent-desktops.target`) groups all agent desktop services

### NFR-002: Isolation

- Agents cannot access other agents' home directories
- Agents cannot read other agents' agenix secrets
- Agents cannot escalate to root (no sudo, no wheel group)
- Network egress is restricted per-agent via firewall rules

### NFR-003: Declarative Everything

- Adding a new agent requires only adding an entry to `keystone.os.agents.{name}`
- All provisioning (user, desktop, secrets, services) happens automatically on `nixos-rebuild switch`
- No imperative setup steps beyond initial agenix secret encryption

### NFR-004: Resource Limits

- Each agent's desktop session has configurable CPU and memory limits (via systemd resource control)
- Chrome's disk cache and memory are bounded
- Total agent resource consumption is capped at the system level

## Configuration Interface

```nix
keystone.os.agents.researcher = {
  fullName = "Research Agent";
  email = "researcher@ks.systems";

  desktop = {
    enable = true;
    compositor = "cage";        # cage | sway-headless
    resolution = "1920x1080";
    vnc.port = 5901;            # Each agent gets a unique port
  };

  chrome = {
    enable = true;
    debugPort = 9222;           # Chrome DevTools Protocol port
    extensions = [ ];           # Extension IDs to pre-install
    mcp.enable = true;          # Enable Chrome DevTools MCP server
  };

  mail = {
    enable = true;
    domain = "ks.systems";      # Stalwart domain
  };

  bitwarden = {
    enable = true;
    serverUrl = "https://vault.ks.systems";
    collection = "agent-researcher";  # Scoped collection
  };

  tailscale = {
    enable = true;
    hostname = "agent-researcher";
  };

  ssh = {
    keyType = "ed25519";
    gitSigningKey = true;       # Use SSH key for git commit signing
  };

  resources = {
    cpuQuota = "200%";          # 2 cores max
    memoryMax = "4G";
  };
};
```

## Architecture

```
┌──────────────────────────── Host Machine ─────────────────────────────┐
│                                                                       │
│  ┌─────────── Human User ───────────┐                                │
│  │  Hyprland Desktop                │                                │
│  │  VNC client → agent desktops     │                                │
│  └──────────────────────────────────┘                                │
│                                                                       │
│  ┌─── agent-researcher (uid 4001) ──┐  ┌── agent-coder (uid 4002) ──┐│
│  │  /home/agent-researcher/         │  │  /home/agent-coder/         ││
│  │                                  │  │                              ││
│  │  systemd user services:          │  │  systemd user services:      ││
│  │  ├── cage-desktop.service        │  │  ├── cage-desktop.service    ││
│  │  ├── wayvnc.service              │  │  ├── wayvnc.service          ││
│  │  ├── chrome.service              │  │  ├── chrome.service          ││
│  │  ├── ssh-agent.service           │  │  ├── ssh-agent.service       ││
│  │  └── chrome-devtools-mcp.service │  │  └── chrome-devtools-mcp    ││
│  │                                  │  │                              ││
│  │  agenix secrets:                 │  │  agenix secrets:             ││
│  │  ├── ssh key + passphrase        │  │  ├── ssh key + passphrase    ││
│  │  ├── mail credentials            │  │  ├── mail credentials        ││
│  │  ├── bitwarden API key           │  │  ├── bitwarden API key       ││
│  │  └── tailscale auth key          │  │  └── tailscale auth key      ││
│  └──────────────────────────────────┘  └──────────────────────────────┘│
│                                                                       │
│  ┌─────────── Host Services ────────────────────────────────────────┐ │
│  │  Stalwart Mail Server    (IMAP/SMTP for agent accounts)          │ │
│  │  Headscale / Tailscale   (mesh VPN, agent nodes)                 │ │
│  │  Vaultwarden             (Bitwarden server, agent collections)   │ │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘

Remote Observation (over Headscale):
  Laptop ──tailnet──▶ agent-researcher:5901 (VNC) ──▶ Cage desktop + Chrome
```

## Service Dependency Graph

```
multi-user.target
  └── agent-desktops.target
        ├── agent-researcher-desktop.service
        │     ├── cage (Wayland compositor)
        │     ├── wayvnc (VNC server, After=cage)
        │     ├── chrome (browser, After=cage)
        │     └── chrome-devtools-mcp (After=chrome)
        └── agent-coder-desktop.service
              └── (same structure)

user@4001.service (systemd user instance)
  ├── ssh-agent.service (auto-unlock key from agenix)
  └── (user-level services)
```

## Open Questions

1. **Compositor choice**: Cage is simplest (single-app kiosk), but Sway headless allows multi-window. Should agents have multi-window desktops or a Chrome-only kiosk?
2. **VNC vs RDP**: wayvnc is lightweight but RDP (via wlfreerdp) offers better performance. Which protocol to prioritize?
3. **Chrome vs Chromium**: Google Chrome includes proprietary codecs and sync. Chromium is pure open-source but lacks some features. Preference?
4. **Agent-to-agent communication**: Should agents be able to communicate with each other (e.g., shared mailbox, shared Bitwarden collection)?
5. **Lifecycle management**: Should there be a CLI (`keystone-agent-os`) for imperative operations (restart desktop, rotate keys, view logs)?

## Future Considerations

- Integration with SPEC-012 sandboxes: OS agents could launch MicroVM sandboxes for isolated code execution
- GPU passthrough for agents that need rendering or ML inference
- Audio capture/playback for agents that interact with voice interfaces
- Screen recording for audit trails of agent activity
- Multi-monitor support for agents working with complex UIs
