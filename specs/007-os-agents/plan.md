# SPEC-007: OS Agents — Implementation Plan

## Architecture Overview

### High-Level Design

The agent system extends the existing `keystone.os.users` pattern with a parallel `keystone.os.agents` option set. Agents are standard NixOS users with additional systemd user services for desktop, browser, task loop, and MCP. A shared `agents.nix` module in `modules/os/` mirrors the structure of `users.nix`.

```
keystone.os.agents.{name}
  ├── NixOS user (agent-{name}, uid 4000+, agents group)
  ├── Home-manager config (reuses keystone.terminal, adds agent-specific layers)
  ├── Systemd user services (desktop, chrome, ssh-agent, task-loop, MCP)
  ├── Agenix secrets (/run/agenix/agent-{name}-*)
  └── Agent-space (/home/agent-{name}/agent-space/, git-initialized)
```

### Architecture Diagram

```
┌──────────────────────────────── Host Machine ──────────────────────────────────┐
│                                                                                │
│  ┌─────────── Human User ───────────┐                                         │
│  │  Hyprland Desktop                │                                         │
│  │  VNC client → agent desktops     │                                         │
│  └──────────────────────────────────┘                                         │
│                                                                                │
│  ┌────────────── agent-researcher (uid 4001) ──────────────────────────────┐  │
│  │  /home/agent-researcher/                                                │  │
│  │                                                                         │  │
│  │  agent-space/                        systemd user services:             │  │
│  │  ├── TASKS.yaml                      ├── cage-desktop.service           │  │
│  │  ├── PROJECTS.yaml                   ├── wayvnc.service                 │  │
│  │  ├── ISSUES.yaml                     ├── chrome.service                 │  │
│  │  ├── SCHEDULES.yaml                  ├── chrome-devtools-mcp.service    │  │
│  │  ├── SOUL.md / HUMAN.md             ├── ssh-agent.service              │  │
│  │  ├── AGENTS.md / SERVICES.md        ├── task-loop.timer  (every 15m)   │  │
│  │  ├── .repos/                         └── scheduler.timer  (daily)       │  │
│  │  ├── logs/                                                              │  │
│  │  └── flake.nix                       agenix secrets:                    │  │
│  │                                      ├── ssh key + passphrase           │  │
│  │  .mcp.json (generated)               ├── mail credentials               │  │
│  │  bin/agent.coding-agent              ├── bitwarden API key              │  │
│  │                                      └── tailscale auth key             │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                                │
│  ┌─────────── Host Services ──────────────────────────────────────────────┐   │
│  │  Stalwart Mail Server    (IMAP/SMTP for agent accounts)                │   │
│  │  Headscale / Tailscale   (mesh VPN, agent nodes)                       │   │
│  │  Vaultwarden             (Bitwarden server, agent collections)         │   │
│  │  Forgejo                 (agent-space git remotes)                     │   │
│  └────────────────────────────────────────────────────────────────────────┘   │
│                                                                                │
│  ┌─────────── Audit & Monitoring ─────────────────────────────────────────┐   │
│  │  /var/log/agent-{name}/audit.jsonl   (root-owned, append-only)         │   │
│  │  /var/lib/agent-incidents/           (shared incident database)         │   │
│  │  Grafana Alloy → Loki               (log forwarding)                   │   │
│  └────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────┘

Remote Observation (over Headscale):
  Laptop ──tailnet──▶ agent-researcher:5901 (VNC) ──▶ Cage desktop + Chrome
```

