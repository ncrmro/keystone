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
| libvirt + QEMU | Full deployment testing | `bin/virtual-machine` |
| **microvm.nix** | Fast TPM/module testing | `tests/microvm/` |

---

## Testing Framework Comparison

### Framework Capabilities Matrix

| Capability | nixos-rebuild build-vm | microvm.nix | NixOS Test | libvirt + OVMF |
|------------|------------------------|-------------|------------|----------------|
| **Boot Time** | ~10s | ~2-5s | ~30s | ~60s |
| **UEFI/OVMF** | ❌ | ❌ | ✅ (configurable) | ✅ |
| **Secure Boot** | ❌ | ❌ | ✅ | ✅ |
| **TPM Emulation** | ❌ | ✅ (swtpm) | ✅ | ✅ (swtpm) |
| **Persistent Disk** | ✅ (qcow2) | ✅ (volumes) | ❌ (ephemeral) | ✅ |
| **9P/virtiofs** | ✅ | ✅ | ✅ | ❌ |
| **Network** | User-mode | TAP/bridge | Internal | Bridge/NAT |
| **Nix Integration** | Native | Native | Native | Scripts |
| **CI Friendly** | ✅ | ✅ | ⚠️ (IFD issues) | ❌ (KVM required) |
| **Multi-boot Test** | Manual | Manual | ✅ (Python) | ✅ |

### Framework Selection Guide

| Use Case | Recommended Framework | Rationale |
|----------|----------------------|-----------|
| Desktop/terminal config iteration | `nixos-rebuild build-vm` | Fast, mounts host Nix store |
| TPM enrollment logic testing | microvm.nix | Fast boot, swtpm integration |
| Module isolation testing | microvm.nix | Lightweight, reproducible |
| Installer TUI automation | `runNixOSTest` | Python scripting, OCR support |
| Full Secure Boot chain | libvirt + OVMF | Only option with UEFI |
| TPM auto-unlock verification | libvirt + OVMF | Requires real boot chain |
| Remote unlock (initrd SSH) | libvirt or NixOS Test | Needs network + reboot |

### Key Findings: microvm.nix Limitations

**microvm.nix does NOT support UEFI boot.** The QEMU runner uses direct kernel boot exclusively:

```nix
# From microvm.nix lib/runners/qemu.nix
"-kernel" "${kernelPath}"
"-initrd" initrdPath
# No -bios or -drive pflash options
```

**Implications:**
- Cannot test Secure Boot enrollment or verification
- Cannot test lanzaboote signed kernel chain
- TPM PCR 7 (Secure Boot state) will have different values than real hardware
- Cannot validate `boot.loader.efi.canTouchEfiVariables` assertions

**What CAN be tested with microvm.nix:**
- TPM device availability (`/dev/tpm0`)
- `systemd-cryptenroll` TPM enrollment on loopback devices
- `systemd-cryptsetup` TPM unlock
- LUKS2 + TPM token handling
- TPM PCR binding (except PCR 7)
- Module configuration and service startup

---

## microvm.nix Implementation

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Host                                                        │
│  ┌─────────────┐    ┌──────────────────────────────────┐   │
│  │   swtpm     │◄───│  bin/test-microvm-tpm            │   │
│  │  (socket)   │    │  - Starts swtpm                  │   │
│  └──────┬──────┘    │  - Builds microvm runner         │   │
│         │           │  - Runs test, checks output      │   │
│         │           └──────────────────────────────────┘   │
│         │                                                   │
│  ┌──────▼──────────────────────────────────────────────┐   │
│  │ MicroVM (QEMU direct kernel boot)                   │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │ NixOS Guest                                    │ │   │
│  │  │  - /dev/tpm0 (virtio-tpm)                     │ │   │
│  │  │  - security.tpm2.enable = true                │ │   │
│  │  │  - systemd.services.verify-tpm (test logic)   │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Configuration Structure

**Flake input** (`tests/flake.nix`):
```nix
inputs.microvm = {
  url = "github:astro/microvm.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**NixOS configuration** (`tests/microvm/tpm-test.nix`):
```nix
{ pkgs, ... }: {
  microvm = {
    hypervisor = "qemu";
    qemu.extraArgs = [
      "-chardev" "socket,id=chrtpm,path=./swtpm-sock"
      "-tpmdev" "emulator,id=tpm0,chardev=chrtpm"
      "-device" "tpm-tis,tpmdev=tpm0"
    ];
  };

  # Don't use keystone.os - requires UEFI assertions
  keystone.os.enable = false;

  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
    tctiEnvironment.enable = true;
  };

  # Test service that runs on boot
  systemd.services.verify-tpm = {
    wantedBy = [ "multi-user.target" ];
    script = ''
      # Test TPM presence and enrollment
      systemd-cryptenroll /dev/loop0 --tpm2-device=auto --tpm2-pcrs=0
      echo "--- TPM Test: PASSED ---"
      poweroff
    '';
  };
}
```

### Test Runner Script Pattern

**`bin/test-microvm-tpm`**:
```bash
#!/usr/bin/env bash
set -euo pipefail

TPM_DIR=$(mktemp -d)
SWTPM_SOCK="$TPM_DIR/swtpm-sock"

cleanup() {
  kill "$SWTPM_PID" 2>/dev/null || true
  rm -rf "$TPM_DIR"
}
trap cleanup EXIT

# 1. Start swtpm
swtpm socket --tpmstate dir="$TPM_DIR" \
  --ctrl type=unixio,path="$SWTPM_SOCK" \
  --tpm2 &
SWTPM_PID=$!

