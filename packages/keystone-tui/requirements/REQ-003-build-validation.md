# REQ-003: Build Validation

This document defines the automated test contract that proves the template
config generation produces buildable NixOS configurations. Tests run as part
of `nix flake check`.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### Test Infrastructure

**REQ-003.1** The test MUST be a Nix derivation importable as a flake check
via `checks.x86_64-linux.template-evaluation`.

**REQ-003.2** The test MUST provide a `mkTemplateConfig` helper function
that accepts the same data model inputs as REQ-002 and produces a NixOS
module importing `keystone.nixosModules.operating-system`.

**REQ-003.3** The `mkTemplateConfig` helper MUST mirror the configuration
structure that the TUI will generate, ensuring the test validates the same
output contract.

### Test Coverage

**REQ-003.4** The test MUST include at least 4 distinct configuration
variants covering: single-disk ZFS, multi-disk ZFS mirror, single-disk
ext4, and ZFS with desktop module.

**REQ-003.5** Each test configuration MUST evaluate successfully via
`nixpkgs.lib.nixosSystem` without errors.

**REQ-003.6** Each test configuration MUST force deep evaluation by
serializing `users.users`, `users.groups`, and `systemd.services` via
`builtins.toJSON`.

### Output

**REQ-003.7** The test derivation MUST write inspectable JSON output to
`$out/<config-name>.json` for each test configuration, containing at
minimum `users`, `groups`, and `services` keys.

**REQ-003.8** The test output SHOULD be examinable via
`nix build .#template-evaluation && cat result/<config-name>.json`.

### Integration

**REQ-003.9** The test MUST be included in `nix flake check` so CI
automatically validates template configs on every commit.

**REQ-003.10** The test MUST also be available as a check in the separate
test flake at `tests/flake.nix`.

**REQ-003.11** The test SHOULD have a corresponding `make test-template-eval`
target for developer convenience.
