# PLAN: Keystone TUI Installer

## Overview

The Keystone TUI Installer is a terminal-based installer for NixOS that runs on the Keystone ISO. It provides a guided installation experience with network setup, disk selection, encryption options, and NixOS configuration generation.

## Architecture

```
packages/keystone-installer-ui/
├── src/
│   ├── index.tsx          # Entry point, terminal theming, cleanup handlers
│   ├── App.tsx            # Main component, screen state machine, theme colors
│   ├── types.ts           # TypeScript types, constants (MOUNT_ROOT, DEV_MODE)
│   ├── network.ts         # Network detection, WiFi scanning
│   ├── disk.ts            # Disk detection, formatting, mounting
│   ├── config-generator.ts # Generates flake.nix, host configs, disko configs
│   └── installation.ts    # Orchestrates installation: disko → nixos-install
├── package.json           # npm scripts: build, dev
└── default.nix            # Nix package definition
```

## Current State (Session Progress)

### ✅ Completed Fixes

1. **Royal Green Theme**
   - Redefined Linux VT 16-color palette for consistent theming
   - Dark forest green background: `#0a140f` (RGB: 10, 20, 15)
   - Gold/yellow text colors for readability
   - Works on both modern terminals (OSC 11) and Linux VTs (palette redefinition)

2. **Disko Mountpoint Bug**
   - Fixed: `generateStandaloneDiskConfig()` had `/mnt/boot` and `/mnt` hardcoded
   - Disko expects final mountpoints (`/`, `/boot`) and adds `/mnt` prefix automatically
   - Result was `/mnt/mnt/boot` - now fixed to `/boot`

3. **Missing Module Error**
   - Fixed: Generated flake referenced non-existent `keystone.nixosModules.diskoSingleDiskRoot`
   - Updated to use `keystone.nixosModules.server` or `client` (which include disko)
   - Updated disk-config to use `keystone.os.storage` interface instead of `keystone.disko`

4. **Screen Flashing During Install**
   - Fixed: `runCommandWithCapture()` was writing directly to stdout/stderr
   - This interfered with Ink's rendering causing flashing
   - Now captures output silently, displays via Ink components

### 🔧 Pending / Known Issues

1. **Flakes Not Available** - Added `nix.settings.experimental-features` to iso-installer.nix

2. **Test in VM** - Need to rebuild ISO and verify all fixes work together

## Key Files Modified

| File | Changes |
|------|---------|
| `src/index.tsx` | Linux VT palette redefinition, cleanup handlers |
| `src/App.tsx` | Theme colors (gold/green), FullScreen wrapper |
| `src/config-generator.ts` | Fixed disko mountpoints, updated to keystone.os.storage |
| `src/installation.ts` | Removed direct stdout writes (no more flashing) |
| `modules/iso-installer.nix` | Added flakes experimental feature |

## Generated Configuration Structure

The TUI generates a NixOS flake configuration:

```
/mnt/home/{username}/nixos-config/
├── flake.nix                    # Imports keystone.nixosModules.{server|client}
└── hosts/{hostname}/
    ├── default.nix              # hostname, hostId, user
    ├── disk-config.nix          # keystone.os.storage config
    ├── disko-standalone.nix     # For disko CLI (partitioning)
    └── hardware-configuration.nix
```

### Generated flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    keystone.url = "github:ncrmro/keystone";
  };
  outputs = { nixpkgs, keystone, ... }: {
    nixosConfigurations.{hostname} = nixpkgs.lib.nixosSystem {
      modules = [
        keystone.nixosModules.{server|client}
        ./hosts/{hostname}
      ];
    };
  };
}
```

### Generated disk-config.nix

```nix
# For encrypted ZFS:
keystone.os = {
  enable = true;
  storage = {
    type = "zfs";
    devices = [ "/dev/disk/by-id/..." ];
    swap.size = "8G";
  };
};

# For unencrypted ext4:
keystone.os = {
  enable = true;
  storage = {
    type = "ext4";
    devices = [ "/dev/disk/by-id/..." ];
    swap.size = "8G";
  };
};
```

## Development Workflow

### Local Testing (Fast Iteration)
```bash
cd packages/keystone-installer-ui
npm install
npm run dev
```

### VM Testing (Full Stack)
```bash
# Build ISO with SSH key
make build-iso-ssh

# Reset VM and create fresh from ISO
make vm-reset && make vm-create

# Open graphical display
make vm-display

# SSH into VM (after boot)
make vm-ssh
```

## Theme Colors (Linux VT Palette)

```typescript
const palette = {
  '0': '0a140f',  // Black/BG → dark forest green
  '1': 'cc4444',  // Red → softer red
  '2': '44aa44',  // Green → medium green
  '3': 'd4a017',  // Yellow → gold
  '4': '6699cc',  // Blue → soft sky blue (readable on green)
  '5': 'aa66aa',  // Magenta
  '6': '55aaaa',  // Cyan → teal
  '7': 'dddddd',  // White → light gray
  '8': '1a2f20',  // Bright black → slightly lighter green
  '9': 'ff6666',  // Bright red
  'A': '66cc66',  // Bright green
  'B': 'ffd700',  // Bright yellow → bright gold
  'C': '88bbee',  // Bright blue → lighter blue
  'D': 'cc88cc',  // Bright magenta
  'E': '77cccc',  // Bright cyan
  'F': 'ffffff',  // Bright white
};
```

## Installation Flow

1. **Network Check** → Ethernet detection, optional WiFi setup
2. **Method Selection** → Remote (SSH), Local, or Clone from repo
3. **Disk Selection** → Detect disks, validate size (≥8GB)
4. **Encryption Choice** → ZFS+LUKS or ext4 unencrypted
5. **Host Configuration** → Hostname, username, password, system type
6. **Summary** → Review before install
7. **Installation** → disko → nixos-install → cleanup
8. **Complete** → Reboot option

## Next Steps

1. Verify all fixes work in VM
2. Test both encrypted (ZFS) and unencrypted (ext4) paths
3. Test "clone from repository" workflow
4. Consider adding progress indicators during nixos-install
