# Research: NixOS on Apple Silicon MacBooks

## Overview

This document researches the feasibility of running Keystone on Apple Silicon Macs using the [nixos-apple-silicon](https://github.com/nix-community/nixos-apple-silicon) project, which provides NixOS support for M1/M2/M3 hardware via Asahi Linux.

## Current State of Apple Silicon Linux Support

### Asahi Linux Project

Asahi Linux provides the foundational drivers and firmware for running Linux on Apple Silicon. Key achievements:

- **GPU**: World's first certified conformant OpenGL 4.6, OpenGL ES 3.2, OpenCL 3.0, and Vulkan 1.4 for Apple Silicon
- **Audio**: Fully integrated DSP solution with Smart Amp implementation
- **Webcam**: Supported on MacBook Air, MacBook Pro, and iMac
- **Touch ID**: Fingerprint authentication supported
- **Thunderbolt/USB4**: Supported on all devices

### NixOS Integration

The [nixos-apple-silicon](https://github.com/nix-community/nixos-apple-silicon) project provides:

- NixOS modules for Apple Silicon hardware
- Pre-built installation ISOs
- Integration with Asahi Linux kernel and drivers

## Installation Process

### Boot Chain

Apple Silicon uses a unique boot process:

1. **Apple Boot Firmware** → Initial hardware initialization
2. **m1n1** → Bridge between Apple firmware and Linux
3. **U-Boot** → Standard UEFI environment
4. **GRUB/systemd-boot** → Linux bootloader
5. **Linux Kernel** → Asahi-patched kernel

### Requirements

- Apple Silicon Mac (M1/M2/M3 series)
- macOS 12.3 or later
- Admin access
- 512MB+ USB flash drive
- Command-line familiarity

### Critical Partitioning Warnings

> **DANGER**: Damage to the GPT partition table, first partition (iBootSystemContainer), or the last partition (RecoveryOSContainer) could result in the loss of all data and render the Mac unbootable.

The installation:

- Resizes existing macOS partition (requires 20GB+ free space)
- Adds UEFI environment stub partition
- Creates Linux root partition
- **Prohibits automated partitioning tools**

Manual partitioning example:

```bash
sgdisk /dev/nvme0n1 -n 0:0 -s
mkfs.ext4 -L nixos /dev/nvme0n1p5
```

### NixOS Configuration

Required settings for Apple Silicon:

```nix
{
  imports = [ ./apple-silicon-support ];

  # CRITICAL: Apple Silicon cannot modify EFI variables
  boot.loader.efi.canTouchEfiVariables = false;

  # Peripheral firmware from EFI partition
  hardware.asahi.peripheralFirmwareDirectory = /boot/asahi;
}
```

## Keystone Compatibility Analysis

### What Works

| Feature | Status | Notes |
|---------|--------|-------|
| Basic NixOS | ✅ Works | Standard NixOS operations |
| Home-manager | ✅ Works | Terminal/desktop modules |
| LUKS Encryption | ✅ Works | With specific configuration |
| Hyprland | ⚠️ Partial | GPU support improving |
| Systemd-boot | ✅ Works | Must set `canTouchEfiVariables = false` |

### What Doesn't Work / Limitations

| Feature | Status | Notes |
|---------|--------|-------|
| ZFS | ❌ Untested | No documentation exists |
| Native ZFS Encryption | ❌ Unknown | Keystone's credstore pattern untested |
| TPM2 | ❌ Not Available | Apple Silicon has no TPM |
| Secure Boot (Lanzaboote) | ❌ Not Compatible | Apple uses different security model |
| UEFI Variable Access | ❌ Blocked | `canTouchEfiVariables = false` required |

### Apple Silicon Security Model vs Keystone

Apple Silicon uses a fundamentally different security architecture:

| Aspect | Apple Silicon | Keystone (x86) |
|--------|---------------|----------------|
| Boot Security | Secure Enclave + iBoot | TPM2 + Secure Boot |
| Key Storage | Secure Enclave | TPM2 PCR binding |
| Boot Attestation | Apple proprietary | TPM2 PCR measurements |
| Disk Unlock | FileVault (macOS only) | LUKS + TPM2 auto-unlock |

**Key Insight**: Apple's Secure Enclave is not accessible from Linux, so Keystone's TPM-based automatic disk unlock cannot work. Users must enter a password on every boot.

## LUKS Encryption on Apple Silicon

LUKS encryption IS supported, but with manual password entry:

```nix
# hardware-configuration.nix
boot.initrd.luks.devices = {
  crypted = {
    device = "/dev/disk/by-uuid/YOUR-LUKS-UUID";
    preLVM = true;
  };
};
```

Installation steps:

```bash
# Create LUKS container (use LUKS2 with Argon2id)
cryptsetup luksFormat /dev/nvme0n1p5
cryptsetup open /dev/nvme0n1p5 crypted

# Create filesystem on encrypted volume
mkfs.ext4 /dev/mapper/crypted
```

## ZFS Feasibility

### Unknown Status

No documentation exists for ZFS on Apple Silicon NixOS. Potential issues:

1. **Kernel Compatibility**: Asahi kernel patches may conflict with ZFS module
2. **aarch64 Support**: ZFS supports aarch64, but untested on Apple hardware
3. **Boot Complexity**: ZFS-on-LUKS adds boot chain complexity
4. **No Native Encryption Auto-Unlock**: Without TPM, ZFS encryption keys must be entered manually

### Recommended Investigation

If pursuing ZFS on Apple Silicon:

1. Test basic ZFS pool creation on ext4 root
2. Test ZFS native encryption (manual key entry)
3. Test ZFS-on-LUKS configuration
4. Evaluate boot time and reliability

## Recommendations for Keystone

### Recommended: Separate `operating-system-mac` Module

Create a new NixOS module output specifically for Apple Silicon Macs. This approach:

- Avoids polluting the x86 module with conditionals
- Makes platform limitations explicit (no TPM/Secure Boot options exist)
- Shares common code via a base module
- Uses clear naming: `operating-system-mac`

```nix
# User's flake.nix for Apple Silicon Mac
{
  inputs.keystone.url = "github:ncrmro/keystone";

  outputs = { keystone, ... }: {
    nixosConfigurations.macbook = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        keystone.nixosModules.operating-system-mac
        {
          keystone.os = {
            enable = true;
            storage = {
              type = "ext4";  # ZFS untested, ext4 recommended initially
              devices = [ "/dev/disk/by-id/nvme-APPLE_SSD_..." ];
            };
            # LUKS encryption with manual password (no TPM auto-unlock)
            users.alice = {
              fullName = "Alice";
              email = "alice@example.com";
              terminal.enable = true;
            };
          };
        }
      ];
    };
  };
}
```

### Alternative: Home-Manager Only

For users who want Keystone's dev environment without managing the full OS:

```nix
{
  imports = [
    keystone.homeModules.terminal
    keystone.homeModules.desktop  # If Hyprland works
  ];

  keystone.terminal.enable = true;
}
```

This provides the development environment without attempting unsupported security features.

### Future Milestones

The Apple Silicon Linux ecosystem is rapidly evolving. Key milestones to watch:

- [ ] ZFS confirmed working on Asahi kernel
- [ ] Stable GPU drivers for Hyprland
- [ ] Secure Enclave Linux interface (unlikely)

## Architecture Considerations

### Proposed Module Structure

Refactor `modules/os/` to share common code between platforms:

```
modules/os/
├── base/                    # Shared across platforms
│   ├── default.nix          # Imports all base modules
│   ├── users.nix            # User management (platform-agnostic)
│   ├── services.nix         # Avahi, firewall, resolved
│   └── nix.nix              # Flakes, GC settings
├── x86/                     # x86_64-linux specific (current functionality)
│   ├── default.nix
│   ├── storage.nix          # ZFS + LUKS credstore pattern
│   ├── secure-boot.nix      # Lanzaboote
│   ├── tpm.nix              # TPM enrollment
│   └── remote-unlock.nix    # Initrd SSH with TPM fallback
└── mac/                     # Apple Silicon specific
    ├── default.nix
    ├── storage.nix          # ext4 + LUKS (simpler, no credstore)
    ├── apple-silicon.nix    # Hardware quirks, firmware, asahi support
    └── remote-unlock.nix    # Initrd SSH (if feasible)
```

### Flake Outputs

```nix
# flake.nix
nixosModules = {
  # Current x86_64 module (unchanged API)
  operating-system = {
    imports = [
      ./modules/os/base
      ./modules/os/x86
      disko.nixosModules.disko
      lanzaboote.nixosModules.lanzaboote
    ];
  };

  # New Apple Silicon module
  operating-system-mac = {
    imports = [
      ./modules/os/base
      ./modules/os/mac
      disko.nixosModules.disko
      # No lanzaboote - uses systemd-boot directly
    ];
  };
};

# aarch64-linux support
packages.aarch64-linux = { ... };
devShells.aarch64-linux = { ... };
```

### Option Differences

| Option | `operating-system` (x86) | `operating-system-mac` |
|--------|--------------------------|------------------------|
| `keystone.os.storage.type` | `zfs` / `ext4` | `ext4` (initially) |
| `keystone.os.secureBoot` | ✅ Available | ❌ Not present |
| `keystone.os.tpm` | ✅ Available | ❌ Not present |
| `keystone.os.remoteUnlock` | ✅ Available | ⚠️ TBD |
| `keystone.os.users` | ✅ Shared | ✅ Shared |
| `keystone.os.services` | ✅ Shared | ✅ Shared |

## Sources

- [nixos-apple-silicon UEFI Standalone Guide](https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md)
- [NixOS on Apple Silicon with LUKS](https://gist.github.com/itsnebulalol/8a74bb613fc150f73969d1f861b999dc)
- [Asahi Linux Fedora](https://asahilinux.org/fedora/) - Hardware feature status
- [NixOS Wiki: Full Disk Encryption](https://nixos.wiki/wiki/Full_Disk_Encryption)

## Conclusion

Running Keystone on Apple Silicon is **partially feasible** with significant limitations:

| Keystone Feature | Apple Silicon Support |
|-----------------|----------------------|
| Terminal Dev Environment | ✅ Full support |
| Desktop (Hyprland) | ⚠️ Partial (GPU maturing) |
| LUKS Encryption | ✅ With manual password |
| ZFS Storage | ❓ Untested |
| TPM Auto-Unlock | ❌ Not possible |
| Secure Boot | ❌ Not compatible |
| Remote Unlock (initrd SSH) | ⚠️ May work |

### Recommended Approach

1. Create `keystone.nixosModules.operating-system-mac` as a separate module output
2. Refactor common code into `modules/os/base/` (users, services, nix settings)
3. Start with ext4 + LUKS storage (ZFS can be added later once tested)
4. Omit TPM and Secure Boot options entirely from the Mac module
5. Add `nixos-apple-silicon` as a flake input for hardware support
