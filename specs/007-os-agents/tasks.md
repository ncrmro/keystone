# SPEC-007: OS Agents — Tasks

## Overview

**Total Tasks**: 16
**Phases**: 7
**Parallelizable**: 8

Note: This spec uses functional requirements (FR-NNN) rather than user stories. Tasks reference FRs directly.

## Task Dependency Graph

```
Phase 1:  [1] → [2]
Phase 2:  [3] → [4]  (depends on Phase 1)
Phase 3:  [5] [P] [6] [P] [7] [P] [8] [P]  (all depend on Phase 1)
Phase 4:  [9] → [10]  (depends on Phase 1)
Phase 5:  [11] [P] [12] [P]  (11 depends on Phase 4, 12 depends on Phase 1)
Phase 6:  [13] [P] [14] [P]  (depend on Phase 4+5)
Phase 7:  [15] → [16]  (depends on all above)
```

---

## Phase 1: Core User Provisioning

### Task 1: Agent Option Declarations + User Creation [FR-001] [FR-008]

**Type**: Infrastructure
**Dependencies**: None

**Description:**
Create the `keystone.os.agents` option set in `modules/os/default.nix` and implement the agent user provisioning module. The agent submodule type mirrors the existing `userSubmodule` in `default.nix` but with agent-specific defaults (no password, `agents` group, UID 4000+ range). Include agenix secret path conventions and assertions. Wire up home-manager to reuse `keystone.terminal` for agent configs.

**Files to Create/Modify:**
- `modules/os/agents.nix` — Top-level option declarations for `keystone.os.agents` (agentSubmodule type)
- `modules/os/agents/default.nix` — Imports all agent sub-modules
- `modules/os/agents/users.nix` — User creation: NixOS user, home dir (ZFS or ext4), `agents` group, home-manager with `keystone.terminal`
- `modules/os/agents/secrets.nix` — Agenix path convention (`/run/agenix/agent-{name}-*`), assertions (secrets readable only by owner)
- `modules/os/default.nix` — Add `./agents.nix` to imports, add `keystone.os.agents` option

**Acceptance Criteria:**
- [ ] `keystone.os.agents.researcher = { fullName = "Research Agent"; email = "researcher@test.local"; }` is a valid config
- [ ] Agent user `agent-researcher` is created with UID >= 4000
- [ ] Agent user belongs to `agents` group
- [ ] Agent user has no password and is not in `wheel`
- [ ] Home directory exists at `/home/agent-researcher` with `chmod 700`
- [ ] Home-manager config reuses `keystone.terminal` module
- [ ] Agenix assertions verify secret ownership

**Validation:**
Run `nix eval` on a test config to verify option evaluation succeeds without errors.

---

### Task 2: Agent Provisioning VM Test [FR-012 partial]

**Type**: Test
**Dependencies**: Task 1

**Description:**
Create a NixOS VM test that declares 2 agents and verifies the core provisioning from Task 1. This establishes the test pattern expanded in later phases.

**Files to Create:**
- `tests/os-agents.nix` — NixOS VM test with 2 agents (`researcher` and `coder`)

**Acceptance Criteria:**
- [ ] Test provisions 2 agents: `agent-researcher` (uid 4001) and `agent-coder` (uid 4002)
- [ ] Asserts both users exist with correct UIDs
- [ ] Asserts both users are in `agents` group
- [ ] Asserts neither user is in `wheel` group
- [ ] Asserts home directories exist with correct ownership
- [ ] Asserts `agent-researcher` cannot read `/home/agent-coder/`
- [ ] Test passes: `nix build .#checks.x86_64-linux.os-agents`

**Validation:**
`nix build .#checks.x86_64-linux.os-agents` exits 0.

---

## Checkpoint: Phase 1 Complete

**Verify:**
- [ ] Agent option declarations evaluate without error
- [ ] VM test passes with 2 agents
- [ ] Cross-agent home directory isolation confirmed

---

## Phase 2: Desktop + Browser

### Task 3: Headless Wayland Desktop [FR-002]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Implement the headless Wayland desktop as systemd user services. Cage compositor runs as the primary service, wayvnc binds to a configurable port for remote viewing. Services auto-start on boot and restart on crash. Group under `agent-desktops.target`.

**Files to Create:**
- `modules/os/agents/desktop.nix` — Cage compositor + wayvnc as systemd user services, `agent-desktops.target`, configurable resolution and VNC port

**Acceptance Criteria:**
- [ ] `keystone.os.agents.researcher.desktop.enable = true` activates desktop services
- [ ] Cage compositor runs as systemd user service under agent account
- [ ] wayvnc binds to configured port (default 5901)
- [ ] Services restart on failure (`Restart=always`)
- [ ] `agent-desktops.target` groups all agent desktop services

**Validation:**
Extend VM test: `systemctl --user -M agent-researcher@ is-active cage-desktop.service` succeeds.

