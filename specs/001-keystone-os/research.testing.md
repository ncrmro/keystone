# Keystone Testing Infrastructure Research

## Current State Analysis

### Test Locations

| Location | Type | Purpose |
|----------|------|---------|
| `tests/installer-test.nix` | NixOS VM Test | Installer TUI validation with OCR |
| `vms/build-vm-terminal/` | NixOS Config | Fast terminal dev env testing |
| `vms/build-vm-desktop/` | NixOS Config | Fast Hyprland desktop testing |
| `vms/test-server/` | NixOS Config | Full security stack (ZFS, TPM, SecureBoot) |
| `vms/test-hyprland/` | NixOS Config | Full desktop + security stack |

### Current `flake.nix` Test Strategy

**Key Design Decision**: Tests are in `packages` NOT `checks`:

```nix
packages.x86_64-linux = {
  # Internal VM test - run with: nix build .#installer-test
  # Not in checks to avoid IFD evaluation issues with nix flake check
  # (NixOS VM tests use kernel modules that cause IFD failures in CI)
  installer-test = import ./tests/installer-test.nix { ... };
};
```

**Rationale**: NixOS VM tests require kernel modules which cause Import-From-Derivation (IFD) failures during `nix flake check` evaluation in CI environments.

### Testing Frameworks Used

| Framework | Usage | Location |
|-----------|-------|----------|
| `pkgs.testers.runNixOSTest` | Installer TUI automation | `tests/installer-test.nix` |
| `nixos-rebuild build-vm` | Fast config iteration | `bin/build-vm` |
| libvirt + Python | Full deployment testing | `bin/test-deployment` |

### Testable Components Inventory

#### 1. TUI Packages

| Package | Language | Path | Current Tests |
|---------|----------|------|---------------|
| keystone-ha-tui-client | Rust | `packages/keystone-ha/tui/` | None |
| keystone-ha-common | Rust | `packages/keystone-ha/common/` | None |
| keystone-installer-ui | TypeScript | `packages/keystone-installer-ui/` | VM test only |

#### 2. NixOS Modules

| Module | Path | Current Tests |
|--------|------|---------------|
| OS (consolidated) | `modules/os/` | test-server config |
| Storage (ZFS/LUKS) | `modules/os/storage.nix` | test-server config |
| Secure Boot | `modules/os/secure-boot.nix` | test-deployment |
| TPM | `modules/os/tpm.nix` | test-deployment |
| Remote Unlock | `modules/os/remote-unlock.nix` | test-deployment |
| Users | `modules/os/users.nix` | test-server/hyprland |
| SSH | `modules/os/ssh.nix` | test-server/hyprland |
| Server | `modules/server/` | test-server config |
| Client | `modules/client/` | test-hyprland config |
| ISO Installer | `modules/iso-installer.nix` | iso build only |

#### 3. Home-Manager Modules

| Module | Path | Current Tests |
|--------|------|---------------|
| Terminal Dev Env | `home-manager/modules/terminal-dev-environment/` | build-vm-terminal |
| Desktop Hyprland | `home-manager/modules/desktop/hyprland/` | build-vm-desktop |
| Keystone Terminal | `modules/keystone/terminal/` | Partial |
| Keystone Desktop | `modules/keystone/desktop/` | Partial |

### CI/CD Integration

**GitHub Actions** (`.github/workflows/test.yml`):
- Conditional execution based on file changes
- `nix flake check` always runs
- ISO build on ISO-related changes
- Installer test on installer changes (with KVM enabled)

### Gaps Identified

| Gap | Impact | Priority |
|-----|--------|----------|
| No `checks` output in flake | Tests not discoverable via standard Nix tooling | Medium |
| No Rust unit tests | TUI packages untested | High |
| No TypeScript unit tests | Installer UI logic untested | High |
| No NixOS module unit tests | Module options not validated in isolation | Medium |
| TPM/SecureBoot only tested via full deployment | Slow feedback loop | Medium |
| No formal test matrix | Coverage unclear | High |

---

## Proposed Testing Matrix

### Test Categories

| Category | Scope | Framework | CI? |
|----------|-------|-----------|-----|
| **Unit** | Individual functions/modules | Native (Rust/TS/Nix) | Yes |
| **Module** | NixOS module evaluation | `nixosTest` nodes | Yes |
| **Integration** | Multi-component interaction | `nixosTest` | Selective |
| **System** | Full OS with security | libvirt + deployment | Manual |