### Configuration Interface

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

  # Agent space (FR-009)
  agentSpace = {
    enable = true;
    remote = "git@forgejo.local:agents/researcher.git";  # Git remote for agent-space
    flake.enable = true;        # Scaffold flake.nix in agent-space
  };

  # Task loop (FR-010)
  taskLoop = {
    enable = true;
    schedulerInterval = "daily";     # How often to ingest new work
    loopInterval = "15min";          # How often to process task queue
    maxTasksPerRun = 5;
    maxWallTime = "2h";
    errorThreshold = 3;              # Stop after N consecutive failures
    models = {
      ingest = "haiku";              # Fast model for triage
      execute = "sonnet";            # Capable model for task execution
    };
    sources = {
      github.enable = true;
      email.enable = true;
      schedules.enable = true;
    };
  };

  # Coding subagent (FR-013)
  codingAgent = {
    enable = true;
    branchPrefix = "agent-researcher";  # Branch naming: agent-researcher/slug
    provider = "claude";                # claude | gemini | codex
    autoReview = true;                  # Run linter/tests after each commit
    draftPR = true;                     # PRs are draft by default
  };

  # MCP configuration (FR-015)
  mcp = {
    servers = {
      # Additional MCP servers beyond Chrome DevTools
      grafana = {
        command = "grafana-mcp";
        args = [ "--url" "https://grafana.local" ];
      };
    };
  };
};
```

### Service Dependency Graph

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
  ├── task-loop.timer → task-loop.service (process task queue)
  ├── scheduler.timer → scheduler.service (ingest new work)
  └── mcp-*.service (additional MCP servers)

System services (root):
  ├── agent-audit@{name}.service (audit log writer)
  └── agent-audit-forward.service (Alloy → Loki)
```

### Component Responsibilities

- **`modules/os/agents.nix`** — Option definitions for `keystone.os.agents.{name}` (agent submodule type). Mirrors `default.nix`'s user submodule pattern. Imports agent sub-modules.
- **`modules/os/agents/`** — Directory of agent sub-modules, each handling one FR:
  - `users.nix` — FR-001: User creation, UID allocation, home directory, home-manager
  - `desktop.nix` — FR-002: Cage/Sway compositor, wayvnc, systemd user services
  - `chrome.nix` — FR-003: Chrome with remote debugging
  - `mail.nix` — FR-004: Stalwart account + himalaya CLI config
  - `bitwarden.nix` — FR-005: Vaultwarden account + bw CLI config
  - `tailscale.nix` — FR-006: Tailscale identity + firewall rules
  - `ssh.nix` — FR-007: SSH keypair + ssh-agent service + git signing
  - `secrets.nix` — FR-008: Agenix secret paths + assertions
  - `agent-space.nix` — FR-009: Workspace scaffold + git init
  - `task-loop.nix` — FR-010: Systemd timers + task loop script
  - `audit.nix` — FR-011: Audit log service + rotation + Loki forwarding
  - `coding-agent.nix` — FR-013: Coding subagent script + config
  - `incidents.nix` — FR-014: Shared incident database + escalation
  - `mcp.nix` — FR-015: .mcp.json generation + MCP server services
- **`tests/os-agents.nix`** — FR-012: NixOS VM test for isolation verification
- **`modules/os/agents/scripts/`** — Shell scripts used by systemd services (task-loop runner, audit logger, coding-agent wrapper)

### Integration Points

- **`modules/os/default.nix`** — Add `./agents.nix` to imports list, add `keystone.os.agents` option declaration
- **`modules/os/users.nix`** — No changes. Agents reuse the same home-manager modules (`keystone.terminal`, `keystone.desktop`) but through their own config path
- **`modules/os/mail.nix`** — Existing Stalwart module. Agent mail accounts are configured alongside human accounts
- **Agenix** — New secret files added to the repo's `secrets/` directory per agent
- **Home-manager** — Agent home-manager configs set `keystone.terminal.enable = true` and agent-specific options, reusing the shared terminal module

## Technology Stack

### Wayland Compositor
**Chosen**: Cage (default), Sway headless (optional)
**Rationale**: Cage is a single-application kiosk compositor — minimal, starts one app (Chrome) fullscreen. Sway headless is available for multi-window use cases. Both are in nixpkgs.

### VNC Server
**Chosen**: wayvnc
**Rationale**: Lightweight Wayland-native VNC server. Already packaged in nixpkgs. Binds to a configurable port per agent.

### Task Loop
**Chosen**: Bash script driven by systemd timers, invoking LLM CLI (claude, gemini, etc.)
**Rationale**: Systemd timers are the NixOS-native scheduling mechanism. The script handles lock files, stop conditions, and model dispatch. No external scheduler dependencies.

### Audit Logging
**Chosen**: JSON Lines to `/var/log/agent-{name}/audit.jsonl`, root-owned with `chattr +a`
**Rationale**: Append-only files prevent agent tampering. JSON Lines is grep-friendly and parseable by Loki/Alloy. Log rotation via logrotate.

### MCP Servers
**Chosen**: Chrome DevTools MCP as systemd user service, additional servers configurable
**Rationale**: Systemd manages lifecycle, health checks via `RestartSec` + `Restart=on-failure`. `.mcp.json` generated from Nix config.