---

### Task 4: Chrome Browser + DevTools [FR-003]

**Type**: Infrastructure
**Dependencies**: Task 3

**Description:**
Install Chrome and configure it to auto-launch on the agent's desktop with remote debugging enabled. Chrome profile persists in agent's home directory. The service starts after the Cage compositor.

**Files to Create:**
- `modules/os/agents/chrome.nix` — Chrome systemd user service (`After=cage-desktop.service`), `--remote-debugging-port`, persistent profile at `~/.config/google-chrome-agent/`, configurable extensions

**Acceptance Criteria:**
- [ ] Chrome starts with `--remote-debugging-port={debugPort}` (default 9222)
- [ ] Chrome profile persists at `/home/agent-{name}/.config/google-chrome-agent/`
- [ ] Chrome service starts after Cage compositor
- [ ] Remote debugging port is accessible from localhost

**Validation:**
Extend VM test: `curl -s http://localhost:9222/json/version` returns Chrome version JSON.

---

## Checkpoint: Phase 2 Complete

**Verify:**
- [ ] Agent desktop visible via VNC connection
- [ ] Chrome running with remote debugging accessible
- [ ] Services survive restart

---

## Phase 3: Identity + Credentials

### Task 5: Email via Stalwart [P] [FR-004]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Configure a Stalwart mail account for each agent. Generate IMAP/SMTP credentials stored in agenix. Configure himalaya CLI in agent's environment for programmatic email access.

**Files to Create:**
- `modules/os/agents/mail.nix` — Stalwart account config (`agent-{name}@{domain}`), himalaya CLI config at `~/.config/himalaya/config.toml`, agenix secret for mail password

**Acceptance Criteria:**
- [ ] `keystone.os.agents.researcher.mail.enable = true` creates Stalwart account
- [ ] IMAP/SMTP password stored at `/run/agenix/agent-researcher-mail-password`
- [ ] himalaya config references agenix secret path
- [ ] CalDAV/CardDAV access provisioned when mail is enabled

**Validation:**
Extend VM test: himalaya config file exists at expected path.

---

### Task 6: Bitwarden Account [P] [FR-005]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Configure Vaultwarden integration for each agent. Store API credentials in agenix. Install and pre-configure `bw` CLI. Create a dedicated Bitwarden collection per agent.

**Files to Create:**
- `modules/os/agents/bitwarden.nix` — Vaultwarden config, `bw` CLI in agent's PATH, agenix secret for client secret, collection scoping

**Acceptance Criteria:**
- [ ] `keystone.os.agents.researcher.bitwarden.enable = true` configures Vaultwarden access
- [ ] Client secret stored at `/run/agenix/agent-researcher-bitwarden-client-secret`
- [ ] `bw` CLI available in agent's PATH and pre-configured with server URL
- [ ] Collection scoped to `agent-researcher`

**Validation:**
Extend VM test: `su - agent-researcher -c "which bw"` succeeds.

---

### Task 7: Tailscale Identity [P] [FR-006]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Configure Tailscale identity per agent with unique hostname. Store pre-auth key in agenix. Add firewall rules restricting agent network egress to declared services only.

**Files to Create:**
- `modules/os/agents/tailscale.nix` — Tailscale auth key in agenix, unique hostname (`agent-{name}`), per-agent firewall egress rules

**Acceptance Criteria:**
- [ ] Auth key stored at `/run/agenix/agent-researcher-tailscale-auth-key`
- [ ] Agent joins tailnet with hostname `agent-researcher`
- [ ] Firewall rules restrict egress to declared services
- [ ] VNC port accessible over tailnet

**Validation:**
Extend VM test: firewall rules exist for agent user.

---

### Task 8: SSH Key Management [P] [FR-007]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Generate ed25519 SSH keypair per agent. Store private key + passphrase in agenix. Create `ssh-agent` systemd user service that auto-unlocks the key. Configure git to use SSH key for commit signing.

**Files to Create:**
- `modules/os/agents/ssh.nix` — SSH keypair generation, `ssh-agent` systemd user service, agenix secrets for key + passphrase, git signing config (`user.signingkey`, `gpg.format = ssh`), `~/.ssh/authorized_keys`

**Acceptance Criteria:**
- [ ] SSH private key at `/run/agenix/agent-researcher-ssh-key`
- [ ] SSH passphrase at `/run/agenix/agent-researcher-ssh-passphrase`
- [ ] `ssh-agent` systemd user service auto-starts and unlocks key
- [ ] Git configured with `gpg.format = ssh` and `user.signingkey`
- [ ] Agent's public key in its own `~/.ssh/authorized_keys`

**Validation:**
Extend VM test: `systemctl --user -M agent-researcher@ is-active ssh-agent.service` succeeds.

---

## Checkpoint: Phase 3 Complete

