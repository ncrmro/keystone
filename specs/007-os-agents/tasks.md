# SPEC-007: OS Agents — Tasks

## Overview

**Total Tasks**: 20
**Phases**: 8
**Parallelizable**: 10

Note: This spec uses functional requirements (FR-NNN) rather than user stories. Tasks reference FRs directly.

## Task Dependency Graph

```
Phase 1:  [1] → [2]
Phase 2:  [3] → [4]  (depends on Phase 1)
Phase 3:  [5] [P] [6] [P] [7] [P] [8] [P]  (all depend on Phase 1)
Phase 4:  [9] → [10]  (depends on Phase 1)
Phase 5:  [11] [P] [12] [P]  (11 depends on Phase 4, 12 depends on Phase 1)
Phase 6:  [13] [P] [14] [P]  (depend on Phase 4+5; 13 also depends on 19)
Phase 7:  [15] → [16]  (depends on all above)
Phase 8:  [17] [P] [18] [P] [19] [P] [20] [P]  (17,18 depend on Task 9; 19,20 independent)
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
- [x] Home directory exists at `/home/agent-researcher` with `chmod 750` (group readable by `agent-admins`)
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

## Phase 2: Desktop + Browser

### Task 3: Headless Wayland Desktop [FR-002]

**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Implement the headless Wayland desktop as systemd system services with `User=`. labwc compositor runs as the primary service, wayvnc binds to a configurable port for remote viewing. Services auto-start on boot and restart on crash. Group under `agent-desktops.target`.

**Files Modified:**
- `modules/os/agents.nix` — labwc compositor + wayvnc as systemd system services (with `User=`), `agent-desktops.target`, configurable resolution and VNC port, labwc config generation

> **Deviation from plan**: Uses labwc (not Cage) — labwc has better wlroots headless backend support with `WLR_BACKENDS=headless` and `WLR_RENDERER=pixman`. Uses systemd system services with `User=` directive (not user services) to avoid linger/session bootstrap issues. Desktop config is in the consolidated `agents.nix` (not a separate `desktop.nix`).

**Acceptance Criteria:**
- [x] `keystone.os.agents.researcher.desktop.enable = true` activates desktop services
- [x] labwc compositor runs as systemd system service under agent account
- [x] wayvnc binds to configured port (default 5901)
- [x] Services restart on failure (`Restart=always`)
- [x] `agent-desktops.target` groups all agent desktop services

**Validation:**
VM test validates: labwc service active, Wayland socket created, wayvnc service active, VNC port 5901 accepting connections, wlr-randr shows HEADLESS-1 virtual output, config files exist with correct ownership, VNC is localhost-only, non-desktop agent has no desktop services.

---

### Task 4: Chrome Browser + DevTools MCP [FR-003]

**Type**: Infrastructure
**Dependencies**: Task 3

**Description:**
Install Chrome/Chromium and configure it to auto-launch on the agent's desktop with remote debugging enabled. Chrome profile persists in agent's home directory. The Chrome service starts after labwc compositor. Package `chrome-devtools-mcp` as a Nix derivation (from the `chrome-devtools-mcp` npm package via [ChromeDevTools/chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp)). Chrome DevTools MCP uses **stdio transport** — no dedicated systemd service; MCP clients launch ephemeral processes. The `.mcp.json` entry for Chrome DevTools MCP is generated in Task 10.

**Files to Create:**
- `modules/os/agents/chrome.nix` — Chrome systemd system service (`After=labwc-agent-{name}.service`, `User=agent-{name}`), `--remote-debugging-port={debugPort}`, persistent profile at `~/.config/google-chrome-agent/`, configurable extensions
- Keystone overlay derivation for `chrome-devtools-mcp` npm package (using `buildNpmPackage` or equivalent)

**Acceptance Criteria:**
- [ ] Chrome starts with `--remote-debugging-port={debugPort}` (default 9222)
- [ ] Chrome profile persists at `/home/agent-{name}/.config/google-chrome-agent/`
- [ ] Chrome service starts after labwc compositor (system service with `User=`)
- [ ] Remote debugging port is accessible from localhost
- [ ] `chrome-devtools-mcp` Nix derivation builds successfully
- [ ] Multiple MCP clients can connect to the same debug port

**Validation:**
Extend VM test: `curl -s http://localhost:9222/json/version` returns Chrome version JSON. Verify `chrome-devtools-mcp` binary exists in the Nix store.