### Component × Test Type Matrix

| Component | Unit | Module | Integration | System |
|-----------|------|--------|-------------|--------|
| **TUI (Rust)** | `cargo test` | - | - | - |
| **Installer UI** | `npm test` | - | VM test | - |
| **OS Module** | Nix eval | Node boot | - | Full deploy |
| **Storage** | - | ZFS create | Encryption | TPM unlock |
| **Secure Boot** | - | Key gen | Enrollment | Boot verify |
| **TPM** | - | PCR config | Enrollment | Auto-unlock |
| **Desktop** | - | Hyprland start | Login flow | Full session |
| **Server** | - | Services start | SSH access | Remote unlock |

### Detailed Test Scenarios

#### Tier 1: Fast Feedback (CI - Always)
- `nix flake check` - Flake validity
- Nix module evaluation - All configs build
- Rust `cargo test` - TUI unit tests
- TypeScript `npm test` - Installer unit tests

#### Tier 2: Module Tests (CI - On Change)
- **Desktop isolation**: Hyprland boots, greetd works, audio available
- **Server isolation**: SSH accessible, services running
- **OS module**: ZFS pool imports, users created, SSH keys work

#### Tier 3: Integration Tests (CI - On Change)
- **Installer flow**: Full TUI walkthrough (existing test)
- **Remote unlock**: Initrd SSH + disk unlock
- **Home-manager**: Terminal/desktop environment evaluation

#### Tier 4: System Tests (Manual/Nightly)
- **Full deployment**: nixos-anywhere with TPM + SecureBoot
- **TPM auto-unlock**: Boot without password after enrollment
- **SecureBoot chain**: Signed kernel verification

---

## NixOS Test Framework Patterns

### Standard Pattern (from user guide)

```nix
# tests/module-name.nix
{ pkgs, moduleToTest }:

pkgs.nixosTest {
  name = "module-name-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ moduleToTest ];
    # Test-specific configuration
  };

  testScript = ''
    machine.wait_for_unit("some.service")
    machine.succeed("some-command")
  '';
}
```

### Flake Integration

```nix
checks = forAllSystems (system: {
  module-test = import ./tests/module-test.nix {
    pkgs = nixpkgs.legacyPackages.${system};
    moduleToTest = self.nixosModules.someModule;
  };
});
```

### IFD Workaround Strategy

For tests that cause IFD issues:
1. Keep in `packages` output (current approach)
2. Run explicitly: `nix build .#test-name`
3. CI runs via wrapper scripts that build explicitly

---

## Recommendations

### 1. Directory Structure

```
tests/
├── unit/
│   ├── installer-ui/      # TypeScript tests
│   └── tui/               # Rust tests (or inline)
├── module/
│   ├── os.nix             # OS module evaluation
│   ├── desktop.nix        # Desktop isolation test
│   └── server.nix         # Server isolation test
├── integration/
│   ├── installer.nix      # Current installer-test.nix
│   ├── remote-unlock.nix  # Initrd SSH unlock
│   └── home-manager.nix   # HM module evaluation
└── system/
    └── README.md          # Manual test procedures
```

### 2. Flake Output Organization

```nix
checks.x86_64-linux = {
  # Fast checks (always run)
  flake-check = ...;           # Implicit
  rust-tests = ...;            # cargo test
  typescript-tests = ...;      # npm test

  # Module checks (evaluation only, no VM)
  eval-os = ...;
  eval-desktop = ...;
  eval-server = ...;
};

packages.x86_64-linux = {
  # VM tests (explicit build to avoid IFD)
  test-installer = ...;
  test-desktop-isolation = ...;
  test-remote-unlock = ...;
};
```

### 3. CI Matrix

```yaml
jobs:
  fast-checks:
    - nix flake check
    - cargo test (if Rust changes)
    - npm test (if TS changes)

  module-tests:
    needs: fast-checks
    if: modules changed
    - nix build .#test-desktop-isolation
    - nix build .#test-server-isolation

  integration-tests:
    needs: module-tests
    if: installer or OS changes
    - nix build .#test-installer
```

---

## References

- [NixOS Testing Framework](https://nixos.org/manual/nixos/stable/#sec-nixos-tests)
- [Nix Flake Checks](https://nixos.wiki/wiki/Flakes#Output_schema)
- Current: `tests/installer-test.nix`, `bin/test-installer`, `bin/test-deployment`