## File Structure

### New Files

```
modules/os/
├── agents.nix                      # Option declarations for keystone.os.agents
└── agents/
    ├── default.nix                 # Imports all agent sub-modules
    ├── users.nix                   # FR-001: User provisioning + home-manager
    ├── desktop.nix                 # FR-002: Cage/Sway + wayvnc
    ├── chrome.nix                  # FR-003: Chrome + DevTools
    ├── mail.nix                    # FR-004: Stalwart account + himalaya
    ├── bitwarden.nix               # FR-005: Vaultwarden + bw CLI
    ├── tailscale.nix               # FR-006: Tailscale identity
    ├── ssh.nix                     # FR-007: SSH keys + ssh-agent
    ├── secrets.nix                 # FR-008: Agenix paths + assertions
    ├── agent-space.nix             # FR-009: Workspace scaffold
    ├── task-loop.nix               # FR-010: Systemd timers
    ├── audit.nix                   # FR-011: Audit logging
    ├── coding-agent.nix            # FR-013: Coding subagent
    ├── incidents.nix               # FR-014: Incident log
    ├── mcp.nix                     # FR-015: MCP configuration
    └── scripts/
        ├── scaffold-agent-space.sh # Agent-space git init + file creation
        ├── task-loop.sh            # Task loop runner (ingest/prioritize/execute)
        ├── audit-logger.sh         # Audit event writer
        └── coding-agent.sh         # Coding subagent wrapper

tests/
└── os-agents.nix                   # FR-012: NixOS VM isolation test
```

### Modified Files

- `modules/os/default.nix` — Add `keystone.os.agents` option (attrsOf agentSubmodule), add `./agents.nix` to imports
- `flake.nix` — Add `tests/os-agents.nix` to checks (if not auto-discovered)

## Implementation Strategy

### Phase 1: Core User Provisioning (FR-001 + FR-008 + FR-012 partial)

The foundation everything else builds on. Create the agent user, home directory, home-manager integration, and agenix secret structure. Write the first VM test proving the user exists with correct properties.

**Why first**: Every other FR depends on having an agent user. The VM test establishes the testing pattern used throughout.

**Deliverables**:
- `modules/os/agents.nix` — Option declarations
- `modules/os/agents/default.nix` — Sub-module imports
- `modules/os/agents/users.nix` — User creation + home-manager (reusing `keystone.terminal`)
- `modules/os/agents/secrets.nix` — Agenix path conventions + assertions
- `tests/os-agents.nix` — VM test: user exists, UID range, agents group, no wheel, home dir exists, no password login
- Update `modules/os/default.nix` to import agents

### Phase 2: Desktop + Browser (FR-002 + FR-003)

Give agents a visible desktop with Chrome for web interaction.

**Why second**: Desktop + Chrome is the highest-value capability — it enables web browsing, which most agent tasks require.

**Deliverables**:
- `modules/os/agents/desktop.nix` — Cage compositor + wayvnc as systemd user services
- `modules/os/agents/chrome.nix` — Chrome with `--remote-debugging-port` as systemd user service
- Extend VM test: compositor running, VNC port listening, Chrome process active

### Phase 3: Identity + Credentials (FR-004 + FR-005 + FR-006 + FR-007)

Connect agents to external services: email, password vault, mesh network, git.

**Why third**: These are independent of each other but all depend on Phase 1's user + secrets. Can be developed in parallel.

**Deliverables**:
- `modules/os/agents/mail.nix` — Stalwart account config + himalaya
- `modules/os/agents/bitwarden.nix` — Vaultwarden + bw CLI
- `modules/os/agents/tailscale.nix` — Tailscale identity + firewall
- `modules/os/agents/ssh.nix` — SSH keypair + ssh-agent + git signing
- Extend VM test: SSH agent running, git signing configured

### Phase 4: Agent Space + MCP (FR-009 + FR-015)

Set up the agent's workspace and tool access.

**Why fourth**: Agent-space provides the working directory for task execution. MCP provides the tool interface. Both are prerequisites for the task loop.

