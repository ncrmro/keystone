# SPEC-007: OS Agents — Implementation Plan

## Architecture Overview

### High-Level Design

The agent system extends the existing `keystone.os.users` pattern with a parallel `keystone.os.agents` option set. Agents are standard NixOS users with systemd system services (using `User=` directives) for desktop and VNC, plus future systemd user services for browser, task loop, and MCP. A single `agents.nix` module in `modules/os/` consolidates all agent logic.

```
keystone.os.agents.{name}
  ├── NixOS user (agent-{name}, uid 4000+, agents group)
  ├── Systemd system services (labwc desktop, wayvnc — with User= directive)
  ├── Future: home-manager config (keystone.terminal reuse)
  ├── Future: agenix secrets (/run/agenix/agent-{name}-*)
  └── Future: agent-space (/home/agent-{name}/agent-space/, git-initialized)
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
│  │  agent-space/                        systemd services:                  │  │
│  │  ├── TASKS.yaml                      ├── labwc-agent-{name}.service     │  │
│  │  ├── PROJECTS.yaml                   ├── wayvnc-agent-{name}.service    │  │
│  │  ├── ISSUES.yaml                     ├── chromium-agent-{name}.service  │  │
│  │  ├── SCHEDULES.yaml                  ├── chrome-devtools-mcp.service    │  │
│  │  ├── SOUL.md / HUMAN.md             ├── ssh-agent.service              │  │
│  │  ├── AGENTS.md / SERVICES.md        ├── task-loop.timer  (every 15m)   │  │
│  │  ├── .repos/                         └── scheduler.timer  (daily)       │  │
│  │  ├── logs/                                                              │  │
│  │  └── flake.nix                       per-agent tailscaled:              │  │
│  │                                      ├── tailscaled-agent-researcher    │  │
│  │  .mcp.json (generated)               ├── TUN: tailscale-agent-…          │  │
│  │  bin/agent.coding-agent              └── socket: /run/tailscale/...     │  │
│  │                                                                         │  │
│  │                                      agenix secrets:                    │  │
│  │                                      ├── ssh key + passphrase           │  │
│  │                                      ├── mail credentials               │  │
│  │                                      ├── bitwarden password             │  │
│  │                                      └── tailscale auth key             │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                                │
│  ┌─────────── nftables Network Isolation (FR-016) ───────────────────────┐   │
│  │  Per-UID output rules:                                                │   │
│  │  ├── skuid 4001 → block ports 5902, 9223, ... (other agents)         │   │
│  │  ├── skuid 4002 → block ports 5901, 9222, ... (other agents)         │   │
│  │  └── Generated declaratively from agent config (UIDs, ports)          │   │
│  │  Per-UID fwmark routing:                                              │   │
│  │  ├── uid 4001 → fwmark 0x1001 → tailscale-agent-researcher           │   │
│  │  └── uid 4002 → fwmark 0x1002 → tailscale-agent-coder                │   │
│  └────────────────────────────────────────────────────────────────────────┘   │
│                                                                                │
│  ┌─────────── Host Services (via Tailscale ACLs, not localhost) ─────────┐   │
│  │  Stalwart Mail Server    (IMAP/SMTP for agent accounts)                │   │
│  │  Headscale / Tailscale   (mesh VPN, per-agent nodes)                   │   │
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

Remote Observation (over Headscale or SSH tunnel):
  Laptop ──tailnet──▶ agent-researcher:5901 (VNC) ──▶ labwc desktop + Chromium
  Laptop ──ssh -L──▶ host:5901 (localhost) ──▶ labwc desktop + Chromium
  Each agent has its own tailscaled → own tailnet IP → own Headscale ACLs
```

### Configuration Interface

