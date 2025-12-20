# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Keystone is a NixOS-based self-sovereign infrastructure platform that enables users to deploy secure, encrypted infrastructure on any hardware. It provides two primary configuration types: **Servers** (always-on infrastructure services) and **Clients** (interactive desktop workstations).

## Core Architecture

### Module System
The project is organized around NixOS modules that can be composed together:

- **`modules/os/`** - Consolidated OS module (storage, secure boot, TPM, remote unlock, users)
- **`modules/server/`** - Always-on infrastructure (auto-imports OS module)
- **`modules/client/`** - Interactive workstations with Hyprland desktop (auto-imports OS module)
- **`modules/iso-installer.nix`** - Bootable installer configuration

The `modules/os/` module provides a unified `keystone.os.*` options interface:
- `keystone.os.storage` - ZFS/ext4 with encryption, multi-disk support (mirror, raidz1/2/3)
- `keystone.os.secureBoot` - Lanzaboote Secure Boot configuration
- `keystone.os.tpm` - TPM-based automatic disk unlock
- `keystone.os.remoteUnlock` - SSH in initrd for remote disk unlocking
- `keystone.os.users` - User management with ZFS home directories

### Security Model
All configurations use a layered security approach:
- **TPM2** for hardware-based key storage and boot attestation
- **LUKS** encryption for all storage devices with TPM2 automatic unlock
- **ZFS native encryption** using credstore pattern for key management
- **Secure Boot** with custom key enrollment and lanzaboote
- **SystemD initrd** with complex service orchestration for secure boot process

The disko module implements a sophisticated boot process:
1. Pool import → Credstore unlock → Key loading → Filesystem mounting
2. TPM2 PCR measurements for boot state verification
3. Automatic fallback to password unlock if TPM fails

### Client Desktop Stack
The client module provides a complete Hyprland desktop:
- **Hyprland** compositor with UWSM (Universal Wayland Session Manager)
- **PipeWire** audio with ALSA/Pulse/Jack compatibility
- **greetd** login manager with tuigreet
- **NetworkManager** with Bluetooth support
- Modular desktop components in `modules/client/desktop/` and `modules/client/services/`

## Common Development Commands

### Fast VM Testing with bin/build-vm (Recommended for Config Testing)

The `bin/build-vm` script provides the **fastest way** to test desktop and terminal configurations using `nixos-rebuild build-vm`. It automatically builds and connects you to the VM:

```bash
# Terminal development environment - auto-SSH into VM
./bin/build-vm terminal             # Build and auto-connect via SSH
./bin/build-vm terminal --clean     # Clean old artifacts first

# Hyprland desktop - open graphical console
./bin/build-vm desktop              # Build and open console
./bin/build-vm desktop --clean      # Clean old artifacts first

# Build only, don't connect
./bin/build-vm terminal --build-only
```

**Key Features**:
- **Automatic connection** - Terminal: auto-SSH, Desktop: graphical console
- **Fast iteration** - Mounts host Nix store via 9P (no copying, faster builds)
- **Persistent disk** - Creates `build-vm-{terminal,desktop}.qcow2` for persistent state
- **No encryption/secure boot overhead** - Focus on config testing, not security features
- **Simple credentials** - User: `testuser/testpass`, Root: `root/root`

**How it works**:
- **Terminal VM**: Starts VM in background, waits for SSH to be ready, then automatically connects you
  - Exit SSH with `exit` or Ctrl-D (VM keeps running in background)
  - Reconnect: `ssh -p 2222 testuser@localhost`
  - Stop VM: `kill $(cat build-vm-terminal.pid)`
- **Desktop VM**: Opens QEMU window with Hyprland desktop
  - Stop with `poweroff` inside VM or Ctrl-C

**When to use build-vm vs test-deployment**:
- Use `build-vm` for: Testing desktop configs, terminal dev environment, home-manager modules, fast iteration
- Use `test-deployment` for: Full stack testing (ZFS encryption, secure boot, TPM, initrd SSH unlock)

**VM Details**:
- The VM script is at `./result/bin/run-build-vm-{terminal,desktop}-vm`
- Persistent disk at `./build-vm-{terminal,desktop}.qcow2`
- Disk survives reboots but can be deleted with `--clean`
- VMs use QEMU directly (no libvirt)
- Terminal VM: SSH forwarded to `localhost:2222`

**Configurations**:
- `terminal`: Minimal NixOS with terminal dev environment (Helix, Zsh, Zellij, Ghostty, Git)
- `desktop`: Full Hyprland desktop + terminal dev environment (Firefox, VSCode, VLC, Waybar, etc.)

### Full Stack VM Testing with bin/virtual-machine

The `bin/virtual-machine` script is the **primary driver** for creating and managing libvirt VMs for full-stack Keystone testing:

