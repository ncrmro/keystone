# SPEC-007: OS Agents — Tasks

## Overview

**Total Tasks**: 19
**Phases**: 8
**Parallelizable**: 8

Note: This spec uses functional requirements (FR-NNN) rather than user stories. Tasks reference FRs directly.

## Task Dependency Graph

```
Phase 1:    [1] → [2]
Phase 2:    [3]  (depends on Phase 1)
Phase 2.5:  [4a] → [4b]  (depends on Phase 2)
Phase 3:    [5] [P] [6] [P] [7] [P] [8] [P] [9] [10]  (5-8 depend on Phase 1, 9 depends on 7, 10 depends on 5-8)
Phase 4:    [11] → [12]  (depends on Phase 1)
Phase 5:    [13] [P] [14] [P]  (13 depends on Phase 4, 14 depends on Phase 1)
Phase 6:    [15] [P] [16] [P]  (depend on Phase 4+5)
Phase 7:    [17] → [18]  (depends on all above)
```

---

## Phase 1: Core User Provisioning

### Task 1: Agent Option Declarations + User Creation [FR-001] [FR-008]

**Type**: Infrastructure
**Dependencies**: None

**Description:**
Create the `keystone.os.agents` option set in `modules/os/default.nix` and implement the agent user provisioning module. The agent submodule type mirrors the existing `userSubmodule` in `default.nix` but with agent-specific defaults (no password, `agents` group, UID 4000+ range). Include agenix secret path conventions and assertions. Wire up home-manager to reuse `keystone.terminal` for agent configs.

**Files Created/Modified:**
- `modules/os/agents.nix` — Single consolidated module with option declarations, user creation, home directory setup (ZFS + ext4), and desktop services

> **Deviation from plan**: Implemented as a single `agents.nix` file instead of `agents/` directory with 14 sub-files. The consolidated approach keeps all agent logic co-located and avoids premature abstraction while the feature set is small. Sub-modules can be extracted later as complexity grows.

