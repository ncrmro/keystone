# Apple Silicon (macOS) Installation Plan

This document describes the complete workflow for installing Keystone NixOS on Apple Silicon Macs.

## Overview

Apple Silicon Macs require a specialized installation process due to:
1. **Asahi Linux kernel** - Standard NixOS kernel lacks display drivers (causes black screen)
2. **Preserved partitions** - Apple system partitions must not be modified
3. **U-Boot limitations** - Cannot touch EFI variables
4. **ext4 only** - ZFS not supported on Asahi kernel

## Prerequisites

### 1. Run Asahi Linux Installer

Before using the Keystone installer, run the Asahi Linux installer on macOS:

```bash
curl https://alx.sh | sh
```

Select **"UEFI environment only"** option. This creates:
- Stub APFS partition (2.5GB) - Contains m1n1 stage 1 bootloader
- EFI System Partition (500MB) - Contains m1n1 stage 2, U-Boot, and firmware

### 2. Boot Keystone Installer ISO

Build and boot the Apple Silicon installer ISO:

```bash
# From development machine
make build-iso-ssh-aarch64

# Or manually
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub --arch aarch64-linux
```

### 3. Establish Network Connectivity

After booting the ISO, verify network:
```bash
ip addr show
ping -c 3 google.com
```

## Installation Process

### Automated Installation

The `install-apple-silicon` script handles everything:

```bash
# Basic installation
install-apple-silicon --hostname my-macbook

# With SSH key for admin user
install-apple-silicon --hostname my-macbook --ssh-key ~/.ssh/id_ed25519.pub

# With LUKS encryption
install-apple-silicon --hostname my-macbook --encrypt

# Skip all prompts (for SSH automation)
install-apple-silicon --hostname my-macbook --ssh-key ~/.ssh/id_ed25519.pub --yes

# Preview without making changes
install-apple-silicon --dry-run
```

### What the Script Does

```
┌─────────────────────────────────────────────────────────────────┐
│                    INSTALLATION FLOW                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Detect Asahi ESP partition                                   │
│     └── From /proc/device-tree/chosen/asahi,efi-system-partition │
│                                                                  │
│  2. Create/format root partition                                 │
│     └── ext4 in free space between ESP and Recovery              │
│                                                                  │
│  3. Mount filesystems                                            │
│     ├── Root → /mnt                                              │
│     └── ESP → /mnt/boot                                          │
│                                                                  │
│  4. Generate NixOS configuration                                 │
│     ├── flake.nix (with nixos-apple-silicon)                     │
│     ├── configuration.nix                                        │
│     └── hardware-configuration.nix                               │
│                                                                  │
│  5. Run nixos-install --impure                                   │
│     └── Uses /mnt/boot/asahi for firmware path                   │
│                                                                  │
│  6. Update flake for runtime                                     │
│     └── Change /mnt/boot/asahi → /boot/asahi                     │
│                                                                  │
│  7. Pre-reboot verification (5 checks)                           │
│     ├── ✓ Asahi kernel installed                                 │
│     ├── ✓ Boot loader configured                                 │
│     ├── ✓ Firmware files present                                 │
│     ├── ✓ Flake uses runtime path                                │
│     └── ✓ canTouchEfiVariables = false                           │
│                                                                  │
│  8. If ALL checks pass → "Safe to reboot"                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Technical Details

### The Firmware Path Problem

The `peripheralFirmwareDirectory` option in nixos-apple-silicon is evaluated at **build time**, creating a path mismatch:

| Phase | ESP Mount | Firmware Path |
|-------|-----------|---------------|
| During install | `/mnt/boot` | `/mnt/boot/asahi` |
| After reboot | `/boot` | `/boot/asahi` |

**Solution**: Two-phase configuration
1. Install with `/mnt/boot/asahi` + `--impure` flag
2. Update to `/boot/asahi` before reboot
3. Future rebuilds work without `--impure`

### Why `--impure` is Required

Nix's pure evaluation mode blocks filesystem access. The `--impure` flag allows:
- Reading firmware files from `/mnt/boot/asahi`
- Evaluating paths that don't exist in the Nix store

After reboot, `/boot/asahi` exists on the running system, so pure evaluation works.

### Pre-Reboot Verification

The script runs 5 critical checks before allowing reboot:

1. **Asahi Kernel Check**
   - Verifies `*linux-asahi*.efi` exists in `/mnt/boot/EFI/nixos/`
   - Standard kernel causes BLACK SCREEN on Apple Silicon

2. **Boot Loader Check**
   - Verifies `loader.conf` exists
   - Verifies boot entry points to Asahi kernel

3. **Firmware Check**
   - Verifies `/mnt/boot/asahi/` directory exists
   - Verifies `all_firmware.tar.gz` is present

4. **Flake Configuration Check**
   - Verifies flake uses `/boot/asahi` (runtime path)
   - Fails if `/mnt/boot/asahi` (install path) still present

5. **Safety Settings Check**
   - Verifies `canTouchEfiVariables = false`
   - Setting this to `true` can brick the device

## Post-Installation

### First Boot

1. **Reboot**: `reboot`
2. **Boot picker**: Hold power button during boot
3. **Select NixOS** from the boot menu
4. **Login**: `admin` / `changeme`
5. **Change password**: `passwd`

### System Updates

After booting into the installed system:

```bash
cd /etc/nixos
sudo vim configuration.nix
sudo nixos-rebuild switch --flake .#my-macbook
```

Note: Future rebuilds do NOT require `--impure` because `/boot/asahi` exists.

## Troubleshooting

### Black Screen After Reboot

**Cause**: Standard NixOS kernel installed instead of Asahi kernel.

**Prevention**: The pre-reboot verification catches this. If you see:
```
[ERROR] Asahi kernel not found in boot partition!
[ERROR] Standard NixOS kernel will cause BLACK SCREEN on Apple Silicon
```

**Fix**: Do NOT reboot. Re-run installation with flake:
```bash
nixos-install --flake /mnt/etc/nixos#hostname --no-root-passwd --impure
```

### "access to absolute path forbidden" Error

**Cause**: Missing `--impure` flag during `nixos-install`.

**Fix**: Add `--impure`:
```bash
nixos-install --flake /mnt/etc/nixos#hostname --no-root-passwd --impure
```

### Firmware Path Error After Reboot

**Cause**: Flake still contains `/mnt/boot/asahi` instead of `/boot/asahi`.

**Fix**: Update the path:
```bash
sudo sed -i 's|/mnt/boot/asahi|/boot/asahi|g' /etc/nixos/flake.nix
sudo nixos-rebuild switch --flake /etc/nixos#hostname
```

### Recovery Mode

If the system won't boot:
1. Hold power button during boot
2. Select "Options" → "Startup Disk"
3. Boot back to macOS or recovery
4. Re-run installation from Keystone ISO

## Limitations

- **No ZFS**: Asahi kernel doesn't support ZFS
- **No Secure Boot**: U-Boot doesn't support Secure Boot
- **No TPM**: Apple Silicon doesn't have TPM2
- **ext4 only**: Must use ext4 for root filesystem
