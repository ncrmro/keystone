# Implementation Plan - Notes (Rust TUI/CLI)

## Technical Context

This feature implements an automated agent system for a user's notes repository using a high-performance **Rust** CLI and TUI. It supports background cron jobs (via systemd), git synchronization, and AI agent execution (Claude/Gemini/Local).

**Key Components:**
1.  **Rust Binary (`keystone-notes`)**: A single binary providing both CLI commands and an interactive TUI.
2.  **Job Scheduler**: Generates systemd user units from `.keystone/jobs.toml`.
3.  **TUI Dashboard**: A `ratatui`-based interface to view job status, logs, and approve scripts.
4.  **Agent Runner**: Abstraction layer for invoking `claude-code`, `gemini`, or local LLM APIs.
5.  **Git Sync**: Robust synchronization logic using `git` commands.

**Dependencies:**
- **Language**: Rust (2021 edition).
- **Crates**:
  - `clap`: CLI argument parsing.
  - `ratatui`: Terminal User Interface.
  - `tokio`: Async runtime (essential for process management and I/O).
  - `serde`, `toml`, `serde_json`: Configuration and state serialization.
  - `anyhow`, `thiserror`: Error handling.
  - `sha2`: For script trust hashing.
  - `tracing`: Structured logging.

**Risks & Unknowns:**
- **TUI/Async Interaction**: Running long-running jobs (agents) while keeping the TUI responsive requires careful `tokio` task management.
- **Systemd Integration**: We rely on `systemctl` being available in the user's path.

## Constitution Check

| Principle | Compliant? | Justification |
| :--- | :--- | :--- |
| **Declarative Infrastructure** | Yes | Jobs defined in `.keystone/jobs.toml`. |
| **Security by Default** | Yes | Scripts require explicit "allow" (FR-009). |
| **Modular Composability** | Yes | Single binary, easy to install/remove. |
| **Hardware Agnostic** | Yes | Rust cross-compiles well; systemd is standard on Linux/NixOS. |
| **Cryptographic Sovereignty** | Yes | All keys and data remain local. |

## Phase 0: Outline & Research (Completed)

- [x] Defined scheduling architecture (Systemd User Units).
- [x] Defined context strategy (Hybrid Diff/File).
- [x] Defined trust mechanism (Hash-based).
- [x] Selected Rust stack (Ratatui, Clap, Tokio).

## Phase 1: Design & Contracts

### Goal
Define the configuration schema and internal Rust structures.

### Tasks
- [ ] Update `data-model.md` to reflect Rust types and CLI signature.
- [ ] Define the `jobs.toml` schema strictly.
- [ ] Update agent context (`AGENTS.md`) with Rust specifics.

### Output
- `specs/010-notes/data-model.md`

## Phase 2: Core Implementation (Crates)

### Goal
Implement the core logic libraries (could be modules within the binary crate for simplicity, or a workspace).

### Tasks
- [ ] **Config Module**: Structs for `AgentJob`, `GlobalConfig` with `toml` parsing.
- [ ] **Trust Module**: Logic for hashing files and managing `~/.local/share/keystone/allowlist.json`.
- [ ] **Git Module**: Wrapper around `git` commands for sync/diff operations.
- [ ] **Backend Module**: Trait `AgentBackend` and implementations for `ClaudeCode`, `Gemini`, `Ollama`.
- [ ] **Systemd Module**: Logic to generate `.service` and `.timer` files and call `systemctl`.

### Output
- Rust source code in `packages/keystone-notes/src/`.

## Phase 3: CLI & TUI Implementation

### Goal
Build the user-facing binary.

### Tasks
- [ ] **CLI**: Implement `clap` commands (`install-jobs`, `run`, `allow`, `sync`, `tui`).
- [ ] **TUI**: Implement `ratatui` interface.
  - **Dashboard**: List jobs, last run status, next run time.
  - **Logs View**: Stream logs from journalctl or internal buffer.
  - **Approval View**: List untrusted scripts and allow approving them.
- [ ] **Integration**: Wire up the `tui` command to launch the dashboard.

### Output
- Working `keystone-notes` binary.

## Phase 4: Integration & Polish

### Goal
Ensure smooth user experience.

### Tasks
- [ ] Create `quickstart.md` with Rust installation steps.
- [ ] Add extensive logging (tracing) to file `~/.local/share/keystone/agent.log`.
- [ ] Test with `claude-code` and `gemini` installed.

### Output
- Finalized feature.