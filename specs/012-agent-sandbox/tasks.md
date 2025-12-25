# Tasks: Agent Sandbox

**Input**: Design documents from `/specs/012-agent-sandbox/`
**Prerequisites**: plan.md (complete), spec.md (complete), research.md (complete), data-model.md (complete), contracts/cli-spec.md (complete)

**Tests**: Not explicitly requested in specification. Test tasks omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md structure:
- **CLI Tooling**: `bin/`
- **NixOS Modules**: `modules/keystone/agent/`
- **Guest Modules**: `modules/keystone/agent/guest/`
- **Home-Manager**: `modules/keystone/agent/home/`
- **Tests**: `tests/microvm/`, `tests/integration/`

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Create project structure and foundational scaffolding

- [ ] T001 Create agent module directory structure at modules/keystone/agent/
- [ ] T002 [P] Create CLI entrypoint script at bin/agent (Python + Click skeleton)
- [ ] T003 [P] Create guest module directory structure at modules/keystone/agent/guest/
- [ ] T004 [P] Create home-manager module directory at modules/keystone/agent/home/
- [ ] T005 Add agent module to flake.nix outputs

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T006 Implement base NixOS module with keystone.agent.enable option in modules/keystone/agent/default.nix
- [ ] T007 [P] Define SandboxConfig options (memory, vcpus, nested_virt, network, sync_mode, persist) in modules/keystone/agent/default.nix
- [ ] T008 [P] Define Backend options (type, microvm config, kubernetes config stub) in modules/keystone/agent/default.nix
- [ ] T009 [P] Create sandbox state directory structure at ~/.config/keystone/agent/ via CLI
- [ ] T010 [P] Implement sandbox registry (sandboxes.json) management in bin/agent
- [ ] T011 [P] Create agent.toml configuration file parser in bin/agent
- [ ] T012 Implement Backend interface abstraction in modules/keystone/agent/backends/default.nix
- [ ] T013 [P] Create CLI Click application structure with subcommand routing in bin/agent
- [ ] T014 [P] Add color output and logging utilities to CLI (following bin/worktree pattern) in bin/agent

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Launch Agent in Sandbox (Priority: P1) MVP

**Goal**: Developer can run `keystone agent start` on any git repo, the agent works without prompts, and changes are accessible

**Independent Test**: Run `keystone agent start` in a git repo, verify MicroVM boots with `/workspace/` containing the repo

### Implementation for User Story 1

- [ ] T015 [US1] Implement MicroVM backend create/start/stop/destroy in modules/keystone/agent/backends/microvm.nix
- [ ] T016 [US1] Configure virtiofs share for /workspace/ mount in modules/keystone/agent/backends/microvm.nix
- [ ] T017 [P] [US1] Create guest OS base configuration in modules/keystone/agent/guest/default.nix
- [ ] T018 [P] [US1] Configure Claude Code package and auto-accept settings in modules/keystone/agent/guest/agents.nix
- [ ] T019 [P] [US1] Add development tools (git, direnv, etc.) to guest in modules/keystone/agent/guest/tools.nix
- [ ] T020 [US1] Implement git clone/push workflow for initial workspace setup in modules/keystone/agent/sync.nix
- [ ] T021 [US1] Configure .env file rsync from host to sandbox in modules/keystone/agent/sync.nix
- [ ] T022 [US1] Setup direnv auto-load for .env files in guest at modules/keystone/agent/guest/tools.nix
- [ ] T023 [US1] Implement `keystone agent start` command with all options in bin/agent
- [ ] T024 [US1] Implement `keystone agent stop` command in bin/agent
- [ ] T025 [US1] Implement `keystone agent status` command in bin/agent
- [ ] T026 [US1] Implement `keystone agent list` command in bin/agent
- [ ] T027 [US1] Implement `keystone agent destroy` command in bin/agent
- [ ] T028 [US1] Add nested virtualization detection and KVM passthrough in modules/keystone/agent/backends/microvm.nix
- [ ] T029 [US1] Implement --fresh flag to discard previous sandbox state in bin/agent
- [ ] T030 [US1] Add exit code handling per cli-spec.md in bin/agent