# 2. Wait for socket
while [ ! -S "$SWTPM_SOCK" ]; do sleep 0.1; done

# 3. Symlink to project root (where microvm expects it)
ln -sf "$SWTPM_SOCK" ./swtpm-sock

# 4. Build and run
nix build ./tests#nixosConfigurations.tpm-microvm.config.microvm.declaredRunner
./result/bin/microvm-run > microvm.log 2>&1

# 5. Check results
grep -q "--- TPM Test: PASSED ---" microvm.log
```

### Integration with keystone.os Module

The `keystone.os` module requires `storage.devices` and Secure Boot assertions that don't apply to microvm testing. Two approaches:

**Option A: Disable keystone.os entirely** (current approach)
```nix
keystone.os.enable = false;
# Configure TPM manually via security.tpm2
```

**Option B: Use storage.enable = false** (requires module change)
```nix
keystone.os = {
  enable = true;
  storage.enable = false;  # Skip disk management
  secureBoot.enable = false;  # Skip UEFI assertions
  tpm.enable = false;  # Skip enrollment scripts
};
# Then configure TPM manually
```

Option B is cleaner but requires adding `storage.enable`, `secureBoot.enable` guards to skip assertions.

### Layered Testing Strategy

| Tier | Framework | Speed | Coverage | CI |
|------|-----------|-------|----------|-----|
| **1. Fast** | microvm.nix | ~5s | TPM enrollment, module config | ✅ |
| **2. Medium** | NixOS Test | ~30s | Multi-node, remote unlock | ⚠️ |
| **3. Full** | libvirt + OVMF | ~60s | Secure Boot, TPM PCR 7 | Manual |

**Workflow:**
1. Iterate on TPM logic with microvm (~5s feedback loop)
2. Validate remote unlock with NixOS test framework
3. Full integration test with libvirt before merge

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

| Gap | Impact | Priority | Status |
|-----|--------|----------|--------|
| No `checks` output in flake | Tests not discoverable via standard Nix tooling | Medium | Open |
| No Rust unit tests | TUI packages untested | High | Open |
| No TypeScript unit tests | Installer UI logic untested | High | Open |
| No NixOS module unit tests | Module options not validated in isolation | Medium | Open |
| TPM only tested via full deployment | Slow feedback loop | Medium | **Addressed by microvm** |
| SecureBoot only tested via full deployment | No fast iteration path | Low | Requires UEFI (libvirt only) |
| No formal test matrix | Coverage unclear | High | **Documented above** |

---

## Proposed Testing Matrix

### Test Categories

| Category | Scope | Framework | CI? |
|----------|-------|-----------|-----|
| **Unit** | Individual functions/modules | Native (Rust/TS/Nix) | Yes |
| **Module** | NixOS module evaluation | `nixosTest` nodes | Yes |
| **Fast Integration** | TPM, services, config | microvm.nix | Yes |
| **Integration** | Multi-component interaction | `nixosTest` | Selective |
| **System** | Full OS with security | libvirt + deployment | Manual |

### Component × Test Type Matrix

| Component | Unit | microvm | NixOS Test | libvirt |
|-----------|------|---------|------------|---------|
| **TUI (Rust)** | `cargo test` | - | - | - |
| **Installer UI** | `npm test` | - | VM test | - |
| **OS Module** | Nix eval | Config boot | - | Full deploy |
| **Storage** | - | - | ZFS create | Encryption |
| **Secure Boot** | - | ❌ (no UEFI) | ✅ | ✅ |
| **TPM** | - | ✅ Enrollment | ✅ | ✅ Auto-unlock |
| **Desktop** | - | - | Hyprland start | Full session |
| **Server** | - | Services start | SSH access | Remote unlock |
| **Remote Unlock** | - | - | Initrd SSH | Full reboot |

### Detailed Test Scenarios

#### Tier 1: Fast Feedback (CI - Always) - ~seconds
- `nix flake check` - Flake validity
- Nix module evaluation - All configs build
- Rust `cargo test` - TUI unit tests
- TypeScript `npm test` - Installer unit tests

#### Tier 2: microvm Tests (CI - On Change) - ~5s per test
- **TPM enrollment**: Create loopback LUKS, enroll TPM, verify unlock
- **Service startup**: Validate systemd services start correctly
- **Module config**: Test keystone.os options without full boot chain
- **Command**: `nix develop --command ./bin/test-microvm-tpm`

#### Tier 3: NixOS VM Tests (CI - Selective) - ~30s per test
- **Desktop isolation**: Hyprland boots, greetd works, audio available
- **Server isolation**: SSH accessible, services running
- **Installer flow**: Full TUI walkthrough (existing test)
- **Remote unlock**: Initrd SSH + disk unlock
- **Home-manager**: Terminal/desktop environment evaluation

#### Tier 4: libvirt System Tests (Manual/Nightly) - ~60s+
- **Full deployment**: nixos-anywhere with TPM + SecureBoot
- **TPM auto-unlock**: Boot without password after enrollment
- **SecureBoot chain**: Signed kernel verification (UEFI required)
- **Command**: `./bin/virtual-machine --name test --start`

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
- [microvm.nix Documentation](https://astro.github.io/microvm.nix/)
- [microvm.nix GitHub](https://github.com/astro/microvm.nix)
- [swtpm - Software TPM Emulator](https://github.com/stefanberger/swtpm)
- [NixOS OVMF Configuration](https://discourse.nixos.org/t/enable-secure-boot-for-qemu/15718)
- Current: `tests/installer-test.nix`, `bin/test-installer`, `bin/virtual-machine`
- New: `tests/microvm/tpm-test.nix`, `bin/test-microvm-tpm`
