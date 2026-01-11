# Research: Notes Agent Architecture (Rust Edition)

## 1. Scheduling Architecture

**Question**: How should we implement user-defined scheduling from `.keystone/jobs.toml`?

**Requirements**:
- Must run as the user.
- Must respect the schedule in the TOML file.
- Must update when the TOML file changes (or when the user runs an "apply" command).
- Should be robust (logs, retries).

**Decision**: Use **Systemd User Units**.
- **Implementation**: The Rust CLI (`keystone-notes install-jobs`) will read the TOML config.
- It will generate systemd unit files (`.service` and `.timer`) in `~/.config/systemd/user/`.
- It will use `std::process::Command` to call `systemctl --user daemon-reload` and `systemctl --user enable/start`.
- **Why Rust?**: Single binary distribution, fast startup for CLI commands, type-safe config parsing.

## 2. Context Strategy

**Question**: How to efficiently feed "recent context" to the agent?

**Decision**: Hybrid / Configurable.
- **Diff-based**: `git log -p -n X`.
- **File-based**: `git diff --name-only` -> Read files.
- **Implementation**:
  - Use `git2` crate (libgit2 bindings) for efficient git operations OR just shell out to `git` binary (simpler dep tree, often sufficient).
  - Given `claude-code` integration, piping output to its stdin is crucial.
  - **Regex Filtering**: Use `regex` crate to filter filenames/content.

## 3. Trust Mechanism

**Question**: How to secure script execution?

**Decision**: Implement **Hash-based Allowlist**.
- Store in `~/.local/share/keystone/script_allowlist.json`.
- **Rust Implementation**:
  - Struct `TrustStore` using `serde_json`.
  - SHA-256 hashing using `sha2` crate.
  - Check hash before any `Command::new(script).spawn()`.

## 4. AI Backend Abstraction & Agent CLI Integration

**Question**: How to unify the API and integrate with specialized agent CLIs (Claude Code, Gemini)?

**Decision**:
1.  **Unified Backend Trait**: Create a `Backend` trait in Rust.
    - `async fn generate(prompt: &str) -> Result<String>`.
2.  **Agent CLI Integration (MCP)**:
    - **Claude Code**: Execute `claude` binary, piping context into stdin.
    - **Gemini CLI**: Execute `gemini` binary.
    - **Ollama/Local**: Use `reqwest` to hit the local API endpoint.
3.  **TUI Integration**:
    - The TUI (built with `ratatui`) will primarily be for **viewing logs**, **managing jobs** (run/stop), and **approving scripts**.
    - It can also act as an interactive "Runner" where the output of the agent streams into a widget.

## 6. Example Project

A concrete example of a user's notes repository structure and configuration has been created in `specs/010-notes/research.example/`.

This directory contains:
- `.keystone/jobs.toml`: A valid configuration file.
- `scripts/`: Example scripts (`summarize.sh`, `fetch-movies.py`).
- `daily/`: Sample markdown notes.
- `README.md`: Usage instructions.

Developers should refer to this directory to understand the expected input/output of the `keystone-notes` agent.