**Checkpoint**: User Story 1 complete - developer can launch sandboxes with AI agents

---

## Phase 4: User Story 2 - Interactive TUI Session (Priority: P1)

**Goal**: Developer can attach to sandbox via TUI, view agent output, run commands, manage worktrees

**Independent Test**: Run `keystone agent attach`, verify Zellij session connects and terminal is usable

### Implementation for User Story 2

- [ ] T031 [US2] Configure Zellij in guest with session persistence in modules/keystone/agent/guest/zellij.nix
- [ ] T032 [US2] Setup Zellij web server for remote attachment in modules/keystone/agent/guest/zellij.nix
- [ ] T033 [US2] Implement session naming convention (<sandbox>-<branch>) in modules/keystone/agent/guest/zellij.nix
- [ ] T034 [US2] Implement `keystone agent attach` command with terminal mode in bin/agent
- [ ] T035 [US2] Implement `keystone agent attach --web` for browser mode in bin/agent
- [ ] T036 [US2] Configure worktree directory structure at /workspace/.worktrees/ in modules/keystone/agent/guest/worktree.nix
- [ ] T037 [US2] Implement `keystone agent worktree add` command in bin/agent
- [ ] T038 [US2] Implement `keystone agent worktree list` command in bin/agent
- [ ] T039 [US2] Implement `keystone agent worktree remove` command in bin/agent
- [ ] T040 [US2] Implement `keystone agent exec` command in bin/agent
- [ ] T041 [US2] Implement `keystone agent ssh` command in bin/agent
- [ ] T042 [US2] Add --worktree option to attach command for switching in bin/agent

**Checkpoint**: User Story 2 complete - developer has full TUI experience

---

## Phase 5: User Story 3 - Sync Changes Back to Host (Priority: P1)

**Goal**: Agent's commits sync to host via host-initiated git pull; artifacts sync via rsync

**Independent Test**: Agent makes commits, run `keystone agent sync`, verify commits appear in host git log

### Implementation for User Story 3

- [ ] T043 [US3] Setup git server/remote in sandbox for host-initiated pull in modules/keystone/agent/sync.nix
- [ ] T044 [US3] Implement host-initiated git pull workflow in bin/agent-sync
- [ ] T045 [US3] Implement `keystone agent sync` command in bin/agent
- [ ] T046 [US3] Implement `keystone agent sync --artifacts` rsync mode in bin/agent
- [ ] T047 [US3] Implement `keystone agent sync --dry-run` in bin/agent
- [ ] T048 [US3] Add sync output formatting (commits, files changed, insertions/deletions) in bin/agent
- [ ] T049 [P] [US3] Implement auto-commit sync mode with post-commit hook in modules/keystone/agent/sync.nix
- [ ] T050 [P] [US3] Implement auto-idle sync mode with inotify watcher in modules/keystone/agent/sync.nix
- [ ] T051 [US3] Add --sync flag to stop command in bin/agent
- [ ] T052 [US3] Handle merge conflicts with clear error messaging in bin/agent

**Checkpoint**: User Story 3 complete - full sandbox workflow operational (MVP COMPLETE)

---

## Phase 6: User Story 4 - Proxy Development Servers (Priority: P2)

**Goal**: Dev servers in sandbox accessible at `<project>.sandbox.local` via host browser

**Independent Test**: Start dev server on port 3000 in sandbox, access `http://myproject.sandbox.local:3000` from host

### Implementation for User Story 4