**Acceptance Criteria:**
- [x] `keystone.os.agents.researcher = { fullName = "Research Agent"; email = "researcher@test.local"; }` is a valid config
- [x] Agent user `agent-researcher` is created with UID >= 4000
- [x] Agent user belongs to `agents` group
- [x] Agent user has no password and is not in `wheel`
- [x] Home directory exists at `/home/agent-researcher` with `chmod 700`
- [ ] Home-manager config reuses `keystone.terminal` module *(deferred — agents don't use home-manager yet)*
- [ ] Agenix assertions verify secret ownership *(deferred — secrets.nix not implemented yet)*

**Validation:**
Run `nix eval` on a test config to verify option evaluation succeeds without errors.

---

### Task 2: Agent Provisioning VM Test [FR-012 partial]

**Type**: Test
**Dependencies**: Task 1

**Description:**
Create a NixOS VM test that declares 2 agents and verifies the core provisioning from Task 1. This establishes the test pattern expanded in later phases.

**Files Created:**
- `tests/module/agent-isolation.nix` — NixOS VM test with 2 agents (`researcher` and `coder`) + 1 human user, 19 assertions covering both eval and runtime

> **Deviation from plan**: Test file at `tests/module/agent-isolation.nix` (not `tests/os-agents.nix`). Check name is `checks.x86_64-linux.test-agent-isolation` (not `os-agents`). Also tests human-agent isolation (bidirectional), sudo restrictions, and system path write restrictions — exceeding the original Phase 1 scope.

**Acceptance Criteria:**
- [x] Test provisions 2 agents: `agent-researcher` (uid 4002) and `agent-coder` (uid 4001)
- [x] Asserts both users exist with correct UIDs
- [x] Asserts both users are in `agents` group
- [x] Asserts neither user is in `wheel` group
- [x] Asserts home directories exist with correct ownership
- [x] Asserts `agent-researcher` cannot read `/home/agent-coder/`
- [x] Test passes: `nix build .#checks.x86_64-linux.test-agent-isolation`

**Validation:**
`nix build .#checks.x86_64-linux.test-agent-isolation` exits 0.

---

## Checkpoint: Phase 1 Complete

**Verify:**
- [x] Agent option declarations evaluate without error
- [x] VM test passes with 2 agents
- [x] Cross-agent home directory isolation confirmed

---

## Phase 2: Headless Desktop

### Task 3: Headless Wayland Desktop [FR-002]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Implement the headless Wayland desktop as systemd system services with `User=`. labwc compositor runs as the primary service, wayvnc binds to a configurable port for remote viewing. Services auto-start on boot and restart on crash. Group under `agent-desktops.target`. Support `vncTailscale` option for Tailscale-only binding.

**Files Modified:**
- `modules/os/agents.nix` — labwc compositor + wayvnc as systemd system services (with `User=`), `agent-desktops.target`, configurable resolution and VNC port, labwc config generation, `vncTailscale` conditional bind

> **Deviation from plan**: Uses labwc (not Cage) — labwc has better wlroots headless backend support with `WLR_BACKENDS=headless` and `WLR_RENDERER=pixman`. Uses systemd system services with `User=` directive (not user services) to avoid linger/session bootstrap issues. Desktop config is in the consolidated `agents.nix` (not a separate `desktop.nix`).

**Acceptance Criteria:**
- [x] `keystone.os.agents.researcher.desktop.enable = true` activates desktop services
- [x] labwc compositor runs as systemd system service under agent account
- [x] wayvnc binds to configured port (default 5901)
- [x] Services restart on failure (`Restart=always`)
- [x] `agent-desktops.target` groups all agent desktop services
- [ ] `vncTailscale = true` restricts VNC binding to `tailscale0` interface

**Validation:**
VM test validates: labwc service active, Wayland socket created, wayvnc service active, VNC port 5901 accepting connections, wlr-randr shows HEADLESS-1 virtual output, config files exist with correct ownership, VNC is localhost-only, non-desktop agent has no desktop services.

---

## Checkpoint: Phase 2 Complete

**Verify:**
- [x] Agent desktop visible via VNC connection
- [x] Services survive restart

---

## Phase 2.5: Chrome + MCP

### Task 4a: Chromium Browser Service [FR-003]

**Type**: Infrastructure
**Dependencies**: Task 3

**Description:**
Install Chromium and configure it to auto-launch on the agent's desktop with remote debugging enabled. Debug port is auto-assigned from base 9222 to avoid conflicts across agents. Chromium profile persists in agent's home directory. The service starts after labwc.

**Files to Create:**
- `modules/os/agents/chrome.nix` — Chromium systemd service (`After=labwc-agent-{name}.service`), `--remote-debugging-port={debugPort}`, auto-assignment from base 9222, persistent profile at `~/.config/chromium-agent/`, configurable extensions

**Acceptance Criteria:**
- [ ] Chromium starts with `--remote-debugging-port={debugPort}`
- [ ] `chrome.debugPort = null` auto-assigns from base 9222 (agent index 0 → 9222, index 1 → 9223, ...)
- [ ] Chromium profile persists at `/home/agent-{name}/.config/chromium-agent/`
- [ ] Chromium service starts after labwc compositor
- [ ] Remote debugging port is accessible from localhost

**Validation:**
Extend VM test: `curl -s http://localhost:9222/json/version` returns Chromium version JSON.

---

### Task 4b: Chrome DevTools MCP Server [FR-003, FR-015]

**Type**: Infrastructure
**Dependencies**: Task 4a

**Description:**
Create a Nix derivation wrapping the `chrome-devtools-mcp` npm package (pinned version, no `npx -y @latest`). Run as a systemd system service with `User=agent-{name}` that connects to the agent's Chrome debug port. MCP server port is auto-assigned per agent to avoid conflicts. Binds to localhost only.

**Files to Create:**
- Nix derivation for `chrome-devtools-mcp` (pinned npm package)
- Addition to `modules/os/agents/chrome.nix` or `modules/os/agents/mcp.nix` — Chrome DevTools MCP systemd service (`After=chromium-agent-{name}.service`), localhost binding, auto-assigned MCP port

**Acceptance Criteria:**
- [ ] `chrome-devtools-mcp` is a Nix derivation with a pinned npm version (no `npx`)
- [ ] MCP systemd service starts after Chromium service
- [ ] MCP server connects to agent's Chrome debug port
- [ ] MCP server port auto-assigned per agent (avoids conflicts)
- [ ] MCP binds to localhost only (not 0.0.0.0)
- [ ] Service restarts on failure

**Validation:**
Extend VM test: MCP service is active, can communicate with Chrome debug port.

---

## Checkpoint: Phase 2.5 Complete

**Verify:**
- [ ] Chromium running with remote debugging accessible
- [ ] Chrome DevTools MCP server running and connected to Chromium
- [ ] Ports auto-assigned without conflicts across agents

---

## Phase 3: Identity + Credentials + Network Isolation

### Task 5: Email via Stalwart [P] [FR-004]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Configure a Stalwart mail account for each agent. Generate IMAP/SMTP credentials stored in agenix. Configure himalaya CLI in agent's environment for programmatic email access. Agenix path declared by keystone module, `.age` files provided by consumer.

**Files to Create:**
- `modules/os/agents/mail.nix` — Stalwart account config (`agent-{name}@{domain}`), himalaya CLI config at `~/.config/himalaya/config.toml`, `age.secrets."agent-{name}-mail-password"` declaration

**Acceptance Criteria:**
- [ ] `keystone.os.agents.researcher.mail.enable = true` creates Stalwart account
- [ ] `age.secrets."agent-researcher-mail-password"` declared with owner `agent-researcher`, mode 0400
- [ ] himalaya config references agenix secret path
- [ ] CalDAV/CardDAV access provisioned when mail is enabled

**Validation:**
Extend VM test: himalaya config file exists at expected path.

---

### Task 6: Bitwarden Account [P] [FR-005]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Configure Vaultwarden integration for each agent. Store password in agenix. Install and pre-configure `bw` CLI. Create a dedicated Bitwarden collection per agent. Agenix path declared by keystone module.

**Files to Create:**
- `modules/os/agents/bitwarden.nix` — Vaultwarden config, `bw` CLI in agent's PATH, `age.secrets."agent-{name}-bitwarden-password"` declaration, collection scoping

**Acceptance Criteria:**
- [ ] `keystone.os.agents.researcher.bitwarden.enable = true` configures Vaultwarden access
- [ ] `age.secrets."agent-researcher-bitwarden-password"` declared with owner `agent-researcher`, mode 0400
- [ ] `bw` CLI available in agent's PATH and pre-configured with server URL
- [ ] Collection scoped to `agent-researcher`

**Validation:**
Extend VM test: `su - agent-researcher -c "which bw"` succeeds.

---

### Task 7: Per-Agent Tailscale Instances [P] [FR-006]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Configure per-agent `tailscaled` daemon instances. Each agent gets its own state directory, socket, and TUN interface. UID-based fwmark rules route agent traffic through their specific TUN. A `tailscale` CLI wrapper auto-specifies `--socket`. Auth key stored in agenix. Support fallback to host Tailscale via `tailscale0`.

**Files to Create:**
- `modules/os/agents/tailscale.nix` — Per-agent `tailscaled` systemd services with:
  - Unique state: `/var/lib/tailscale/tailscaled-agent-{name}.state`
  - Unique socket: `/run/tailscale/tailscaled-agent-{name}.socket`
  - Unique TUN: `tailscale-agent-{name}`
  - `age.secrets."agent-{name}-tailscale-auth-key"` declaration (owner: root, mode 0400)
  - nftables fwmark rules for UID-based routing
  - `tailscale` CLI wrapper in agent's PATH with `--socket` auto-specified

**Acceptance Criteria:**
- [ ] `tailscaled-agent-researcher.service` runs with unique state/socket/TUN
- [ ] Agent appears as `agent-researcher` on the Headscale tailnet
- [ ] `age.secrets."agent-researcher-tailscale-auth-key"` declared with owner root, mode 0400
- [ ] nftables fwmark rule routes uid 4001 traffic through `tailscale-agent-researcher`
- [ ] `tailscale` wrapper in agent's PATH auto-specifies `--socket`
- [ ] `tailscale.enable = false` falls back to host Tailscale via `tailscale0`

**Validation:**
Extend VM test: `systemctl is-active tailscaled-agent-researcher.service` succeeds, fwmark rules present in nftables.

---

### Task 8: SSH Key Management [P] [FR-007]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Generate ed25519 SSH keypair per agent. Store private key + passphrase in agenix (declared by keystone module). Create `ssh-agent` systemd user service that auto-unlocks the key. Configure git to use SSH key for commit signing.

**Files to Create:**
- `modules/os/agents/ssh.nix` — SSH keypair generation, `ssh-agent` systemd user service, `age.secrets."agent-{name}-ssh-key"` and `age.secrets."agent-{name}-ssh-passphrase"` declarations, git signing config (`user.signingkey`, `gpg.format = ssh`), `~/.ssh/authorized_keys`

**Acceptance Criteria:**
- [ ] `age.secrets."agent-researcher-ssh-key"` declared with owner `agent-researcher`, mode 0400
- [ ] `age.secrets."agent-researcher-ssh-passphrase"` declared with owner `agent-researcher`, mode 0400
- [ ] `ssh-agent` systemd user service auto-starts and unlocks key
- [ ] Git configured with `gpg.format = ssh` and `user.signingkey`
- [ ] Agent's public key in its own `~/.ssh/authorized_keys`

**Validation:**
Extend VM test: `systemctl --user -M agent-researcher@ is-active ssh-agent.service` succeeds.

---

### Task 9: Per-Agent Network Isolation [FR-016]

**Type**: Infrastructure
**Dependencies**: Task 7

**Description:**
Implement nftables UID-based output rules that block ALL inter-agent network traffic. Rules are generated declaratively from the agent configuration (UIDs, VNC ports, Chrome debug ports, MCP ports). Each agent's nftables rules use `skuid {uid}` to match traffic. Access to shared services must be via Tailscale ACLs, not localhost. Support `networking.isolation` opt-out per agent for testing.

**Files to Create:**
- `modules/os/agents/network-isolation.nix` — nftables ruleset generator:
  - For each agent UID, block output to all other agents' ports (VNC, Chrome debug, MCP, etc.)
  - Block all inter-agent localhost traffic
  - Generated declaratively from `keystone.os.agents` config
  - `networking.isolation = true` (default) enables rules; `false` disables for testing

**Acceptance Criteria:**
- [ ] nftables rules block agent-researcher (uid 4001) from connecting to agent-coder's VNC/Chrome/MCP ports
- [ ] nftables rules block agent-coder (uid 4002) from connecting to agent-researcher's VNC/Chrome/MCP ports
- [ ] Rules use `skuid` matching for UID-based traffic filtering
- [ ] Rules are generated from agent config (no hardcoded UIDs/ports)
- [ ] `networking.isolation = false` disables rules for the specific agent
- [ ] Shared services only accessible via Tailscale (not localhost)

**Validation:**
Extend VM test: `su - agent-researcher -c "curl agent-coder-vnc-port"` fails (blocked by nftables).

---

### Task 10: Agenix Secret Declarations [FR-008]

**Type**: Infrastructure
**Dependencies**: Task 5, Task 6, Task 7, Task 8

**Description:**
Ensure the `secrets.nix` module declares all `age.secrets` entries from enabled agent features. The module accepts a `secretsPath` option per agent pointing to the directory containing `.age` files. Consumer (nixos-config) provides the encrypted `.age` files.

**Files to Modify:**
- `modules/os/agents/secrets.nix` — Consolidate `age.secrets` declarations from all sub-modules, add `secretsPath` option, add assertions for ownership/permissions

**Acceptance Criteria:**
- [ ] All agent secrets declared as `age.secrets` entries with correct owner/mode
- [ ] `secretsPath` option defaults to consumer-provided path
- [ ] Assertions verify ownership matches agent user
- [ ] Module works with or without individual features enabled (conditional declarations)

**Validation:**
`nix eval` on test config shows all expected `age.secrets` entries.

---

## Checkpoint: Phase 3 Complete

**Verify:**
- [ ] All identity services configured (mail, bitwarden, tailscale, ssh)
- [ ] Per-agent tailscaled instances running with unique TUN interfaces
- [ ] Inter-agent traffic blocked by nftables UID rules
- [ ] All agenix secrets declared by keystone module
- [ ] ssh-agent running and key unlocked

---

## Phase 4: Agent Space + MCP

### Task 11: Agent Space Scaffold [FR-009]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Create the agent-space workspace structure. A systemd oneshot service scaffolds `/home/agent-{name}/agent-space/` on first boot with all standard files, git-initializes it, and sets the remote. Identity docs (SOUL.md, HUMAN.md) are auto-populated from config.

**Files to Create:**
- `modules/os/agents/agent-space.nix` — Systemd oneshot service that runs scaffold script, configurable git remote
- `modules/os/agents/scripts/scaffold-agent-space.sh` — Creates directory structure, git init, writes TASKS.yaml/PROJECTS.yaml/ISSUES.yaml/SCHEDULES.yaml/SOUL.md/HUMAN.md/AGENTS.md/ARCHITECTURE.md/REQUIREMENTS.md/SERVICES.md, creates `.repos/` and `logs/`, optionally creates `flake.nix`

**Acceptance Criteria:**
- [ ] `/home/agent-researcher/agent-space/` is a git repo
- [ ] All standard files exist (TASKS.yaml, PROJECTS.yaml, ISSUES.yaml, SCHEDULES.yaml, SOUL.md, HUMAN.md, AGENTS.md, ARCHITECTURE.md, REQUIREMENTS.md, SERVICES.md)
- [ ] `.repos/` and `logs/` directories exist
- [ ] SOUL.md contains agent's fullName and email from config
- [ ] HUMAN.md contains operator info from config
- [ ] Git remote set to configured URL

**Validation:**
Extend VM test: `su - agent-researcher -c "ls agent-space/TASKS.yaml"` succeeds.

---

### Task 12: MCP Configuration [FR-015]

**Type**: Infrastructure
**Dependencies**: Task 4b, Task 11

**Description:**
Generate `.mcp.json` from keystone config. Chrome DevTools MCP server entry references the per-agent debug port. Support additional MCP servers. Health checks with automatic restart. No inline secrets.

**Files to Create:**
- `modules/os/agents/mcp.nix` — `.mcp.json` generation from `keystone.os.agents.{name}.mcp.servers`, Chrome DevTools MCP entry references auto-assigned debug port, localhost binding, no inline secrets

**Acceptance Criteria:**
- [ ] `.mcp.json` generated at `/home/agent-researcher/.mcp.json`
- [ ] Chrome DevTools MCP entry references correct agent-specific debug port
- [ ] Additional MCP servers from config are included in `.mcp.json`
- [ ] No secrets appear inline in `.mcp.json` (references to agenix paths only)
- [ ] MCP service restarts on failure

**Validation:**
Extend VM test: `.mcp.json` exists and contains expected server entries with correct ports.

---

## Checkpoint: Phase 4 Complete

**Verify:**
- [ ] Agent-space scaffolded with all standard files
- [ ] `.mcp.json` generated with Chrome DevTools MCP and correct ports
- [ ] Agent has a working directory and tool access

---

## Phase 5: Task Loop + Audit

### Task 13: Task Loop Timers [P] [FR-010]

**Type**: Infrastructure
**Dependencies**: Task 11

**Description:**
Implement the two-tier systemd timer architecture. Scheduler timer (daily) ingests new work from GitHub/email/schedules. Task-loop timer (configurable, default 15 min) processes the task queue. Lock management prevents concurrent execution. Configurable stop conditions and model strategy.

**Files to Create:**
- `modules/os/agents/task-loop.nix` — Systemd timers (`scheduler.timer`, `task-loop.timer`), service definitions, configurable intervals/stop conditions/models
- `modules/os/agents/scripts/task-loop.sh` — Lock file management, source ingestion, LLM dispatch (ingest model vs execute model), stop condition checks, failure handling

**Acceptance Criteria:**
- [ ] `scheduler.timer` fires daily by default
- [ ] `task-loop.timer` fires every 15 minutes by default
- [ ] Lock file prevents concurrent task-loop runs
- [ ] Stop conditions enforced: max tasks per run, max wall time, error threshold
- [ ] Failed tasks logged and skipped (loop continues)
- [ ] Intervals and models configurable per-agent

**Validation:**
Extend VM test: `systemctl --user -M agent-researcher@ is-active task-loop.timer` succeeds.

---

### Task 14: Audit Trail [P] [FR-011]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Implement immutable append-only audit logging. Root-owned log directory with `chattr +a` on the audit file. JSON Lines format. Log rotation via logrotate. Optional Loki forwarding via Alloy. NixOS assertion prevents disabling audit when agents are enabled.

**Files to Create:**
- `modules/os/agents/audit.nix` — Systemd service creating `/var/log/agent-{name}/`, setting `chattr +a`, logrotate config, optional Alloy forwarding config, NixOS assertion
- `modules/os/agents/scripts/audit-logger.sh` — Appends JSON Lines events (timestamp, event_type, details, outcome) to audit.jsonl

**Acceptance Criteria:**
- [ ] `/var/log/agent-researcher/audit.jsonl` exists
- [ ] Log file is root-owned and has append-only attribute
- [ ] Agent user cannot modify or delete audit entries
- [ ] Logrotate configured with 90-day default retention
- [ ] NixOS assertion: `keystone.os.agents != {} -> audit.enable == true`
- [ ] Alert rules defined for suspicious patterns (when monitoring enabled)

**Validation:**
Extend VM test: `lsattr /var/log/agent-researcher/audit.jsonl` shows `a` flag.

---

## Checkpoint: Phase 5 Complete

**Verify:**
- [ ] Task loop timers active
- [ ] Audit log exists, append-only, root-owned
- [ ] Agent cannot tamper with audit entries

---

## Phase 6: Coding Subagent + Incidents

### Task 15: Coding Subagent [P] [FR-013]

**Type**: Infrastructure
**Dependencies**: Task 11, Task 8

**Description:**
Implement the structured code contribution workflow. A script at `~/bin/agent.coding-agent` performs pre-flight checks, enforces branch naming, applies the agent contract (commits OK, push/PR/branch-switch forbidden), supports review cycles, and cleans up on exit.

**Files to Create:**
- `modules/os/agents/coding-agent.nix` — `codingAgent.enable` option, installs script to `~/bin/`, configures branch prefix and provider
- `modules/os/agents/scripts/coding-agent.sh` — Pre-flight (repo exists, clean tree, remote accessible), branch creation (`agent-{name}/{slug}`), git hooks enforcing contract, review cycle (lint/test after commit), cleanup on exit (stash, summary)

**Acceptance Criteria:**
- [ ] `keystone.os.agents.researcher.codingAgent.enable = true` installs script
- [ ] Script at `/home/agent-researcher/bin/agent.coding-agent` is executable
- [ ] Pre-flight checks verify repo state before starting
- [ ] Branch naming follows `agent-researcher/{slug}` pattern
- [ ] Agent cannot push, create PRs, or switch branches (contract enforcement)
- [ ] Working state cleaned up on exit

**Validation:**
Extend VM test: `su - agent-researcher -c "test -x ~/bin/agent.coding-agent"` succeeds.

---

### Task 16: Incident Log [P] [FR-014]

**Type**: Infrastructure
**Dependencies**: Task 11

**Description:**
Implement the operational learning system. ISSUES.yaml schema with structured fields. Shared incident database at `/var/lib/agent-incidents/`. Auto-escalation for critical incidents via agent's email. Known issues injected into agent context at task-loop startup.

**Files to Create:**
- `modules/os/agents/incidents.nix` — Shared database at `/var/lib/agent-incidents/`, ISSUES.yaml schema definition, escalation config (email webhook), context injection into AGENTS.md

**Acceptance Criteria:**
- [ ] ISSUES.yaml schema enforced: name, description, discovered_during, status, severity, workaround, fix
- [ ] `/var/lib/agent-incidents/` exists and is writable by `agents` group
- [ ] Critical incidents trigger email escalation to operator
- [ ] Agent's AGENTS.md references active incidents from ISSUES.yaml
- [ ] Known open issues available in agent context

**Validation:**
Extend VM test: `/var/lib/agent-incidents/` exists with correct group ownership.

---

## Checkpoint: Phase 6 Complete

**Verify:**
- [ ] Coding subagent script installed and executable
- [ ] Incident database path exists
- [ ] All agent operational features in place

---

## Phase 7: Full Security Test Suite

### Task 17: Comprehensive Isolation Tests [FR-012]

**Type**: Test
**Dependencies**: All previous tasks

**Description:**
Expand `tests/os-agents.nix` to cover all isolation and credential scoping requirements from FR-012. Tests provision 2+ agents with all features enabled and verify cross-cutting security properties.

**Files to Modify:**
- `tests/os-agents.nix` — Add tests for: cross-agent secret isolation, no sudo/wheel, no system path writes, cgroup limits, nftables UID-based inter-agent block (FR-016), per-agent Tailscale instances (FR-006), VNC port isolation, Chrome debug port isolation, credential scoping (Bitwarden, SSH key, IMAP/SMTP)

**Acceptance Criteria:**
- [ ] `agent-researcher` cannot read `agent-coder`'s agenix secrets
- [ ] Neither agent can `sudo` or write to `/etc`, `/nix/store`
- [ ] Cgroup CPU/memory limits enforced
- [ ] nftables UID rules block inter-agent traffic (FR-016)
- [ ] Network egress blocked to undeclared destinations
- [ ] VNC ports isolated (each agent's port only serves its own desktop)
- [ ] Chrome debug ports not accessible cross-agent
- [ ] Each agent has its own `tailscaled` instance with distinct TUN interface
- [ ] Each agent's SSH key is distinct
- [ ] Each agent can only authenticate to its own IMAP/SMTP account

**Validation:**
`nix build .#checks.x86_64-linux.os-agents` exits 0.

---

### Task 18: CI Integration [FR-012]

**Type**: Infrastructure
**Dependencies**: Task 17

**Description:**
Configure CI to run the agent security tests on PRs that touch `modules/os/agents/`. Add the test to flake checks if not already auto-discovered.

**Files to Modify:**
- `flake.nix` — Add `os-agents` to checks (if needed)
- `.github/workflows/ci.yml` — Add path filter for `modules/os/agents/**` triggering the test

**Acceptance Criteria:**
- [ ] `nix flake check` includes `os-agents` test
- [ ] PRs touching `modules/os/agents/` trigger the security test in CI
- [ ] CI passes on a clean branch

**Validation:**
`nix flake check` includes the os-agents test output.

---

## Checkpoint: Phase 7 Complete

**Verify:**
- [ ] All isolation tests pass
- [ ] CI configured to run tests on relevant PRs
- [ ] Full SPEC-007 implementation complete

---

## Progress Tracking

| Task | Status | FR | Phase | Notes |
|------|--------|----|-------|-------|
| 1 | [x] | FR-001, FR-008 | 1 | Done via single `agents.nix`. Home-manager and agenix deferred. |
| 2 | [x] | FR-012 | 1 | Done as `tests/module/agent-isolation.nix` (19 assertions, eval + runtime) |
| 3 | [x] | FR-002 | 2 | Done with labwc (not Cage), system services with `User=` (not user services) |
| 4a | [ ] | FR-003 | 2.5 | Chromium browser service (auto-assigned debug port) |
| 4b | [ ] | FR-003, FR-015 | 2.5 | Chrome DevTools MCP server (pinned Nix derivation) |
| 5 | [ ] | FR-004 | 3 | Email (parallel with 6,7,8) |
| 6 | [ ] | FR-005 | 3 | Bitwarden (parallel with 5,7,8) |
| 7 | [ ] | FR-006 | 3 | Per-agent Tailscale instances (parallel with 5,6,8) |
| 8 | [ ] | FR-007 | 3 | SSH (parallel with 5,6,7) |
| 9 | [ ] | FR-016 | 3 | Per-agent network isolation (nftables UID rules, depends on 7) |
| 10 | [ ] | FR-008 | 3 | Agenix secret declarations (depends on 5,6,7,8) |
| 11 | [ ] | FR-009 | 4 | Agent space scaffold |
| 12 | [ ] | FR-015 | 4 | MCP config (depends on 4b, 11) |
| 13 | [ ] | FR-010 | 5 | Task loop (parallel with 14) |
| 14 | [ ] | FR-011 | 5 | Audit trail (parallel with 13) |
| 15 | [ ] | FR-013 | 6 | Coding subagent (parallel with 16) |
| 16 | [ ] | FR-014 | 6 | Incident log (parallel with 15) |
| 17 | [ ] | FR-012 | 7 | Full security test suite (incl. nftables, per-agent Tailscale) |
| 18 | [ ] | FR-012 | 7 | CI integration |