```nix
keystone.os.agents.researcher = {
  fullName = "Research Agent";
  email = "researcher@ks.systems";

  desktop = {
    enable = true;
    # Compositor: labwc with WLR_BACKENDS=headless (resolved from Open Question 1)
    resolution = "1920x1080";
    vncPort = 5901;             # Each agent gets a unique port (auto-assigned if null)
  };

  chrome = {
    enable = true;
    debugPort = null;           # null = auto-assign from base 9222 (avoids conflicts)
    extensions = [ ];           # Extension IDs to pre-install
    mcp = {
      enable = true;            # Enable Chrome DevTools MCP server
      port = null;              # null = auto-assign MCP server port
    };
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
    # Per-agent tailscaled instance (FR-006):
    # - Unique state dir, socket, TUN interface
    # - UID-based fwmark routing through agent's TUN
    # - CLI wrapper auto-specifies --socket
  };

  networking = {
    isolation = true;           # FR-016: full inter-agent traffic block (default: true)
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
  ├── create-agent-homes.service (ext4) or zfs-agent-datasets.service (ZFS)
  ├── agent-desktops.target
  │     ├── labwc-agent-researcher.service  (system service, User=agent-researcher)
  │     │     └── Requires: create-agent-homes.service
  │     ├── wayvnc-agent-researcher.service (system service, User=agent-researcher)
  │     │     ├── Requires: labwc-agent-researcher.service
  │     │     └── ExecStartPre: polls for wayland-0 socket (up to 10s)
  │     ├── chromium-agent-researcher.service (After=labwc, User=agent-researcher)
  │     └── chrome-devtools-mcp-agent-researcher.service (After=chromium)
  │
  ├── tailscaled-agent-researcher.service (per-agent tailscaled instance)
  ├── tailscaled-agent-coder.service
  │
  └── nftables.service (UID-based isolation rules, FR-016)

(future) user@{uid}.service (systemd user instance)
  ├── ssh-agent.service (auto-unlock key from agenix)
  ├── task-loop.timer → task-loop.service (process task queue)
  ├── scheduler.timer → scheduler.service (ingest new work)
  └── mcp-*.service (additional MCP servers)

(future) System services (root):
  ├── agent-audit@{name}.service (audit log writer)
  └── agent-audit-forward.service (Alloy → Loki)
```

> **Note on system vs user services**: The plan originally called for systemd user services, but implementation uses system services with `User=` directives. This avoids the complexity of systemd-logind linger sessions and user service bootstrap ordering. The XDG_RUNTIME_DIR is managed via `RuntimeDirectory=` in the service config.

### Component Responsibilities

- **`modules/os/agents.nix`** — Single consolidated module handling FR-001 (user provisioning), FR-002 (labwc desktop + wayvnc), and option declarations for the `keystone.os.agents.{name}` submodule type. Includes UID auto-assignment, VNC port auto-assignment, ext4/ZFS home directory creation, labwc config generation, and systemd service definitions.
- **`tests/module/agent-isolation.nix`** — FR-012: NixOS VM test for isolation verification (19 assertions)
- **Future sub-modules** (will be extracted from `agents.nix` or added as new files as complexity grows):
  - `chrome.nix` — FR-003: Chrome with remote debugging
  - `mail.nix` — FR-004: Stalwart account + himalaya CLI config
  - `bitwarden.nix` — FR-005: Vaultwarden account + bw CLI config
  - `tailscale.nix` — FR-006: Per-agent tailscaled instances + CLI wrapper + fwmark routing
  - `network-isolation.nix` — FR-016: nftables UID-based inter-agent traffic block
  - `ssh.nix` — FR-007: SSH keypair + ssh-agent service + git signing
  - `secrets.nix` — FR-008: Agenix secret paths + assertions
  - `agent-space.nix` — FR-009: Workspace scaffold + git init
  - `task-loop.nix` — FR-010: Systemd timers + task loop script
  - `audit.nix` — FR-011: Audit log service + rotation + Loki forwarding
  - `coding-agent.nix` — FR-013: Coding subagent script + config
  - `incidents.nix` — FR-014: Shared incident database + escalation
  - `mcp.nix` — FR-015: .mcp.json generation + MCP server services
  - `scripts/` — Shell scripts used by systemd services

### Integration Points

- **`modules/os/default.nix`** — Add `./agents.nix` to imports list, add `keystone.os.agents` option declaration
- **`modules/os/users.nix`** — No changes. Agents reuse the same home-manager modules (`keystone.terminal`, `keystone.desktop`) but through their own config path
- **`modules/os/mail.nix`** — Existing Stalwart module. Agent mail accounts are configured alongside human accounts
- **Agenix** — New secret files added to the repo's `secrets/` directory per agent
- **Home-manager** — Agent home-manager configs set `keystone.terminal.enable = true` and agent-specific options, reusing the shared terminal module

## Technology Stack

### Wayland Compositor
**Chosen**: labwc (resolved from Open Question 1)
**Rationale**: labwc provides better wlroots headless backend support than Cage or Sway. Runs with `WLR_BACKENDS=headless` and `WLR_RENDERER=pixman` (software renderer, no GPU needed). Creates a virtual `HEADLESS-1` output via autostart script with `wlr-randr`. Supports multi-window layouts for future Chromium + other apps. Already packaged in nixpkgs with `programs.labwc.enable`.

### VNC Server
**Chosen**: wayvnc
**Rationale**: Lightweight Wayland-native VNC server. Already packaged in nixpkgs. Binds to a configurable port per agent. Supports Tailscale-only binding via `vncTailscale` option.

### Browser
**Chosen**: Chromium
**Rationale**: Open-source, well-packaged in nixpkgs, no proprietary codec dependency for agent use cases. Chrome DevTools Protocol fully supported.

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

### Current Files (Phases 1-2 complete)

