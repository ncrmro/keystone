# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Keystone is a NixOS-based self-sovereign infrastructure platform that enables users to deploy secure, encrypted infrastructure on any hardware.

## Core Architecture

### Module System
The project is organized around NixOS modules that can be composed together:

- **`modules/os/`** - Core operating system module (storage, secure boot, TPM, remote unlock, users, services)
- **`modules/keystone/desktop/`** - Hyprland desktop environment (audio, greetd login)
- **`modules/iso-installer.nix`** - Bootable installer configuration

The `modules/os/` module provides a unified `keystone.os.*` options interface:
- `keystone.os.storage` - ZFS/ext4 with encryption, multi-disk support (mirror, raidz1/2/3)
- `keystone.os.secureBoot` - Lanzaboote Secure Boot configuration
- `keystone.os.tpm` - TPM-based automatic disk unlock
- `keystone.os.remoteUnlock` - SSH in initrd for remote disk unlocking
- `keystone.os.users` - User management with ZFS home directories
- `keystone.os.services` - Avahi/mDNS, firewall, systemd-resolved
- `keystone.os.nix` - Flakes, garbage collection settings

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

### Desktop Stack
The desktop module provides a complete Hyprland environment:
- **Hyprland** compositor with UWSM (Universal Wayland Session Manager)
- **PipeWire** audio with ALSA/Pulse/Jack compatibility
- **greetd** login manager with tuigreet
- **NetworkManager** with Bluetooth support
- Modular desktop components in `modules/keystone/desktop/`

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

### MicroVM Testing

For lightweight and reproducible testing of specific NixOS module configurations (e.g., TPM, networking, specific services), we utilize `microvm.nix`. This setup allows for faster iteration and integrates well with the Nix build system.

**Key Features**:
-   **Lightweight & Fast**: Quick feedback loop for testing.
-   **Reproducible**: Environment is fully defined in Nix.
-   **Flexible**: Supports various configurations, including hardware emulation (e.g., TPM with `swtpm`).

**Integration Overview**:
1.  `microvm.nix` is added as an input in `tests/flake.nix`.
2.  Dedicated MicroVM configurations are defined in `tests/microvm/` (e.g., `tpm-test.nix` for TPM emulation). These configurations build a NixOS guest system tailored for specific test scenarios, enabling necessary modules and services.
3.  Test runner scripts in `bin/` (e.g., `bin/test-microvm-tpm`) manage the lifecycle of the MicroVM, including any necessary host-side services (like `swtpm` for TPM emulation) and post-boot verification.

**How to Run a MicroVM Test**:

To execute a MicroVM test, use the corresponding script in `bin/` within a development shell:

```bash
# Example: Run the TPM MicroVM test
nix develop --command bin/test-microvm-tpm
```

The test script will handle building the MicroVM runner, starting any required host services, launching the MicroVM, and performing checks inside the guest before cleaning up.

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

### VM Screenshot Debugging (libvirt VMs only)

Use `bin/screenshot` to capture a libvirt VM's graphical display for debugging boot issues:

```bash
# Screenshot keystone-test-vm (default)
./bin/screenshot                           # -> screenshots/vm-screenshot-*.png

# Screenshot specific domain
./bin/screenshot keystone-test-vm

# Screenshot with custom output path
./bin/screenshot keystone-test-vm debug.png
```

The script outputs the relative path to the PNG file (e.g., `screenshots/vm-screenshot-20251222-010214.png`), which can be read directly with the Read tool for visual inspection. Useful for debugging:
- UEFI boot failures ("Access Denied", "No bootable device")
- Secure Boot issues
- Disk unlock prompts in initrd
- Any state where SSH is not available

### Building ISOs
```bash
# Build installer ISO without SSH keys
make build-iso

# Build with SSH key from file
make build-iso-ssh

# Or use the script directly
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
```

### Make Targets Reference

Run `make help` to see all available targets. Key targets:

**ISO Building:**
- `make build-iso` - Build installer ISO
- `make build-iso-ssh` - Build ISO with your SSH key

**Fast Config Testing (no encryption/TPM):**
- `make build-vm-terminal` - Build and SSH into terminal dev VM
- `make build-vm-desktop` - Build and open desktop VM with Hyprland

