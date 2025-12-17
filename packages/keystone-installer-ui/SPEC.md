# Keystone Installer UI Specification

## Overview

TUI installer using React/Ink that generates NixOS configurations and runs `nixos-install`.

## Installation Methods

| Method | Description |
|--------|-------------|
| **Local (New)** | Generate fresh NixOS config, partition disk via disko, install |
| **Clone** | Clone existing git repo, select host, install |
| **Remote** | Display SSH command for nixos-anywhere deployment |

## Screen Flow (Local/New)

```
checking → ethernet-connected/wifi-setup → method-selection → disk-selection →
disk-confirmation → encryption-choice → [tpm-warning] → hostname-input →
username-input → password-input → password-confirm → system-type-selection →
summary → installing → complete/error
```

## Installation Phases

| Phase | Function | Description |
|-------|----------|-------------|
| 1. Partitioning | `partitionDisk()` | Validates disk, defers to disko |
| 2. Formatting | `formatDisk()` | Defers to disko |
| 3. Mounting | `mountForInstall()` | Defers to disko |
| 4. Config Generation | `generateNixosConfig()` | Creates flake + host config |
| 5. NixOS Install | `runNixosInstall()` | Runs `nixos-install --flake` |
| 6. Config Copy | `copyConfigToInstalled()` | Copies config to installed system |
| 7. Cleanup | `cleanup()` | Unmounts, exports ZFS pool |

## Division of Responsibility

**Installer TUI handles:**
- Disk detection (`lsblk -J`)
- User input collection
- NixOS flake generation
- Running nixos-install

**Disko handles:**
- Partitioning (GPT, ESP, root, swap)
- Filesystem creation (ZFS or ext4)
- Mounting at /mnt
- Creating directory structure (including /home)
- Encrypted path: LUKS credstore, TPM2 unlock, initrd services

**nixos-install handles:**
- Executing disko configuration
- Applying NixOS system configuration
- Installing bootloader

## Generated Configuration Structure

```
/mnt/home/{username}/nixos-config/
├── flake.nix                           # Keystone + disko inputs
└── hosts/{hostname}/
    ├── default.nix                     # User, hostname, stateVersion
    ├── disk-config.nix                 # Disko configuration
    └── hardware-configuration.nix      # Auto-generated
```

## Disk Layouts

**Encrypted (ZFS + LUKS + TPM2):**
```
[ESP 1G] [ZFS Pool: rpool]
         ├── rpool/crypt (encrypted dataset)
         ├── rpool/credstore (100M LUKS for keys)
         └── rpool/swap
```

**Unencrypted (ext4):**
```
[ESP 1G] [Swap 8G] [Root ext4]
```

## Key Constants

| Constant | Value |
|----------|-------|
| `MOUNT_ROOT` | `/mnt` |
| `ZFS_POOL_NAME` | `rpool` |
| `ESP_SIZE` | `1G` |
| `DEFAULT_SWAP_SIZE` | `8G` |
| `CREDSTORE_SIZE` | `100M` |
| `MIN_DISK_SIZE` | 8GB |
| `NIXOS_VERSION` | `25.05` |
| `NIXOS_INSTALL_TIMEOUT` | 10 min |
| `GIT_CLONE_TIMEOUT` | 2 min |

## Config Generation Details

**flake.nix inputs:**
- `nixpkgs` (nixos-25.05)
- `keystone` (github:ncrmro/keystone)
- `disko` (github:nix-community/disko)

**flake.nix modules:**
- `disko.nixosModules.disko`
- `keystone.nixosModules.diskoSingleDiskRoot`
- `keystone.nixosModules.{server|client}`
- `./hosts/{hostname}`

**host default.nix:**
- `networking.hostName`
- `networking.hostId` (deterministic from hostname)
- Primary user with wheel/networkmanager groups
- Imports disk-config.nix and hardware-configuration.nix

## Git Initialization

**Git is NOT initialized during installation.**

User should run `git init` after first boot as their own user:
```bash
cd ~/nixos-config
git init
git add -A
git commit -m "Initial NixOS configuration"
```

**Why:** Initializing git during install causes ownership errors because the installer runs as root but nixos-install uses the Nix daemon (nixbld user), which refuses to operate on root-owned `.git` directories.

## Validation Rules

**Hostname:** RFC 1123 (max 63 chars, alphanumeric + hyphens, no leading/trailing hyphens)

**Username:** POSIX compliant (starts with letter, max 32 chars, reserved names blocked)

**Disk:** Min 8GB, not mounted, type "disk", has `/dev/disk/by-id/` path

## Dev Mode

When `DEV_MODE=1`:
- Paths use `/tmp/keystone-dev` instead of `/mnt`
- No actual disk operations
- Git operations logged but skipped
- Allows safe testing

## Files

| File | Purpose |
|------|---------|
| `App.tsx` | TUI screens and state management |
| `installation.ts` | Installation orchestration |
| `config-generator.ts` | NixOS config file generation |
| `disk.ts` | Disk detection and operations |
| `network.ts` | Network interface detection |
| `types.ts` | Types and constants |

## Automated Testing

The installer TUI has an automated test suite using NixOS's VM test framework.

### Test Files

| File | Purpose |
|------|---------|
| `tests/installer-test.nix` | VM test configuration and Python test script |
| `bin/test-installer` | Helper script for running tests |

### Running Tests

```bash
# Run test headlessly (for CI)
./bin/test-installer

# Run interactively (watch the VM)
./bin/test-installer --interactive

# Build only, don't run
./bin/test-installer --build-only
```

### Interactive Mode Commands

In interactive mode, a Python REPL is provided:

```python
>>> start_all()                    # Start the VM
>>> test_script()                  # Run full automated test
>>> installer.shell_interact()     # Drop into VM shell
>>> installer.wait_for_text('X')   # Wait for text on screen
>>> installer.send_key('ret')      # Send key (ret, down, up, esc)
>>> installer.send_chars('text')   # Type characters
```

### Test Flow

1. Boot VM with installer configuration
2. Start `keystone-installer` service
3. Wait for "Network Connected" screen
4. Navigate: Continue → Local installation → Select disk → Confirm
5. Select unencrypted installation
6. Enter hostname (`test-machine`), username (`testuser`), password (`testpass123`)
7. Select server type → Review summary → Start installation
8. Wait for "Installation Complete" (10 min timeout)
9. Verify installation artifacts:
   - `/mnt` is mounted
   - `/mnt/home/testuser/nixos-config/flake.nix` exists
   - `/mnt/etc/nixos/hardware-configuration.nix` exists

### VM Configuration

| Setting | Value |
|---------|-------|
| Memory | 8GB |
| CPUs | 4 |
| Boot | Direct kernel/initrd (no bootloader) |
| Target Disk | 20GB empty disk |
| Graphics | Enabled for interactive mode |

### Flake Integration

The test is exposed in the flake:

```bash
# Build test derivation
nix build .#checks.x86_64-linux.installer-test

# Build interactive driver
nix build .#checks.x86_64-linux.installer-test.driverInteractive
```
