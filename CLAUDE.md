# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Keystone is a NixOS-based self-sovereign infrastructure platform that enables users to deploy secure, encrypted infrastructure on any hardware. It provides two primary configuration types: **Servers** (always-on infrastructure services) and **Clients** (interactive desktop workstations).

## Core Architecture

### Module System
The project is organized around NixOS modules that can be composed together:

- **`modules/server/`** - Always-on infrastructure (VPN, DNS, storage, media)
- **`modules/client/`** - Interactive workstations with Hyprland desktop
- **`modules/disko-single-disk-root/`** - Disk partitioning with ZFS encryption and TPM2
- **`modules/iso-installer.nix`** - Bootable installer configuration

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
```

**SSH Access - ALWAYS use `./bin/test-vm-ssh`**:

**IMPORTANT**: Never use raw `ssh` commands to connect to test VMs. Always use the `./bin/test-vm-ssh` script:

```bash
# Connect to default VM (keystone-test-vm)
./bin/test-vm-ssh

# Connect to specific VM
./bin/test-vm-ssh keystone-tui-test

# Run a command on a VM
./bin/test-vm-ssh keystone-tui-test "systemctl status keystone-installer"

# List available VMs
./bin/test-vm-ssh --list
```

**Why use test-vm-ssh**:
- Uses isolated known_hosts (`/tmp/keystone-test-vm-known-hosts`) - won't pollute `~/.ssh/known_hosts`
- Filters SSH warnings to keep agent context clean
- Checks VM is running before attempting connection
- Handles host key changes automatically (VMs are frequently reset)
- Supports all whitelisted test VMs with correct ports/users

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
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    keystone.url = "github:ncrmro/keystone";
    disko.url = "github:nix-community/disko";
  };

  outputs = { nixpkgs, keystone, disko, ... }: {
    nixosConfigurations.mySystem = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        keystone.nixosModules.diskoSingleDiskRoot
        keystone.nixosModules.client  # or .server
        {
          keystone.disko = {
            enable = true;
            device = "/dev/disk/by-id/your-disk";
            enableEncryptedSwap = true;
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

### Disko Configuration
- Always uses "rpool" as the ZFS pool name (not configurable)
- Credstore pattern: 100MB LUKS volume stores ZFS encryption keys
- SystemD services handle credstore lifecycle in initrd
- Supports optional encrypted swap with random encryption per boot

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

- The pool name is hardcoded to "rpool" throughout the disko module
- TPM2 integration requires compatible hardware and UEFI firmware setup
- Secure Boot requires manual key enrollment during installation process
- All ZFS datasets use native encryption with automatic key management
- Client configurations are NixOS system-level only (no home-manager integration)

## Active Technologies
- TypeScript 5.x (transpiled to JavaScript, Node.js runtime) + React 18.3.1, Ink 5.0.1, ink-text-input 6.0.0, ink-select-input 6.0.0, ink-spinner 5.0.0 (011-tui-local-installer)
- ZFS with LUKS credstore (encrypted path) or plain ext4 (unencrypted path) (011-tui-local-installer)

## Recent Changes
- 011-tui-local-installer: Added TypeScript 5.x (transpiled to JavaScript, Node.js runtime) + React 18.3.1, Ink 5.0.1, ink-text-input 6.0.0, ink-select-input 6.0.0, ink-spinner 5.0.0