**Libvirt VM Management (full TPM + Secure Boot):**
- `make vm-create` - Create and start VM with TPM
- `make vm-start` - Start existing VM
- `make vm-stop` - Stop VM gracefully
- `make vm-destroy` - Force stop VM
- `make vm-reset` - Delete VM and all artifacts
- `make vm-ssh` - SSH into test VM
- `make vm-console` - Serial console access
- `make vm-display` - Open graphical display
- `make vm-status` - Show VM status
- `make vm-post-install` - Post-install workflow (remove ISO, snapshot, reboot)
- `make vm-reset-secureboot` - Reset to Secure Boot setup mode

**Testing:**
- `make test` - Run all tests
- `make test-checks` - Fast flake validation
- `make test-module` - Module isolation tests
- `make test-integration` - Integration tests
- `make test-deploy` - Full stack deployment test
- `make test-desktop` - Hyprland desktop test
- `make test-hm` - Home-manager module test
- `make test-template` - Validate flake template

**CI:**
- `make ci` - Run CI checks (format + lockfile)
- `make fmt` - Format Nix files

**Custom VM name:** Use `VM_NAME=my-vm make vm-ssh` to target a different VM.

### Flake Template (Recommended for New Users)

The easiest way to start using Keystone is with the flake template:

```bash
# Initialize a new project
nix flake init -t github:ncrmro/keystone

# Edit configuration.nix - search for TODO: to find required changes
grep -n "TODO:" configuration.nix

# Generate hostId and find disk ID
head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
ls -la /dev/disk/by-id/

# Deploy to target machine
nixos-anywhere --flake .#my-machine root@<installer-ip>
```

The template includes:
- `flake.nix` - All required inputs with operating-system module (desktop optional)
- `configuration.nix` - Documented `keystone.os.*` options with TODO markers
- `hardware.nix` - Hardware configuration placeholder
- `README.md` - Quick start guide

### Using Modules in External Flakes