**Deliverables**:
- `modules/os/agents/agent-space.nix` — Scaffold script + systemd oneshot
- `modules/os/agents/scripts/scaffold-agent-space.sh` — Git init, file creation, identity population
- `modules/os/agents/mcp.nix` — `.mcp.json` generation + Chrome DevTools MCP service
- Extend VM test: agent-space directory exists with expected files, .mcp.json generated

### Phase 5: Task Loop + Audit (FR-010 + FR-011)

Enable autonomous operation with security logging.

**Why fifth**: Task loop is the agent's execution engine. Audit trail is mandatory security (assertion prevents disabling). Both depend on agent-space existing.

**Deliverables**:
- `modules/os/agents/task-loop.nix` — Systemd timers (scheduler + loop)
- `modules/os/agents/scripts/task-loop.sh` — Lock management, stop conditions, model dispatch
- `modules/os/agents/audit.nix` — Audit log service, logrotate, Loki forwarding config
- `modules/os/agents/scripts/audit-logger.sh` — Append events to audit.jsonl
- Extend VM test: timers active, audit.jsonl exists and is root-owned + append-only

### Phase 6: Coding Subagent + Incidents (FR-013 + FR-014)

Structured code contribution and operational learning.

**Why last**: These are higher-level operational features that build on everything below them.

**Deliverables**:
- `modules/os/agents/coding-agent.nix` — Option + script installation
- `modules/os/agents/scripts/coding-agent.sh` — Pre-flight, branch naming, agent contract, cleanup
- `modules/os/agents/incidents.nix` — ISSUES.yaml schema validation, shared database, escalation
- Extend VM test: coding-agent script exists, incident database path exists

### Phase 7: Full Security Test Suite (FR-012 complete)

Expand the VM test to cover all isolation and credential scoping requirements.

**Why last**: The full test suite needs all features to be implemented before it can verify cross-cutting concerns.

**Deliverables**:
- Complete `tests/os-agents.nix` with:
  - Cross-agent home directory isolation (2+ agents)
  - Agenix secret isolation
  - Network egress rules
  - VNC port isolation
  - Credential scoping (Bitwarden collection, SSH key, IMAP/SMTP)
  - Cgroup resource limits

## Security Considerations

| Spec Requirement | Implementation |
|---|---|
| NFR-002: Agent isolation | Separate NixOS users, `chmod 700` home dirs, agenix `owner`/`group` per-agent |
| NFR-002: No root escalation | Assertions: agent users MUST NOT be in `wheel`. No `sudo` config. |
| FR-011: Tamper-proof audit | Root-owned `/var/log/agent-{name}/`, `chattr +a` on audit.jsonl, NixOS assertion preventing disable |
| FR-008: Secret scoping | Each secret has explicit `owner = "agent-{name}"` in agenix config |
| FR-006: Network restriction | Per-agent iptables/nftables rules via `networking.firewall.extraCommands` |
| FR-015: No inline secrets | `.mcp.json` references agenix paths, not plaintext credentials |

## Testing Strategy

| Test Type | What It Covers | Files |
|---|---|---|
| NixOS VM test (Phase 1) | User exists, UID range, groups, no password, home dir | `tests/os-agents.nix` |
| NixOS VM test (Phase 2) | Desktop services running, VNC listening, Chrome process | `tests/os-agents.nix` |
| NixOS VM test (Phase 7) | Full isolation: cross-agent, secrets, network, credentials | `tests/os-agents.nix` |
| CI integration | Run `tests/os-agents.nix` on PRs touching `modules/os/agents/` | `.github/workflows/` or `flake.nix` checks |

All tests use NixOS `nixosTest` — no external test framework needed. Tests provision a VM with 2+ agents and run assertions inside the VM via `machine.succeed()` / `machine.fail()`.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Cage/wayvnc not stable enough for long-running sessions | Desktop crashes, agent loses browser state | Systemd `Restart=always` + `RestartSec=5`. Chrome profile persists on disk. |
| Task loop LLM API costs | Unexpected spend from frequent polling | Configurable interval, max tasks per run, error threshold stop condition |
| Agenix secret rotation requires rebuild | Downtime during key rotation | `systemd reload` triggers re-decryption without full rebuild |
| Audit log disk usage | Fills disk on active agents | Logrotate with configurable retention (default 90 days), compression |
| Chrome DevTools port exposure | Unauthorized access to agent browser | Bind to localhost only, firewall rules block external access |

## Related Documents

- Spec: `spec.md`