```
modules/os/
└── agents.nix                      # Consolidated module: FR-001 (provisioning) + FR-002 (labwc desktop)

tests/module/
└── agent-isolation.nix             # FR-012: NixOS VM isolation test (19 assertions)
```

### Future Files (Phases 3-7)

As features are added, the consolidated `agents.nix` may be split into sub-modules:

```
modules/os/
├── agents.nix                      # Core options + user provisioning + desktop
└── agents/                         # (future) Sub-modules extracted as complexity grows
    ├── chrome.nix                  # FR-003: Chrome + DevTools
    ├── mail.nix                    # FR-004: Stalwart account + himalaya
    ├── bitwarden.nix               # FR-005: Vaultwarden + bw CLI
    ├── tailscale.nix               # FR-006: Per-agent Tailscale instances
    ├── network-isolation.nix       # FR-016: nftables UID-based isolation
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
```

### Modified Files

- `modules/os/default.nix` — Added `./agents.nix` to imports
- `tests/flake.nix` — Added `test-agent-isolation` to checks
- `flake.nix` — Wired `tests/flake.nix` checks into top-level flake

## Development Methodology

Development follows a **red-green cycle** driven by `tests/module/agent-isolation.nix`, a single NixOS VM test that grows with each phase.

### Why this works

- `nixosTest` VMs mount the host `/nix/store` via 9p — no copying, fast boot (~10s)
- Phase 1 modules are pure Nix config (users, groups, file generation) — no large packages to build
- One test file with two agents (`researcher` + `coder`) plus one human user (`testuser`) enables isolation assertions immediately
- Uses `pkgs.testers.nixosTest` directly (simpler than `tests/lib.nix` helpers for this use case)

### Workflow per phase

1. **Red** — Write failing assertions in `tests/module/agent-isolation.nix` for the phase's requirements
2. **Green** — Implement the module until all assertions pass
3. **Refactor** — Clean up, then commit both test and module together
4. Run via `nix build .#test-agent-isolation`

### Test structure

A single `tests/module/agent-isolation.nix` file provisions a VM with 2 agents + 1 human user and runs all assertions. Each phase adds `machine.succeed()` / `machine.fail()` calls to the test script.

### Wiring

- `test-agent-isolation` registered in `tests/flake.nix` checks
- Build via `nix build .#test-agent-isolation`
- Interactive debugging via `nix build .#test-agent-isolation.driverInteractive`

## Implementation Strategy

### Phase 1: Core User Provisioning (FR-001 + FR-012 partial) — COMPLETE

The foundation everything else builds on.