---

## Checkpoint: Phase 2 Partial (Desktop complete, Chrome pending)

**Verify:**
- [x] Agent desktop visible via VNC connection
- [ ] Chrome running with remote debugging accessible *(Task 4 not started)*
- [x] Services survive restart

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
**Dependencies**: Task 4, Task 9

**Description:**
Generate `.mcp.json` from keystone config. When `chrome.mcp.enable = true`, include a `chrome-devtools` entry pointing to the Nix-packaged `chrome-devtools-mcp` binary with `--browserUrl http://127.0.0.1:{debugPort}`. Chrome DevTools MCP uses **stdio transport** — no dedicated systemd service; the MCP client (Claude Code, etc.) launches an ephemeral process per connection. Support additional MCP servers via `keystone.os.agents.{name}.mcp.servers`. Generate human-accessible config fragments at `/etc/keystone/agent-mcp/{name}.json` so human users on the same host can launch their own MCP client connecting to any agent's Chrome.

**Files to Create:**
- `modules/os/agents/mcp.nix` — `.mcp.json` generation from `keystone.os.agents.{name}.mcp.servers` plus Chrome DevTools MCP entry (when `chrome.mcp.enable = true`), human-accessible config at `/etc/keystone/agent-mcp/{name}.json`, no inline secrets

**Acceptance Criteria:**
- [ ] `.mcp.json` generated at `/home/agent-researcher/.mcp.json`
- [ ] When `chrome.mcp.enable = true`, `.mcp.json` contains a `chrome-devtools` server entry with `command` pointing to the Nix-packaged `chrome-devtools-mcp` and `args` containing `["--browserUrl", "http://127.0.0.1:{debugPort}"]`
- [ ] Additional MCP servers from config are included in `.mcp.json`
- [ ] No secrets appear inline in `.mcp.json` (references to agenix paths only)
- [ ] `/etc/keystone/agent-mcp/{name}.json` exists with Chrome DevTools MCP config for human access
- [ ] Human users can use the config fragment to connect to agent Chrome instances

**Validation:**
Extend VM test: `.mcp.json` exists and contains `chrome-devtools` server entry with correct `--browserUrl`. `/etc/keystone/agent-mcp/researcher.json` exists and is readable by human users.

---

## Checkpoint: Phase 4 Complete

**Verify:**
- [ ] Agent-space scaffolded with all standard files
- [ ] `.mcp.json` generated with Chrome DevTools MCP entry (stdio transport, `--browserUrl`)
- [ ] Human-accessible config fragments at `/etc/keystone/agent-mcp/`
- [ ] Agent has a working directory and tool access

---

## Phase 5: Task Loop + Audit

### Task 11: Task Loop Timers [P] [FR-010]

**Type**: Infrastructure
**Dependencies**: Task 9

**Description:**
Implement the two-tier systemd timer architecture with the refined pipeline from agent-space. Scheduler timer (default `*-*-* 05:00:00` — 5 AM) ingests new work. Task-loop timer (default `*:0/5` — every 5 min) runs the full pipeline: pre-fetch sources → hash-based change detection → ingest (haiku) → prioritize (haiku) → execute loop (per-task model). The `run.sh` script MUST live in the agent-space (not Nix store) so the agent can modify its own loop. Lock management prevents concurrent execution. Supports `needs` dependency ordering, `model` per-task override, and `workflow` DeepWork dispatch. Validates TASKS.yaml with `yq` after each write.

