# Keystone TUI — Technical Plan

## Architecture

The TUI follows the same architecture as `packages/keystone-ha/tui/`: a main event loop with `ratatui` + `crossterm`, an `App` state struct, and screen-based rendering. Async operations (git, nix builds, subprocess calls) run on `tokio`.

## Library Choices

| Library | Version | Purpose |
|---------|---------|---------|
| ratatui | 0.29 | TUI framework (proven in keystone-ha/tui) |
| crossterm | 0.28 | Terminal backend |
| tokio | 1 | Async runtime for subprocesses |
| clap | 4 | CLI argument parsing |
| git2 | 0.19 | Git operations (clone, commit, push, diff) |
| ssh-key | 0.6 | SSH key parsing and generation |
| rnix | 0.11 | Nix file parsing and AST manipulation |
| age | 0.11 | agenix-compatible encryption/decryption |
| directories | 6 | XDG config/data paths |
| serde + toml | 1 / 0.8 | Config serialization |
| anyhow + thiserror | 1 / 2 | Error handling |

### FIDO2

FIDO2 enrollment will initially shell out to `ssh-keygen -t ed25519-sk` rather than using a native crate. This avoids complex USB HID dependencies and matches what users expect. A native `ctap-hid-fido2` integration may be added later.

## Module Structure

```
src/
├── main.rs          # Entry point, terminal setup, event loop
├── lib.rs           # Module declarations
├── app.rs           # App state, screen enum, transitions
├── config.rs        # XDG config loading/saving (TOML)
├── screens/         # Screen-specific rendering and input
│   ├── mod.rs
│   ├── welcome.rs   # First-run / repo selection
│   ├── hosts.rs     # Host list and management
│   ├── keys.rs      # SSH/FIDO2 key management
│   ├── secrets.rs   # Secrets repo management
│   ├── build.rs     # Nix build output viewer
│   ├── git.rs       # Diff preview, commit, push
│   └── installer.rs # ISO installer mode
├── git.rs           # git2 wrapper operations
├── nix.rs           # rnix AST manipulation, flake generation
├── keys.rs          # SSH key detection, generation, FIDO2
├── secrets.rs       # age encryption operations
└── types.rs         # Shared types and error definitions
```

## Reference Implementation

The `packages/keystone-ha/tui/` crate provides the pattern for:
- Terminal setup/teardown with panic hook (`src/main.rs`)
- App state with screen enum (`src/app.rs`)
- Event handling with crossterm (`src/input.rs`)
- Screen-based rendering (`src/ui.rs`, `src/screens/`)

## Build and Packaging

- `default.nix`: Uses `rustPlatform.buildRustPackage` (same pattern as keystone-ha/tui)
- `flake.nix`: Self-contained dev shell with rust-overlay for IDE support
- Parent `flake.nix`: Exports as `packages.x86_64-linux.keystone-tui`

## Implementation Phases

1. **Skeleton** (this PR): Compilable binary with quit-on-q, Nix packaging, requirements + plan docs.
2. **Config + First Run**: XDG config, repo import/create, flake validation.
3. **Key Management**: SSH key detection, ed25519 generation, FIDO2 enrollment.
4. **Host Management**: Host listing, adding new hosts, Nix generation with rnix.
5. **Build + Git**: Nix build integration, diff preview, commit/push workflow.
6. **Secrets**: age encryption, secrets repo setup.
7. **Installer Mode**: ISO detection, installation workflow (replaces React Ink TUI).