**Implemented** (PR #70):
- `modules/os/agents.nix` — Consolidated module with option declarations, user creation, UID auto-assignment, ext4/ZFS home directory setup
- `tests/module/agent-isolation.nix` — 11 assertions: user existence, UIDs, groups, permissions, ownership, cross-agent isolation, agent-human isolation, sudo restrictions, system path write restrictions

**Deferred**: FR-008 (agenix secrets), home-manager integration

### Phase 2: Headless Desktop (FR-002)

**FR-002 COMPLETE** (PR #71):
- labwc compositor with `WLR_BACKENDS=headless` and `WLR_RENDERER=pixman`
- wayvnc with Wayland socket polling (up to 10s, 100ms intervals)
- 8 additional runtime assertions in the VM test (19 total)
- VNC binds to 127.0.0.1 only (SSH tunnel or Tailscale for remote access)

### Phase 2.5: Chrome + MCP (FR-003)

Add browser with DevTools MCP for web interaction.

**Red** — Uncomment assertions: Chromium process active, debug port responding, MCP service running.

**Green** — Implement:
- `modules/os/agents/chrome.nix` — Chromium systemd service (`After=labwc-agent-{name}.service`), debug port auto-assignment (base 9222, like VNC base 5900)
- Chrome DevTools MCP: Nix derivation wrapping `chrome-devtools-mcp` npm package (pinned version), systemd service (`After=chromium-agent-{name}.service`), connects to agent's Chrome debug port, localhost binding only

### Phase 3: Identity + Credentials + Network Isolation (FR-004 + FR-005 + FR-006 + FR-007 + FR-016)

Connect agents to external services and enforce network isolation.

**Red** — Uncomment assertions: SSH agent running, git signing configured, mail client available, per-agent tailscaled running, inter-agent traffic blocked.

**Green** — Implement (can be developed in parallel, all depend on Phase 1):
- `modules/os/agents/mail.nix` — Stalwart account config + himalaya
- `modules/os/agents/bitwarden.nix` — Vaultwarden + bw CLI
- `modules/os/agents/tailscale.nix` — Per-agent `tailscaled` instances with unique state/socket/TUN, nftables fwmark routing per UID, tailscale CLI wrapper with auto `--socket`
- `modules/os/agents/ssh.nix` — SSH keypair + ssh-agent + git signing
- `modules/os/agents/network-isolation.nix` — nftables ruleset generated from agent UIDs, full inter-agent block (all traffic, not just VNC/Chrome), declarative from agent config

### Phase 4: Agent Space + MCP (FR-009 + FR-015)

Set up the agent's workspace and tool access.

**Red** — Uncomment assertions: agent-space directory exists with expected files, `.mcp.json` generated.

**Green** — Implement:
- `modules/os/agents/agent-space.nix` — Scaffold script + systemd oneshot
- `modules/os/agents/scripts/scaffold-agent-space.sh` — Git init, file creation, identity population
- `modules/os/agents/mcp.nix` — `.mcp.json` generation + Chrome DevTools MCP service

### Phase 5: Task Loop + Audit (FR-010 + FR-011)

Enable autonomous operation with security logging.

**Red** — Uncomment assertions: timers active, audit.jsonl exists and is root-owned + append-only.

**Green** — Implement:
- `modules/os/agents/task-loop.nix` — Systemd timers (scheduler + loop)
- `modules/os/agents/scripts/task-loop.sh` — Lock management, stop conditions, model dispatch
- `modules/os/agents/audit.nix` — Audit log service, logrotate, Loki forwarding config
- `modules/os/agents/scripts/audit-logger.sh` — Append events to audit.jsonl

### Phase 6: Coding Subagent + Incidents (FR-013 + FR-014)

Structured code contribution and operational learning.

**Red** — Uncomment assertions: coding-agent script exists, incident database path exists.

**Green** — Implement:
- `modules/os/agents/coding-agent.nix` — Option + script installation
- `modules/os/agents/scripts/coding-agent.sh` — Pre-flight, branch naming, agent contract, cleanup
- `modules/os/agents/incidents.nix` — ISSUES.yaml schema validation, shared database, escalation

### Phase 7: Full Security Test Suite (FR-012 complete)

Final red-green pass: uncomment all remaining security assertions and fill any gaps.

- Cross-agent home directory isolation (already tested from Phase 1)
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
| FR-006: Network routing | Per-agent `tailscaled` instances with UID-based fwmark routing through dedicated TUN interfaces |
| FR-016: Inter-agent isolation | nftables UID-based output rules blocking all inter-agent traffic, generated declaratively from agent config |
| FR-015: No inline secrets | `.mcp.json` references agenix paths, not plaintext credentials |

## Testing Strategy

All testing is driven by **one growing test file** (`tests/module/agent-isolation.nix`) as described in Development Methodology above. The test provisions a VM with 2 agents + 1 human user and runs assertions via `machine.succeed()` / `machine.fail()`.

| Phase | Assertions | Status |
|---|---|---|
| 1 | User exists, UID >= 4000, `agents` group, no `wheel`, home dir 700, ownership, cross-agent isolation, agent-human isolation, human-agent isolation, no sudo, no system writes, write to own home | **Complete** (11 assertions) |
| 2 | labwc service active, Wayland socket created, wayvnc active, VNC port open, wlr-randr headless output, config files + ownership, VNC localhost-only, non-desktop agent clean | **Complete** (8 assertions) |
| 2.5 | Chromium process active, debug port responding, MCP service running, port auto-assignment | Pending |
| 3 | SSH agent running, git signing configured, mail client available, per-agent tailscaled running, inter-agent traffic blocked (nftables) | Pending |
| 4 | Agent-space directory + expected files, `.mcp.json` generated | Pending |
| 5 | Timers active, audit.jsonl root-owned + append-only | Pending |
| 6 | Coding-agent script exists, incident database path exists | Pending |
| 7 | Full cross-cutting security: secret isolation, network egress, credential scoping, cgroup limits, nftables UID rules | Pending |

CI runs `tests/module/agent-isolation.nix` on PRs touching `modules/os/agents*`.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| labwc/wayvnc not stable enough for long-running sessions | Desktop crashes, agent loses browser state | Systemd `Restart=always` + `RestartSec=5`. Chrome profile persists on disk. |
| Task loop LLM API costs | Unexpected spend from frequent polling | Configurable interval, max tasks per run, error threshold stop condition |
| Agenix secret rotation requires rebuild | Downtime during key rotation | `systemd reload` triggers re-decryption without full rebuild |
| Audit log disk usage | Fills disk on active agents | Logrotate with configurable retention (default 90 days), compression |
| Chrome DevTools port exposure | Unauthorized access to agent browser | Bind to localhost only, nftables UID rules block cross-agent access (FR-016), Tailscale ACLs for remote access |
| Per-agent tailscaled complexity | Multiple TUN interfaces, fwmark routing tables | Declarative Nix config generates all nftables/routing rules; test in VM with 2+ agents |

## Related Documents

- Spec: `spec.md`