**Files to Create:**
- `modules/os/agents/task-loop.nix` — Systemd timers (`scheduler.timer` at `schedulerOnCalendar`, `task-loop.timer` at `loopOnCalendar`), service definitions pointing to agent-space `run.sh`, configurable intervals/stop conditions/models (ingest, prioritize, execute separately)
- Agent-space `run.sh` template — Pre-fetch pipeline (iterate `PROJECTS.yaml:sources`, run shell commands, collect JSON), hash-based skip, LLM dispatch per step, `needs` dependency checking via yq+jq, per-task model/workflow dispatch, TASKS.yaml validation with git restore on failure

**Acceptance Criteria:**
- [ ] `scheduler.timer` fires at `*-*-* 05:00:00` by default
- [ ] `task-loop.timer` fires at `*:0/5` (every 5 min) by default
- [ ] `run.sh` lives in agent-space, not Nix store
- [ ] Pre-fetch step iterates PROJECTS.yaml sources and collects JSON
- [ ] Hash-based change detection skips ingest when sources unchanged
- [ ] Three separate model configs: `models.ingest` (haiku), `models.prioritize` (haiku), `models.execute` (sonnet)
- [ ] Per-task `model` field overrides execute model
- [ ] Per-task `needs` field enforces dependency ordering
- [ ] Per-task `workflow` field dispatches to DeepWork workflows
- [ ] TASKS.yaml validated after each write; restored from git on failure
- [ ] Lock file prevents concurrent task-loop runs
- [ ] Stop conditions enforced: max tasks per run, max wall time, error threshold
- [ ] Failed tasks logged and skipped (loop continues)

**Validation:**
Extend VM test: `systemctl --user -M agent-researcher@ is-active task-loop.timer` succeeds. Verify `run.sh` exists in agent-space.

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
**Dependencies**: Task 9, Task 8, Task 19

**Description:**
Implement the structured code contribution workflow using the Nix-packaged `agent-coding-agent` derivation (Task 19). The `codingAgent.enable` option adds the package to the agent's PATH. The orchestrator/subagent split means the bash script handles git/push/PR while the LLM only makes commits. Supports provider interface (`agent.coding-agent.{provider} REPO_DIR SYSTEM_PROMPT_FILE TIMEOUT [--model MODEL]`), review cycles (up to N, default 2) with COMMENT/VERDICT format, both GitHub and Forgejo remotes, and `--review-only PR_NUMBER` mode.

**Files to Create:**
- `modules/os/agents/coding-agent.nix` — `codingAgent.enable` option, adds `pkgs.keystone.agent-coding-agent` to agent's PATH, configures branch prefix, provider, max review cycles, and auto-review settings

**Acceptance Criteria:**
- [ ] `keystone.os.agents.researcher.codingAgent.enable = true` adds coding-agent to PATH
- [ ] `agent.coding-agent` binary is available in agent's PATH (from Nix package)
- [ ] Provider scripts (`agent.coding-agent.claude`, etc.) also available in PATH
- [ ] Pre-flight checks verify repo state (exists in `.repos/`, clean tree, remote type detection)
- [ ] Branch naming follows `{prefix}/{slugified-task}` pattern
- [ ] Orchestrator handles push: GitHub (token-based URL), Forgejo (SSH)
- [ ] Draft PRs: `gh pr create --draft` (GitHub), `WIP:` prefix (Forgejo)
- [ ] Review cycle: up to N cycles, COMMENT/VERDICT format, re-run on FAIL
- [ ] `--review-only PR_NUMBER` mode skips coding
- [ ] Working state cleaned up on exit (return to default branch, remove temp files)

**Validation:**
Extend VM test: `su - agent-researcher -c "which agent.coding-agent"` succeeds.

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

## Phase 8: Nix Packaging

### Task 17: Cronjob Self-Management Scaffolding [FR-016]

**Type**: Infrastructure
**Dependencies**: Task 9

