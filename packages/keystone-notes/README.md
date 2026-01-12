# Keystone Notes Agent

A Rust-based agent for managing personal notes with Git synchronization, automated summaries, and extensibility.

## Installation

```bash
# From source
cd packages/keystone-notes
cargo install --path .
```

## Usage

1. **Setup Config**: Create `.keystone/jobs.toml` in your notes repo.
2. **Install Jobs**: `keystone-notes install-jobs`
3. **Allow Scripts**: `keystone-notes allow scripts/`
4. **Sync**: `keystone-notes sync`
5. **Daily Note**: `keystone-notes daily`
6. **TUI**: `keystone-notes tui`

## Configuration

See `specs/010-notes/data-model.md` for full configuration options.
