# Keystone TUI — Agent Conventions

## Pre-Push Checklist

Before pushing any changes, run **all** of the following locally. These mirror
the `Validate / ks-cli` CI job — if any fail locally they will fail in CI.

```bash
# 1. Formatting (must pass with zero diff)
cargo fmt --check

# 2. Clippy with ALL targets (lib, bin, tests, examples) — warnings are errors
cargo clippy --all-targets --all-features -- -D warnings

# 3. Tests
cargo test
```

**Key detail**: Always use `--all-targets` (or `--tests`) with clippy. Plain
`cargo clippy` only checks lib and bin targets — it silently skips test files
under `tests/`, which will then fail in CI.