**Description:**
Implement the cronjob self-management convention in the agent-space scaffold. When scaffolding a new agent-space, create `.cronjobs/shared/{lib.sh,config.sh,setup.sh}` with standard utilities. Create the `.deepwork/jobs/cronjobs/` job definition with three workflows: create, edit, review. The `setup.sh` script installs cronjobs by symlinking service/timer units into `~/.config/systemd/user/`. Add `keystone.os.agents.{name}.cronjobs` NixOS option for declaring managed timers.

**Files to Create:**
- `.cronjobs/shared/lib.sh` template — Logging, error handling, lock management functions
- `.cronjobs/shared/config.sh` template — Environment variables and standard paths
- `.cronjobs/shared/setup.sh` template — Systemd unit installation via symlinks
- `.deepwork/jobs/cronjobs/` — Job definition with create/edit/review workflows (can be copied from agent-space reference)
- `modules/os/agents/cronjobs.nix` — `cronjobs` option set for declaring managed timers

**Acceptance Criteria:**
- [ ] Scaffold creates `.cronjobs/shared/{lib.sh,config.sh,setup.sh}`
- [ ] `.deepwork/jobs/cronjobs/` exists with three workflows
- [ ] `setup.sh` symlinks units into `~/.config/systemd/user/`
- [ ] `run.sh` scripts use `SCRIPT_DIR` for relative paths
- [ ] `keystone.os.agents.researcher.cronjobs` option is available

**Validation:**
Extend VM test: verify `.cronjobs/shared/lib.sh` exists in scaffolded agent-space.

---

### Task 18: Agent-Space Flake Convention [FR-017]

**Type**: Infrastructure
**Dependencies**: Task 9

**Description:**
Define the standard `flake.nix` template for agent-space. The flake MUST provide a dev shell with required tools: LLM CLI (via `llm-agents.nix`), DeepWork CLI, git, gh, jq, yq-go. Optional tools based on agent role. Scaffold mode generates this flake.nix from a template. The flake declares `deepwork` and `llm-agents` as inputs.

**Files to Create:**
- Agent-space `flake.nix` template — Inputs (nixpkgs, flake-utils, deepwork, llm-agents), dev shell with required + optional tools, shell hook setting `VAULT_ROOT`
- Update scaffold script (Task 9) to generate `flake.nix` from template

**Acceptance Criteria:**
- [ ] Scaffolded agent-space contains a `flake.nix`
- [ ] `nix develop` in agent-space provides: claude-code, deepwork, git, gh, jq, yq-go
- [ ] `flake.nix` declares deepwork and llm-agents as inputs
- [ ] Dev shell includes shell hook setting `VAULT_ROOT`

**Validation:**
`nix eval` on the generated flake.nix succeeds without errors.

---

### Task 19: Package `agent-coding-agent` as Nix Derivation [FR-013]

**Type**: Packaging
**Dependencies**: None (packaging is independent of module work)

**Description:**
Package the `agent.coding-agent` bash script and its provider scripts as a Nix derivation. Use `writeShellApplication` or `symlinkJoin` + `makeWrapper` to ensure runtime dependencies (git, gh, openssh, jq, forgejo-cli) are in PATH. The package includes: `agent.coding-agent` (main orchestrator), `agent.coding-agent.claude` (Claude provider), `agent.coding-agent.codex` (stub), `agent.coding-agent.gemini` (stub). Expose as `keystone.agent-coding-agent` in the overlay.

**Files to Create:**
- `packages/agent-coding-agent/default.nix` — Nix derivation wrapping the bash scripts
- `packages/agent-coding-agent/bin/agent.coding-agent` — Main script (from agent-space reference)
- `packages/agent-coding-agent/bin/agent.coding-agent.claude` — Claude provider
- `packages/agent-coding-agent/bin/agent.coding-agent.codex` — Codex stub
- `packages/agent-coding-agent/bin/agent.coding-agent.gemini` — Gemini stub

