---
repo: ncrmro/keystone
branch: feat/tui-red-green-tests
agent: gemini
priority: 1
status: ready
created: 2026-03-07
---

# Implement keystone-tui config generator with red-green TDD using rnix

## Description

Set up the `packages/keystone-tui/` Rust project and implement the Nix config
generator using red-green TDD. Tests use the `rnix` crate to parse generated
Nix files and assert on the AST structure, ensuring generated configs are
syntactically valid and structurally correct.

The generator takes a data model (REQ-002) and produces three files:
`flake.nix`, `configuration.nix`, and `hardware.nix` that satisfy REQ-001.

Tech stack: Rust (edition 2021), rnix for Nix AST parsing/validation, serde
for the data model, tempfile for test fixtures. Follow patterns from the
existing `packages/keystone-ha/` Ratatui TUI.

Reference files:
- `packages/keystone-tui/requirements/REQ-001-config-generation.md` — output contract
- `packages/keystone-tui/requirements/REQ-002-template-data-model.md` — input data model
- `packages/keystone-tui/requirements/REQ-003-build-validation.md` — test contract
- `packages/keystone-ha/tui/Cargo.toml` — existing Rust TUI for dependency patterns
- `templates/default/configuration.nix` — the config structure to generate
- `tests/module/template-evaluation.nix` — Nix-side evaluation test (complement to Rust tests)

## Approach: Red-Green TDD

1. **RED**: Write failing Rust tests that define expected output:
   - Parse generated `flake.nix` with rnix, assert it contains required inputs
     (nixpkgs, keystone, home-manager, disko)
   - Parse generated `configuration.nix` with rnix, assert it sets hostname,
     hostId, stateVersion, keystone.os.enable, storage config, users
   - Assert no `TODO:` markers appear in generated output
   - Assert `hardware.nix` is a valid empty module `{ ... }: { }`
   - Test 4 variants: minimal-zfs, mirror-zfs, ext4-simple, zfs-desktop

2. **GREEN**: Implement the generator to make tests pass:
   - Define `TemplateConfig` struct matching REQ-002 data model
   - Implement `generate_flake_nix()`, `generate_configuration_nix()`,
     `generate_hardware_nix()` functions
   - Use string formatting (not a template engine) for Nix generation since
     Nix syntax doesn't map well to general-purpose template engines

3. **REFACTOR**: Extract shared patterns, add edge case tests

## Acceptance Criteria

- [x] `packages/keystone-tui/Cargo.toml` exists with rnix, serde, serde_json, tempfile dependencies
- [x] `packages/keystone-tui/src/lib.rs` exports `config` and `generator` modules
- [x] `packages/keystone-tui/src/config.rs` defines `TemplateConfig` struct matching REQ-002 data model
- [x] `packages/keystone-tui/src/generator.rs` implements `generate_flake_nix()`, `generate_configuration_nix()`, `generate_hardware_nix()`
- [x] `packages/keystone-tui/tests/config_gen.rs` contains integration tests using rnix to parse and validate generated Nix files
- [x] Tests cover 4 config variants: minimal-zfs, mirror-zfs, ext4-simple, zfs-desktop
- [x] Tests assert: valid Nix syntax (rnix parses without error), no TODO markers, required attributes present (hostname, hostId, keystone.os.enable, storage.type, users)
- [x] `cargo test` passes in the `packages/keystone-tui/` directory
- [x] Generated `flake.nix` includes nixpkgs, keystone, home-manager inputs and imports operating-system module
- [x] Generated `configuration.nix` sets all required keystone.os options based on input config
- [x] Generated `hardware.nix` is `{ ... }: { }` placeholder

## Agent Notes

- Initialized `packages/keystone-tui` as a Rust project.
- Implemented `TemplateConfig` matching REQ-002 with `serde` support.
- Implemented `generator.rs` using string formatting to produce valid Nix files.
- Used `rnix` in tests to ensure generated files have valid Nix syntax.
- Verified all 4 requested configuration variants in integration tests.
- Handled conditional imports of `home-manager` and `desktop` modules in `flake.nix`.

## Results

```bash
running 4 tests
test test_ext4_simple_generation ... ok
test test_mirror_zfs_generation ... ok
test test_zfs_desktop_generation ... ok
test test_minimal_zfs_generation ... ok

test result: ok. 4 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```