```bash
# Create a new VM with default settings (uses vms/keystone-installer.iso if available)
./bin/virtual-machine --name keystone-test-vm --start

# Create VM with custom ISO
./bin/virtual-machine --name my-vm --iso /path/to/custom.iso --start

# Create VM with custom resources
./bin/virtual-machine --name large-vm --memory 8192 --vcpus 4 --disk-size 50 --start

# Post-installation: snapshot disk, remove ISO, and reboot (after VM shutdown)
./bin/virtual-machine --post-install-reboot keystone-test-vm

# Completely delete VM and all associated files
./bin/virtual-machine --reset keystone-test-vm
```

**Key Features**:
- **UEFI Secure Boot Setup Mode** - VMs boot with Secure Boot enabled but no pre-enrolled keys
- Automatic OVMF firmware detection (uses NixOS QEMU package)
- Integrates with `keystone-net` network (static IP: 192.168.100.99)
- Serial console + SPICE graphical display
- TPM 2.0 emulation for testing TPM-based features
- Post-installation workflows (snapshot, ISO detachment)

**Secure Boot Setup Mode**:

VMs are automatically created in **Setup Mode**, which means:
- Secure Boot firmware is enabled
- No Platform Key (PK) is enrolled
- Allows unsigned code to run (including the Keystone installer)
- Enables testing of custom Secure Boot key enrollment

To verify Setup Mode inside the VM:
```bash
bootctl status
# Expected output:
#   Secure Boot: disabled (setup)
#   Setup Mode: setup
```

To reset a VM back to Setup Mode:
```bash
# Shut down the VM first
virsh shutdown keystone-test-vm

# Reset NVRAM to setup mode
./bin/virtual-machine --reset-setup-mode keystone-test-vm

# Start VM again
virsh start keystone-test-vm
```

**Connection Methods**:
```bash
# Graphical display (after starting VM)
remote-viewer $(virsh domdisplay keystone-test-vm)

# Serial console
virsh console keystone-test-vm

# SSH (after NixOS installation) - ALWAYS use this script for VM SSH
./bin/test-vm-ssh

# The test-vm-ssh script:
# - Connects to keystone-test-vm at 192.168.100.99
# - Uses isolated known_hosts to avoid polluting user's SSH configuration
# - Filters out SSH warnings to keep agent context clean
# - Checks VM is running before attempting connection
# - Supports passing commands: ./bin/test-vm-ssh "systemctl status"
```

See bin/virtual-machine:1 and docs/examples/vm-secureboot-testing.md for complete details.

### Building ISOs
```bash
# Build installer ISO without SSH keys
./bin/build-iso

# Build with SSH key from file
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# Build with SSH key string directly
./bin/build-iso --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG... user@host"

# Direct Nix build (no SSH keys)
nix build .#iso
```

### Using Modules in External Flakes

**Server with single disk:**
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    keystone.url = "github:ncrmro/keystone";
    disko.url = "github:nix-community/disko";
    lanzaboote.url = "github:nix-community/lanzaboote/v0.4.2";
  };

  outputs = { nixpkgs, keystone, disko, lanzaboote, ... }: {
    nixosConfigurations.myserver = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        lanzaboote.nixosModules.lanzaboote
        keystone.nixosModules.server  # Auto-imports OS module
        {
          networking.hostId = "deadbeef";  # Required for ZFS

          keystone.os = {
            enable = true;
            storage = {
              type = "zfs";
              devices = [ "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB" ];
              swap.size = "16G";
            };
            remoteUnlock = {
              enable = true;
              authorizedKeys = [ "ssh-ed25519 AAAAC3... admin@workstation" ];
            };
            users.admin = {
              fullName = "Server Admin";
              email = "admin@example.com";
              extraGroups = [ "wheel" ];
              authorizedKeys = [ "ssh-ed25519 AAAAC3... admin@workstation" ];
              hashedPassword = "$6$...";  # mkpasswd -m sha-512
              terminal.enable = true;
            };
          };
        }
      ];
    };
  };
}
```

**Server with mirrored disks:**
```nix
keystone.os = {
  enable = true;
  storage = {
    type = "zfs";
    devices = [
      "/dev/disk/by-id/nvme-disk1"
      "/dev/disk/by-id/nvme-disk2"
    ];
    mode = "mirror";  # RAID1
  };
  # ...
};
```

**Desktop with Hyprland:**
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    keystone.url = "github:ncrmro/keystone";
    disko.url = "github:nix-community/disko";
    lanzaboote.url = "github:nix-community/lanzaboote/v0.4.2";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
  };

  outputs = { nixpkgs, keystone, disko, lanzaboote, home-manager, ... }: {
    nixosConfigurations.workstation = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        lanzaboote.nixosModules.lanzaboote
        home-manager.nixosModules.home-manager
        keystone.nixosModules.client  # Auto-imports OS module
        {
          networking.hostId = "deadbeef";

          keystone.os = {
            enable = true;
            storage = {
              type = "zfs";
              devices = [ "/dev/disk/by-id/nvme-WD_BLACK_SN850X_2TB" ];
              swap.size = "32G";
            };
            users.alice = {
              fullName = "Alice Smith";
              email = "alice@example.com";
              extraGroups = [ "wheel" "networkmanager" ];
              initialPassword = "changeme";
              terminal.enable = true;
              desktop = {
                enable = true;
                hyprland.modifierKey = "SUPER";
              };
              zfs.quota = "500G";
            };
          };
        }
      ];
    };
  };
}
```