**Headless server:**
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    keystone.url = "github:ncrmro/keystone";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
  };

  outputs = { nixpkgs, keystone, home-manager, ... }: {
    nixosConfigurations.myserver = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        home-manager.nixosModules.home-manager
        keystone.nixosModules.operating-system  # Includes disko + lanzaboote
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

**Mirrored disks:**
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
    home-manager.url = "github:nix-community/home-manager/release-25.05";
  };

  outputs = { nixpkgs, keystone, home-manager, ... }: {
    nixosConfigurations.workstation = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        home-manager.nixosModules.home-manager
        keystone.nixosModules.operating-system  # Includes disko + lanzaboote
        keystone.nixosModules.desktop            # Hyprland desktop
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

**With Agent Sandbox (development workstation):**
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    keystone.url = "github:ncrmro/keystone";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
  };

  outputs = { nixpkgs, keystone, home-manager, ... }: {
    nixosConfigurations.devbox = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        home-manager.nixosModules.home-manager
        keystone.nixosModules.operating-system  # Core OS
        keystone.nixosModules.desktop            # Hyprland desktop
        keystone.nixosModules.agent              # Agent sandbox
        {
          networking.hostId = "deadbeef";

          keystone.os = {
            enable = true;
            storage = {
              type = "zfs";
              devices = [ "/dev/disk/by-id/nvme-WD_BLACK_SN850X_2TB" ];
              swap.size = "32G";
            };
            users.dev = {
              fullName = "Dev User";
              email = "dev@example.com";
              extraGroups = [ "wheel" "networkmanager" "kvm" ];
              initialPassword = "changeme";
              terminal.enable = true;
              desktop.enable = true;
            };
          };

          # Enable agent sandbox for isolated AI coding
          keystone.agent = {
            enable = true;
            sandbox = {
              memory = 16384;  # 16GB for development
              vcpus = 8;
              nestedVirtualization = true;  # For testing VMs inside sandbox
            };
            proxy.enable = true;  # Access dev servers at *.sandbox.local
            guest.agents.claudeCode.enable = true;
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

### Desktop Module Structure
```
modules/keystone/desktop/
├── nixos.nix                # NixOS desktop configuration
└── home/
    └── default.nix          # Home-manager Hyprland config
```

### Agent Sandbox Module Structure
```
modules/keystone/agent/
├── default.nix              # Main orchestrator with keystone.agent.* options
├── backends/
│   ├── default.nix          # Backend abstraction layer
│   ├── microvm.nix          # MicroVM backend implementation
│   └── kubernetes.nix       # Kubernetes backend (stub)
├── guest/
│   ├── default.nix          # Guest OS base configuration
│   ├── agents.nix           # AI agent packages (Claude Code, etc.)
│   ├── tools.nix            # Development tools (git, direnv, etc.)
│   ├── zellij.nix           # Session management
│   └── worktree.nix         # Git worktree support
├── sync.nix                 # Host-initiated git sync
└── proxy.nix                # Dev server proxy (*.sandbox.local)

packages/keystone-agent/     # CLI package (Python)
tests/microvm/agent-sandbox.nix  # MicroVM test configuration
```

### Agent Sandbox Features
- **Isolated Execution**: MicroVM sandbox with 9p filesystem sharing (workspace only)
- **SSH Access**: Key-based authentication with password fallback
- **Secure Sync**: Host-initiated git fetch/merge (VM cannot access host SSH keys)
- **direnv Integration**: Auto-loads `.envrc` in `/workspace` directory
- **Nested Virtualization**: Optional KVM passthrough for infrastructure testing
- **Persistent State**: Sandbox state preserved between sessions (use `--fresh` to reset)

CLI Commands (via `nix run .#keystone-agent -- <command>` or after `nix build`):
- `keystone-agent start` - Launch sandbox for current project (auto-attaches)
- `keystone-agent stop` - Stop sandbox gracefully
- `keystone-agent attach` / `ssh` - SSH into sandbox (starts in /workspace)
- `keystone-agent exec -- <cmd>` - Run command in sandbox
- `keystone-agent sync` - Fetch committed changes from sandbox to host
- `keystone-agent status` - Show sandbox status and resources
- `keystone-agent list` - List all sandboxes
- `keystone-agent destroy <name>` - Remove sandbox completely

Quick Start:
```bash
# Build the CLI
nix build .#keystone-agent

# Start sandbox for current project
result/bin/keystone-agent start

# Work in sandbox (SSH session opens automatically)
# Exit with Ctrl-D or 'exit'

# Sync changes back to host
result/bin/keystone-agent sync

# Stop when done
result/bin/keystone-agent stop
```

Documentation:
- `packages/keystone-agent/README.md` - Quick CLI reference
- `docs/agent-sandbox.md` - Full user guide
- `docs/agent-microvms.md` - Architecture deep dive
- `specs/012-agent-sandbox/` - Implementation specification

## Deployment Patterns

### Pattern 1: Home Server + Desktop
- Headless: Use `operating-system` module for always-on infrastructure
- Desktop: Add `desktop` module for workstations with Hyprland

### Pattern 2: VPS + Workstation
- VPS: `operating-system` with `remoteUnlock` for headless operation
- Workstation: `operating-system` + `desktop` for local development

### Pattern 3: Multi-Machine Setup
- Mix headless and desktop configurations as needed
- All share the same `keystone.os.*` options for consistent security

## Important Notes

- The pool name is hardcoded to "rpool" throughout the OS module
- The `operating-system` module includes disko and lanzaboote - no separate import needed
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
- `inputs.keystone.homeModules.agentTui` - Agent sandbox TUI client (optional)

### Available NixOS Modules
- `inputs.keystone.nixosModules.operating-system` - Core OS (storage, secure boot, TPM)
- `inputs.keystone.nixosModules.desktop` - Hyprland desktop environment
- `inputs.keystone.nixosModules.agent` - Agent sandbox system (isolated AI coding environments)
- `inputs.keystone.nixosModules.isoInstaller` - Bootable installer

### Key Options
- `keystone.terminal.enable` - Enable terminal tools (zsh, starship, zellij, helix)
- `keystone.terminal.git.userName` / `userEmail` - Required git config
- `keystone.desktop.enable` - Enable desktop environment
- `keystone.desktop.hyprland.enable` - Enable Hyprland config
- `keystone.desktop.hyprland.modifierKey` - Primary modifier (default: ALT)
- `keystone.desktop.hyprland.capslockAsControl` - Remap caps to ctrl (default: true)
- `keystone.agent.enable` - Enable agent sandbox system
- `keystone.agent.sandbox.*` - Sandbox resource configuration (memory, vcpus, nested virt)
- `keystone.agent.backend.type` - Backend type: microvm (default) or kubernetes
- `keystone.agent.proxy.enable` - Enable dev server proxy to *.sandbox.local

## Recent Changes
- 012-agent-sandbox: Phases 1-3 complete - Agent sandbox is now functional:
  - MicroVM backend with start/stop lifecycle management
  - SSH key-based authentication (falls back to password if no key)
  - Git-based sync command for pulling committed changes back to host
  - direnv auto-load support for `/workspace` directory
  - Persistent sandbox state between sessions
  - SSH sessions start directly in `/workspace` for convenience
