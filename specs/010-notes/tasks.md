---
description: "Task list for Notes Agent implementation"
---

# Tasks: Notes Agent (Rust TUI/CLI)

**Input**: Design documents from `specs/010-notes/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: Not explicitly requested in specification. Test tasks omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Rust Project Root**: `packages/keystone-notes/`
- **Source**: `packages/keystone-notes/src/`
- **Modules**: `packages/keystone-notes/src/modules/`

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Create project structure and foundational scaffolding

- [ ] T001 Initialize Rust project `keystone-notes` in `packages/keystone-notes/` with `cargo init`
- [ ] T002 Add dependencies (clap, ratatui, tokio, serde, toml, anyhow, tracing) to `packages/keystone-notes/Cargo.toml`
- [ ] T003 [P] Create module directory structure in `packages/keystone-notes/src/` (config, backend, git, systemd, trust, tui)
- [ ] T004 Define `Cli` struct with subcommands in `packages/keystone-notes/src/cli.rs`
- [ ] T005 [P] Setup logging with `tracing` and `tracing-appender` in `packages/keystone-notes/src/main.rs`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T006 Define `Config`, `GlobalConfig`, `JobConfig` structs in `packages/keystone-notes/src/modules/config.rs`
- [ ] T007 Implement TOML configuration loading and validation in `packages/keystone-notes/src/modules/config.rs`
- [ ] T008 [P] Define `TrustStore` and `TrustEntry` structs in `packages/keystone-notes/src/modules/trust.rs`
- [ ] T009 [P] Implement `TrustManager` with `is_allowed` and `approve` methods in `packages/keystone-notes/src/modules/trust.rs`
- [ ] T010 [P] Implement `SystemdManager` to generate .service/.timer files in `packages/keystone-notes/src/modules/systemd.rs`
- [ ] T011 Define `Backend` trait with `generate` async method in `packages/keystone-notes/src/modules/backend/mod.rs`
- [ ] T012 [P] Implement `MCPClient` for process-based agent interaction in `packages/keystone-notes/src/modules/backend/mcp.rs`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Automated Note Synchronization (Priority: P1) MVP

**Goal**: Robust git synchronization (pull-rebase-push)

**Independent Test**: Run `keystone-notes sync`, verify changes synced between local/remote

### Implementation for User Story 1

- [ ] T013 [P] [US1] Implement `GitWrapper` for git commands (status, pull, push, diff) in `packages/keystone-notes/src/modules/git.rs`
- [ ] T014 [US1] Implement `sync` logic (stash -> pull --rebase -> pop -> add -> commit -> push) in `packages/keystone-notes/src/modules/git.rs`
- [ ] T015 [US1] Wire up `keystone-notes sync` CLI command in `packages/keystone-notes/src/main.rs`
- [ ] T016 [US1] Implement `install-jobs` command to register the "builtin:sync" job in `packages/keystone-notes/src/commands/install.rs`

**Checkpoint**: User Story 1 complete - Sync is functional

---

## Phase 4: User Story 2 - Daily Task Analysis & Summary (Priority: P1)

**Goal**: AI agent reviews recent notes and generates summary

**Independent Test**: Run `keystone-notes run daily-summary`, verify summary note created

### Implementation for User Story 2

- [ ] T017 [P] [US2] Implement `ContextBuilder` with `diff` mode (git log -p) in `packages/keystone-notes/src/modules/context.rs`
- [ ] T018 [P] [US2] Implement `ClaudeCodeBackend` using `MCPClient` in `packages/keystone-notes/src/modules/backend/claude.rs`
- [ ] T019 [P] [US2] Implement `GeminiBackend` using `MCPClient` in `packages/keystone-notes/src/modules/backend/gemini.rs`
- [ ] T020 [US2] Implement `AgentRunner` to orchestrate Context -> Prompt -> Backend -> Result in `packages/keystone-notes/src/modules/runner.rs`
- [ ] T021 [US2] Wire up `keystone-notes run <job>` CLI command in `packages/keystone-notes/src/main.rs`

**Checkpoint**: User Story 2 complete - AI summaries functional

---

## Phase 5: User Story 3 - Extensible Data Feeds (Priority: P2)

**Goal**: Execute external scripts safely and inject data

**Independent Test**: Create script, approve it, run job, verify output used

### Implementation for User Story 3

- [ ] T022 [US3] Wire up `keystone-notes allow <path>` CLI command in `packages/keystone-notes/src/commands/allow.rs`
- [ ] T023 [US3] Update `AgentRunner` to verify script trust before execution in `packages/keystone-notes/src/modules/runner.rs`
- [ ] T024 [US3] Implement script output capture and injection into prompt in `packages/keystone-notes/src/modules/runner.rs`

**Checkpoint**: User Story 3 complete - Safe script execution

---

## Phase 6: User Story 4 - Local Model & TUI (Priority: P2)

**Goal**: Local privacy and interactive dashboard

**Independent Test**: Run TUI, see jobs; Configure Ollama, run job without internet

### Implementation for User Story 4

- [ ] T025 [P] [US4] Implement `OllamaBackend` using `reqwest` in `packages/keystone-notes/src/modules/backend/ollama.rs`
- [ ] T026 [P] [US4] Create TUI layout (Dashboard, Logs, Approval) in `packages/keystone-notes/src/tui/layout.rs`
- [ ] T027 [US4] Implement TUI state management (jobs list, running status) in `packages/keystone-notes/src/tui/state.rs`
- [ ] T028 [US4] Wire up `keystone-notes tui` command in `packages/keystone-notes/src/main.rs`

**Checkpoint**: User Story 4 complete - Local models and TUI

---

## Phase 7: User Story 5 - Quick Daily Note Access (Priority: P2)

**Goal**: Open daily notes in editor

**Independent Test**: Run `keystone-notes daily`, verify editor opens

### Implementation for User Story 5

- [ ] T029 [US5] Implement `Daily` command logic (date calculation, file creation, process spawn) in `packages/keystone-notes/src/commands/daily.rs`
- [ ] T030 [US5] Wire up `keystone-notes daily` command in `packages/keystone-notes/src/main.rs`

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T031 Create `packages/keystone-notes/README.md` with installation steps
- [ ] T032 Add error handling for network failures in `GitWrapper` and `Backend` modules
- [ ] T033 Validate `quickstart.md` instructions

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Depends on Setup
- **User Story 1 (Phase 3)**: Depends on Foundational (needs Config, Systemd, Git)
- **User Story 2 (Phase 4)**: Depends on Foundational (needs Config, Backend trait)
- **User Story 3 (Phase 5)**: Depends on US2 (extends Runner) and Foundational (needs Trust)
- **User Story 4 (Phase 6)**: Depends on Foundational (needs Backend trait)
- **User Story 5 (Phase 7)**: Depends on Setup (needs CLI structure), largely independent

### Parallel Opportunities

- **Phase 2**: Config (T006, T007), Trust (T008, T009), Systemd (T010), and MCP (T012) are largely independent.
- **Phase 3**: Git implementation (T013) can run parallel to CLI wiring (T015).
- **Phase 4**: Context (T017), Claude (T018), and Gemini (T019) backends can run in parallel.
- **Phase 6**: Ollama backend (T025) and TUI layout (T026) can run in parallel.
- **Phase 7**: Daily command (T029) can run in parallel with other User Stories.

### Implementation Strategy

1. **MVP**: Setup -> Foundational -> US1 (Sync). This gives basic value.
2. **AI MVP**: Add US2 (Summaries) with Cloud Backends.
3. **Security**: Add US3 (Trust/Scripts).
4. **Full Feature**: Add US4 (Local/TUI) and US5 (Daily Note).