- [ ] T053 [US4] Configure Caddy reverse proxy on host in modules/keystone/agent/proxy.nix
- [ ] T054 [US4] Setup Avahi mDNS for *.sandbox.local resolution in modules/keystone/agent/proxy.nix
- [ ] T055 [US4] Implement dynamic route registration via Caddy API in bin/agent-proxy
- [ ] T056 [US4] Auto-detect listening ports in sandbox and register routes in modules/keystone/agent/proxy.nix
- [ ] T057 [US4] Add keystone.agent.proxy.enable and domain options in modules/keystone/agent/default.nix
- [ ] T058 [US4] Show proxy URLs in `keystone agent status` output in bin/agent
- [ ] T059 [US4] Handle sandbox stop: clear proxy routes with error page in bin/agent-proxy

**Checkpoint**: User Story 4 complete - web development workflow enhanced

---

## Phase 7: User Story 6 - Nested VM Support (Priority: P2)

**Goal**: Agents can run VMs inside sandbox (critical for Keystone dogfooding)

**Independent Test**: Inside sandbox, run `bin/build-vm terminal`, verify nested VM boots

### Implementation for User Story 6

- [ ] T060 [US6] Enable KVM passthrough with CPU vmx flag in modules/keystone/agent/backends/microvm.nix
- [ ] T061 [US6] Add nested virtualization capability detection script in bin/agent
- [ ] T062 [US6] Configure resource limits for nested VMs (cgroups) in modules/keystone/agent/guest/default.nix
- [ ] T063 [US6] Add --no-nested flag implementation in bin/agent
- [ ] T064 [US6] Display nested virtualization status in `keystone agent status` in bin/agent
- [ ] T065 [US6] Add host modprobe configuration for nested=1 in modules/keystone/agent/default.nix

**Checkpoint**: User Story 6 complete - Keystone self-hosting enabled

---

## Phase 8: User Story 5 - DevContainer Compatibility (Priority: P3)

**Goal**: Projects with .devcontainer/devcontainer.json work in sandbox

**Independent Test**: Project with .devcontainer/ launches with specified tools installed

### Implementation for User Story 5

- [ ] T066 [US5] Parse devcontainer.json for features in modules/keystone/agent/guest/devcontainer.nix
- [ ] T067 [US5] Map DevContainer features to Nix packages in modules/keystone/agent/guest/devcontainer.nix
- [ ] T068 [US5] Apply port forwarding from devcontainer.json in modules/keystone/agent/proxy.nix
- [ ] T069 [US5] Implement `keystone agent open-vscode` command stub in bin/agent

**Checkpoint**: User Story 5 complete - DevContainer ecosystem accessible

---

## Phase 9: User Story 7 - Kubernetes Pod Backend (Priority: P4 - Stub Only)

**Goal**: Architecture supports future K8s backend (implementation deferred)

**Independent Test**: Config accepts `backend = "kubernetes"` without error

### Implementation for User Story 7 (Stubs)

- [ ] T070 [US7] Create Kubernetes backend stub in modules/keystone/agent/backends/kubernetes.nix
- [ ] T071 [US7] Add kubernetes backend config options (context, namespace, storage_class) in modules/keystone/agent/default.nix
- [ ] T072 [US7] Return "not implemented" error for kubernetes backend operations in bin/agent

**Checkpoint**: User Story 7 stubbed - architecture ready for future K8s implementation

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T073 [P] Add environment variable support per cli-spec.md in bin/agent
- [ ] T074 [P] Validate all exit codes match cli-spec.md in bin/agent
- [ ] T075 [P] Add --json output option to status and list commands in bin/agent
- [ ] T076 [P] Add comprehensive error messages for common failure modes in bin/agent
- [ ] T077 Run quickstart.md validation with actual commands
- [ ] T078 Ensure all NixOS module options have descriptions in modules/keystone/agent/default.nix

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-9)**: All depend on Foundational phase completion
  - US1 (Phase 3): Core sandbox launch
  - US2 (Phase 4): Depends on US1 (needs running sandbox)
  - US3 (Phase 5): Depends on US1 (needs running sandbox with workspace)
  - US4 (Phase 6): Depends on US1 (needs running sandbox)
  - US6 (Phase 7): Depends on US1 (needs MicroVM backend)
  - US5 (Phase 8): Depends on US1 (needs guest configuration)
  - US7 (Phase 9): Can be done in parallel with any phase after Foundational