**Verify:**
- [ ] All 4 identity services configured (mail, bitwarden, tailscale, ssh)
- [ ] All agenix secrets at expected paths
- [ ] ssh-agent running and key unlocked

---

## Phase 4: Agent Space + MCP

### Task 9: Agent Space Scaffold [FR-009]

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

### Task 10: MCP Configuration [FR-015]

**Type**: Infrastructure
**Dependencies**: Task 3, Task 9

**Description:**
Generate `.mcp.json` from keystone config. Chrome DevTools MCP runs as systemd user service after Chrome, binding to localhost only. Support additional MCP servers. Health checks with automatic restart.

**Files to Create:**
- `modules/os/agents/mcp.nix` — `.mcp.json` generation from `keystone.os.agents.{name}.mcp.servers`, Chrome DevTools MCP systemd user service (`After=chrome.service`, `Restart=on-failure`), localhost binding, no inline secrets

**Acceptance Criteria:**
- [ ] `.mcp.json` generated at `/home/agent-researcher/.mcp.json`
- [ ] Chrome DevTools MCP service starts after Chrome
- [ ] MCP binds to localhost only (not 0.0.0.0)
- [ ] Additional MCP servers from config are included in `.mcp.json`
- [ ] No secrets appear inline in `.mcp.json` (references to agenix paths only)
- [ ] MCP service restarts on failure

**Validation:**
Extend VM test: `.mcp.json` exists and contains expected server entries.

---

## Checkpoint: Phase 4 Complete

**Verify:**
- [ ] Agent-space scaffolded with all standard files
- [ ] `.mcp.json` generated with Chrome DevTools MCP
- [ ] Agent has a working directory and tool access

---

## Phase 5: Task Loop + Audit

### Task 11: Task Loop Timers [P] [FR-010]

**Type**: Infrastructure
**Dependencies**: Task 9

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

### Task 12: Audit Trail [P] [FR-011]

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

### Task 13: Coding Subagent [P] [FR-013]

**Type**: Infrastructure
**Dependencies**: Task 9, Task 8

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

### Task 14: Incident Log [P] [FR-014]

**Type**: Infrastructure
**Dependencies**: Task 9

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

### Task 15: Comprehensive Isolation Tests [FR-012]

**Type**: Test
**Dependencies**: All previous tasks

**Description:**
Expand `tests/os-agents.nix` to cover all isolation and credential scoping requirements from FR-012. Tests provision 2+ agents with all features enabled and verify cross-cutting security properties.

**Files to Modify:**
- `tests/os-agents.nix` — Add tests for: cross-agent secret isolation, no sudo/wheel, no system path writes, cgroup limits, network egress rules, VNC port isolation, Tailscale identity distinctness, credential scoping (Bitwarden collection, SSH key, IMAP/SMTP)

**Acceptance Criteria:**
- [ ] `agent-researcher` cannot read `agent-coder`'s agenix secrets
- [ ] Neither agent can `sudo` or write to `/etc`, `/nix/store`
- [ ] Cgroup CPU/memory limits enforced
- [ ] Network egress blocked to undeclared destinations
- [ ] VNC ports isolated (each agent's port only serves its own desktop)
- [ ] Each agent's SSH key is distinct
- [ ] Each agent can only authenticate to its own IMAP/SMTP account

**Validation:**
`nix build .#checks.x86_64-linux.os-agents` exits 0.

---

### Task 16: CI Integration [FR-012]

**Type**: Infrastructure
**Dependencies**: Task 15

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
| 1 | [ ] | FR-001, FR-008 | 1 | Foundation — all others depend on this |
| 2 | [ ] | FR-012 | 1 | VM test pattern established |
| 3 | [ ] | FR-002 | 2 | Headless desktop |
| 4 | [ ] | FR-003 | 2 | Chrome + DevTools |
| 5 | [ ] | FR-004 | 3 | Email (parallel with 6,7,8) |
| 6 | [ ] | FR-005 | 3 | Bitwarden (parallel with 5,7,8) |
| 7 | [ ] | FR-006 | 3 | Tailscale (parallel with 5,6,8) |
| 8 | [ ] | FR-007 | 3 | SSH (parallel with 5,6,7) |
| 9 | [ ] | FR-009 | 4 | Agent space scaffold |
| 10 | [ ] | FR-015 | 4 | MCP config |
| 11 | [ ] | FR-010 | 5 | Task loop (parallel with 12) |
| 12 | [ ] | FR-011 | 5 | Audit trail (parallel with 11) |
| 13 | [ ] | FR-013 | 6 | Coding subagent (parallel with 14) |
| 14 | [ ] | FR-014 | 6 | Incident log (parallel with 13) |
| 15 | [ ] | FR-012 | 7 | Full security test suite |
| 16 | [ ] | FR-012 | 7 | CI integration |