**Acceptance Criteria:**
- [ ] `nix build .#agent-coding-agent` succeeds
- [ ] Built package contains all 4 scripts in `bin/`
- [ ] Runtime deps (git, gh, openssh, jq) are in PATH via wrapper
- [ ] `keystone.agent-coding-agent` available in overlay
- [ ] Scripts are executable and pass basic syntax check (`bash -n`)

**Validation:**
`nix build .#agent-coding-agent && ./result/bin/agent.coding-agent --help` shows usage.

---

### Task 20: Package `fetch-email-source` as Nix Derivation [FR-010]

**Type**: Packaging
**Dependencies**: None

**Description:**
Package the `fetch-email-source` script as a Nix derivation. The script fetches email envelopes via himalaya and enriches them with message bodies, outputting JSON. Use `writeShellApplication` to wrap with himalaya and jq in PATH. Expose as `keystone.fetch-email-source` in the overlay.

**Files to Create:**
- `packages/fetch-email-source/default.nix` — Nix derivation
- `packages/fetch-email-source/bin/fetch-email-source` — Script (from agent-space reference)

**Acceptance Criteria:**
- [ ] `nix build .#fetch-email-source` succeeds
- [ ] Built package contains `fetch-email-source` in `bin/`
- [ ] Runtime deps (himalaya, jq) are in PATH via wrapper
- [ ] `keystone.fetch-email-source` available in overlay

**Validation:**
`nix build .#fetch-email-source && ./result/bin/fetch-email-source --help` or basic invocation test.

---

## Checkpoint: Phase 8 Complete

**Verify:**
- [ ] All Nix packages build successfully
- [ ] Cronjob scaffolding creates expected directory structure
- [ ] Agent-space flake.nix provides required dev shell tools
- [ ] Packages wired into overlay and accessible via `keystone.*` namespace

---

## Progress Tracking

| Task | Status | FR | Phase | Notes |
|------|--------|----|-------|-------|
| 1 | [x] | FR-001, FR-008 | 1 | Done via single `agents.nix`. Home-manager and agenix deferred. |
| 2 | [x] | FR-012 | 1 | Done as `tests/module/agent-isolation.nix` (19 assertions, eval + runtime) |
| 3 | [x] | FR-002 | 2 | Done with labwc (not Cage), system services with `User=` (not user services) |
| 4 | [~] | FR-003 | 2 | Chromium service works (cage + chromium + DevTools port), but always-on regardless of enable flag |
| 5 | [~] | FR-004 | 3 | Himalaya config generated, mail account provisioning pending |
| 6 | [~] | FR-005 | 3 | bw CLI installed, Vaultwarden collection setup pending |
| 7 | [~] | FR-006 | 3 | Coded but disabled (TODO: fix agenix.service dependency) |
| 8 | [x] | FR-007 | 3 | SSH fully implemented: ssh-agent service, SSH_ASKPASS, key generation, git signing |
| 9 | [ ] | FR-009 | 4 | Agent space scaffold |
| 10 | [ ] | FR-015 | 4 | MCP config (.mcp.json + human access fragments, stdio transport) |
| 11 | [ ] | FR-010 | 5 | Task loop — refined pipeline with pre-fetch, hash detection, 3-tier models |
| 12 | [ ] | FR-011 | 5 | Audit trail (parallel with 11) |
| 13 | [ ] | FR-013 | 6 | Coding subagent — Nix-packaged, provider interface, review cycles |
| 14 | [ ] | FR-014 | 6 | Incident log (parallel with 13) |
| 15 | [ ] | FR-012 | 7 | Full security test suite |
| 16 | [ ] | FR-012 | 7 | CI integration |
| 17 | [ ] | FR-016 | 8 | Cronjob self-management scaffolding |
| 18 | [ ] | FR-017 | 8 | Agent-space flake convention |
| 19 | [ ] | FR-013 | 8 | Package `agent-coding-agent` as Nix derivation |
| 20 | [ ] | FR-010 | 8 | Package `fetch-email-source` as Nix derivation |