- **Polish (Phase 10)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: REQUIRED - All other stories depend on this
- **User Story 2 (P1)**: Depends on US1 being complete (needs sandbox to attach to)
- **User Story 3 (P1)**: Depends on US1 being complete (needs workspace to sync)
- **User Story 4 (P2)**: Depends on US1 being complete (needs running sandbox)
- **User Story 6 (P2)**: Depends on US1 being complete (needs MicroVM)
- **User Story 5 (P3)**: Depends on US1 being complete (needs guest OS)
- **User Story 7 (P4)**: Independent (backend abstraction, stub only)

### Within Each User Story

- NixOS modules before CLI commands that use them
- Guest configuration before host features that interact with it
- Core functionality before optional features

### Parallel Opportunities

**Phase 2 (Foundational)**:
```bash
# All [P] tasks can run in parallel:
Task T007: "Define SandboxConfig options"
Task T008: "Define Backend options"
Task T009: "Create sandbox state directory"
Task T010: "Implement sandbox registry"
Task T011: "Create agent.toml parser"
Task T013: "Create CLI Click structure"
Task T014: "Add color output utilities"
```

**Phase 3 (US1) - Models/Config**:
```bash
Task T017: "Create guest OS base configuration"
Task T018: "Configure Claude Code package"
Task T019: "Add development tools to guest"
```

**Phase 5 (US3) - Sync Modes**:
```bash
Task T049: "Implement auto-commit sync mode"
Task T050: "Implement auto-idle sync mode"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 + 3)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Launch Sandbox)
4. Complete Phase 4: User Story 2 (TUI Session)
5. Complete Phase 5: User Story 3 (Sync)
6. **STOP and VALIDATE**: Full developer workflow testable
7. Deploy/demo if ready - THIS IS MVP

### Incremental Delivery

1. Complete Setup + Foundational -> Foundation ready
2. Add User Story 1 -> Test independently -> Sandboxes work (partial MVP)
3. Add User Story 2 -> Test independently -> TUI works
4. Add User Story 3 -> Test independently -> Sync works (FULL MVP!)
5. Add User Story 4 -> Test independently -> Web dev enhanced
6. Add User Story 6 -> Test independently -> Nested VMs work
7. Add User Story 5 -> Test independently -> DevContainer compatible
8. Add User Story 7 (stub) -> Test independently -> K8s-ready architecture
9. Each story adds value without breaking previous stories

### Key Files by Phase

| Phase | Key Files Created |
|-------|-------------------|
| Setup | modules/keystone/agent/, bin/agent, modules/keystone/agent/guest/ |
| Foundation | modules/keystone/agent/default.nix, bin/agent (Click app) |
| US1 | modules/keystone/agent/backends/microvm.nix, modules/keystone/agent/sync.nix, modules/keystone/agent/guest/*.nix |
| US2 | modules/keystone/agent/guest/zellij.nix, modules/keystone/agent/guest/worktree.nix |
| US3 | bin/agent-sync, modules/keystone/agent/sync.nix |
| US4 | modules/keystone/agent/proxy.nix, bin/agent-proxy |
| US6 | modules/keystone/agent/backends/microvm.nix (nested support) |
| US5 | modules/keystone/agent/guest/devcontainer.nix |
| US7 | modules/keystone/agent/backends/kubernetes.nix (stub) |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- US1, US2, US3 are all P1 priority but must be done sequentially (dependencies)
- MVP = Phase 1 + Phase 2 + Phase 3 + Phase 4 + Phase 5 (User Stories 1-3)