### Installation Process
```bash
# 1. Boot target machine from Keystone ISO
# 2. Get IP address from installer
ip addr show

# 3. Deploy from development machine
nixos-anywhere --flake .#your-config root@<installer-ip>
```

## Key Implementation Details

### OS Module Structure
```
modules/os/
├── default.nix           # Main orchestrator with keystone.os.* options
├── storage.nix           # ZFS/ext4 + LUKS credstore
├── secure-boot.nix       # Lanzaboote configuration
├── tpm.nix               # TPM enrollment commands
├── remote-unlock.nix     # Initrd SSH
├── users.nix             # User management + ZFS homes
└── scripts/              # Enrollment and provisioning scripts
```

### Storage Configuration
- Always uses "rpool" as the ZFS pool name
- Supports multiple disks with modes: single, mirror, stripe, raidz1/2/3
- Credstore pattern: LUKS volume stores ZFS encryption keys
- Optional ext4 with LUKS for simpler setups (no snapshots/compression)
- Configurable partition sizes: ESP, swap, credstore

### Security Features
- `tpm2-measure-pcr=yes` in LUKS configuration ensures TPM state integrity
- SystemD credentials system securely provides keys to services
- Encryption root validation prevents mounting fraudulent filesystems
- Boot process includes cleanup and error handling with proper service dependencies

### Client Module Structure
```
modules/client/
├── default.nix              # Main orchestration
├── desktop/
│   ├── hyprland.nix         # Wayland compositor
│   ├── audio.nix            # PipeWire audio
│   ├── greetd.nix           # Login manager
│   └── packages.nix         # Essential packages
└── services/
    ├── networking.nix       # NetworkManager, Bluetooth
    └── system.nix           # System services
```

Each component can be individually enabled/disabled through the configuration interface.

## Deployment Patterns

### Pattern 1: Home Server + Laptop
- Server: Raspberry Pi/NUC with router + storage services
- Client: Laptop with Hyprland desktop
- Use case: Home user with network-wide ad blocking and secure remote access

### Pattern 2: VPS + Workstation
- Server: Cloud VPS providing VPN and backup services  
- Client: High-performance desktop workstation
- Use case: Remote work with reliable external access

### Pattern 3: Complete Home Lab
- Multiple servers for different services and redundancy
- Multiple client devices for family/team use
- Use case: Extensive home infrastructure needs

## Important Notes

- The pool name is hardcoded to "rpool" throughout the OS module
- Server and client modules auto-import the OS module - no need to import separately
- Disko and lanzaboote must still be imported at the flake level
- TPM2 integration requires compatible hardware and UEFI firmware setup
- Secure Boot requires manual key enrollment during installation process
- All ZFS datasets use native encryption with automatic key management
- Home-manager integration is optional and only configured when imported

## Submodule Usage in nixos-config

When keystone is used as a git submodule in another flake (like nixos-config):

### Flake Input Configuration
```nix
keystone = {
  url = "git+file:./.submodules/keystone?submodules=1";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### Local Development
Use `./bin/dev-keystone <hostname>` to rebuild with local keystone changes without requiring commits:
```bash
./bin/dev-keystone        # Uses current hostname
./bin/dev-keystone mox    # Specific host
```

### Available Home-Manager Modules
- `inputs.keystone.homeModules.terminal` - Terminal dev environment
- `inputs.keystone.homeModules.desktop` - Full Hyprland desktop

### Key Options
- `keystone.terminal.enable` - Enable terminal tools (zsh, starship, zellij, helix)
- `keystone.terminal.git.userName` / `userEmail` - Required git config
- `keystone.desktop.enable` - Enable desktop environment
- `keystone.desktop.hyprland.enable` - Enable Hyprland config
- `keystone.desktop.hyprland.modifierKey` - Primary modifier (default: ALT)
- `keystone.desktop.hyprland.capslockAsControl` - Remap caps to ctrl (default: true)
