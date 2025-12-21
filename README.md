# Keystone

Keystone enables self-sovereign infrastructure that you fully control, whether running on bare-metal hardware or cloud services. Unlike traditional infrastructure solutions, Keystone is designed for seamless migration between different environments while maintaining security, availability, and shared resource access.

**[📚 Documentation](https://ncrmro.github.io/keystone/)** | **[🗺️ Roadmap](ROADMAP.md)** | **[🚀 Quick Start](#getting-started)**

## Core Principles

**Self-Sovereign Infrastructure**: Your infrastructure belongs to you. All data is encrypted at rest and in transit, with cryptographic keys under your control. Whether running on a Raspberry Pi in your home or a cloud VPS, you maintain full ownership and control.

**Declarative Configuration**: Everything is configured as code and can be managed in version control systems like Git. Define your desired infrastructure state once in configuration files, and Keystone maintains it across different hardware and network environments. This goes beyond traditional disaster recovery—it enables live migration of services between bare-metal and cloud infrastructure as needs change.

**Flexible Resource Sharing**: Share compute and storage resources within trusted groups (family, friends, business partners) while maintaining security boundaries and resource limits.

## Architecture: Servers and Clients

Keystone provides two primary types of infrastructure:

### Servers 🖥️
**Always-on infrastructure that provides services**
- Network gateway, VPN endpoint, DNS server with ad/tracker blocking
- Storage server with redundant disks, backup destination, media server
- **Purpose**: Run 24/7, provide services to clients and external access
- **Hardware**: Raspberry Pi, NUC, dedicated server, or VPS

### Clients

Keystone provides two types of client configurations for different use cases:

#### Workstations 🖥️💻
**Always-on development machines with remote access capabilities**
- Hardwired, battery-backed systems that remain powered on
- Terminal-based development environment (desktop optional)
- **Remote Development Workflow**:
  - SSH into workstation from laptops or other clients
  - Resume Zellij terminal sessions seamlessly across connections
  - Access local development servers via Tailscale/Headscale hostnames
  - Start work from one device, continue from another without interruption
- **Purpose**: Central development hub accessible from anywhere on your network
- **Hardware**: Desktop workstation, mini PC, or any always-on hardware

#### Interactive Clients 💻
**Portable devices for daily computing**
- Laptop or portable device with full desktop environment
- Development tools, user applications, graphical interface
- **Purpose**: Daily work, mobile computing, can SSH into workstations for development
- **Hardware**: Laptop, portable device, or any interactive-use hardware

### How They Work Together
- Clients connect to servers for backups, VPN access, shared storage
- Servers provide always-on services while clients can be powered down
- Interactive clients can SSH into workstations for development, accessing persistent terminal sessions and local dev servers via Tailscale hostnames
- Both use the same security model (TPM, encryption, secure boot attestation)
- All devices automatically encrypt data and maintain cryptographic verification

## Common Deployment Patterns

### Pattern 1: Home Server + Laptop
- **Server**: Raspberry Pi or NUC providing network services and storage
- **Client**: Laptop for daily computing
- **Use Case**: Home user with reliable home internet, wants network-wide ad blocking and secure remote access

### Pattern 2: VPS + Workstation  
- **Server**: Cloud VPS providing VPN and backup services
- **Client**: Desktop workstation with high-performance hardware
- **Use Case**: Remote work, need reliable external access point and backup destination

### Pattern 3: Complete Home Lab
- **Servers**: Multiple servers for different services and redundancy
- **Clients**: Multiple devices for family or team use
- **Use Case**: Family or small team with extensive home infrastructure needs

## Getting Started

### Quick Start with Flake Template (Recommended)

The fastest way to get started is using the Keystone flake template:

```bash
# Initialize a new project from the template
nix flake init -t github:ncrmro/keystone

# Edit configuration.nix - search for TODO: to find required changes
grep -n "TODO:" configuration.nix

# Generate a unique host ID (required for ZFS)
head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '

# Find your disk ID (use /dev/disk/by-id/ paths)
ls -la /dev/disk/by-id/

# Boot target machine from Keystone ISO, then deploy
nixos-anywhere --flake .#my-machine root@<installer-ip>
```

The template includes:
- **flake.nix** - All required inputs with role toggle (server/client)
- **configuration.nix** - Documented options with TODO markers for required values
- **hardware.nix** - Placeholder ready for your hardware config
- **README.md** - Detailed getting started guide

See the template's README.md for post-deployment steps (Secure Boot keys, TPM enrollment).

### Quick Deployment to VM

Deploy a minimal Keystone server to a VM for testing:

```bash
# 1. Build ISO with SSH key
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# 2. Boot VM from ISO and note its IP address

# 3. Configure your deployment in vms/test-server/configuration.nix
#    (see examples/test-server.nix for reference)

# 4. Deploy with automated wrapper
./scripts/deploy-vm.sh test-server <vm-ip> --verify

# OR deploy directly with nixos-anywhere
nixos-anywhere --flake .#test-server root@<vm-ip>

# 5. SSH into deployed server
ssh root@<vm-ip>
ssh root@test-server.local  # via mDNS
```

See `examples/test-server.nix` for a fully documented example configuration.

### Documentation

For comprehensive documentation, visit our **[Documentation Hub](https://ncrmro.github.io/keystone/)**.

Quick links:
- [Installation Guide](docs/installation.md) - Complete installation process from ISO generation to first boot
- [Examples](docs/examples.md) - Server and client deployment examples
- [Roadmap](ROADMAP.md) - Development milestones and future plans

## Development & Testing

### VM Testing Workflow

Test Keystone ISOs quickly using automated VM workflows:

```bash
# Complete automated test (build ISO + launch VM + SSH)
make vm-test

# SSH into the VM
ssh -p 22220 root@localhost

# Stop the VM when done
make vm-stop

# Clean VM artifacts
make vm-clean
```

**Manual workflow** (step-by-step):
```bash
# 1. Build ISO with your SSH key
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# 2. Launch VM
make vm-server

# 3. SSH into VM (wait ~30 seconds for boot)
ssh -p 22220 root@localhost

# 4. Stop VM
make vm-stop
```

**Available VM targets**:
- `make vm-test` - Build ISO and launch VM with automated SSH check
- `make vm-server` - Launch VM manually (requires pre-built ISO)
- `make vm-ssh` - Show SSH connection command
- `make vm-stop` - Stop running VM
- `make vm-clean` - Remove VM artifacts

**Requirements**:
- quickemu: `nix-env -iA nixpkgs.quickemu`
- socat: `nix-env -iA nixpkgs.socat` (for `bin/test-deployment` automated testing)

**Note**: VM configuration is automatically created from `vms/server.conf.example` on first run. The config file is gitignored to prevent committing runtime state changes.

## Available Configurations

### Server Configuration
- Network gateway, VPN server, DNS with ad blocking, firewall management
- Storage server with ZFS, automated backups, media services
- Always-on services for clients and external access

### Client Configuration  
- Desktop environment, development tools, automated backup client
- Interactive computing that connects to server services

### Installer
- **ISO Installer**: Bootable installer for deploying Keystone to new hardware

## Key Features

### Security
- **TPM Integration**: Hardware-based encryption key storage and bootloader attestation
- **Full Disk Encryption**: LUKS encryption on all storage devices
- **Secure Boot**: Verified boot chain with hardware attestation
- **Zero-Knowledge Architecture**: All data encrypted before leaving devices

### Storage & Backups
- **ZFS Everywhere**: Copy-on-write filesystem with snapshots and compression
- **Automated Backups**: Clients automatically backup to designated servers
- **Distributed Storage**: Multiple backup targets across different locations
- **Incremental Snapshots**: Efficient storage using ZFS snapshot capabilities

### Networking
- **WireGuard VPN**: Secure remote access to home network and services
- **DNS Filtering**: Network-wide ad and tracker blocking
- **Secure Networking**: Encrypted communication between all Keystone devices

### Resource Sharing
- **Family/Team Access**: Controlled sharing of compute and storage resources
- **Permission Management**: Fine-grained access control for shared resources
- **Cross-Platform Support**: Windows/Mac clients can connect to Linux servers

## Using Keystone as a Flake Input

### Recommended: Use the Template

The easiest way to set up Keystone is with the flake template (see [Quick Start](#quick-start-with-flake-template-recommended)):

```bash
nix flake init -t github:ncrmro/keystone
```

This creates a complete project with all required inputs and documented configuration options.

### Manual Setup

If you prefer to add Keystone to an existing flake manually:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    keystone.url = "github:ncrmro/keystone";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
  };

  outputs = { nixpkgs, keystone, home-manager, ... }: {
    nixosConfigurations.my-server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        home-manager.nixosModules.home-manager
        keystone.nixosModules.operating-system
        # keystone.nixosModules.desktop  # Add for Hyprland desktop
        {
          networking.hostId = "deadbeef";  # Required for ZFS
          keystone.os = {
            enable = true;
            storage.devices = [ "/dev/disk/by-id/your-disk" ];
            users.admin = {
              fullName = "Admin";
              initialPassword = "changeme";
            };
          };
        }
      ];
    };
  };
}
```

### Available Modules

**NixOS Modules** (`keystone.nixosModules.*`):
- `operating-system` - Core OS (storage, secure boot, TPM, users, SSH, mDNS, firewall)
- `desktop` - Hyprland desktop environment (audio, greetd login)
- `isoInstaller` - Bootable installer configuration

**Home Manager Modules** (`keystone.homeModules.*`):
- `terminal` - Terminal dev environment (Helix, Zsh, Zellij, Git)
- `desktop` - Full Hyprland desktop configuration

### Local Development Workflow

When developing Keystone alongside a consuming flake, use `--override-input` to test local changes without committing:

```bash
# Instead of committing and pushing keystone changes, override the input:
sudo nixos-rebuild switch --flake .#hostname \
  --override-input keystone "path:/path/to/keystone"
```

#### Example: dev-keystone Script

Create a helper script in your consuming flake (e.g., `bin/dev-keystone`):

```bash
#!/usr/bin/env bash
# Rebuild NixOS with local keystone changes without requiring commits
# Usage: ./bin/dev-keystone <hostname>
#        ./bin/dev-keystone              # uses current hostname

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
KEYSTONE_PATH="$REPO_ROOT/.submodules/keystone"  # or wherever keystone is cloned

HOSTNAME="${1:-$(hostname)}"

echo "Rebuilding with local keystone from: $KEYSTONE_PATH"
echo "Target hostname: $HOSTNAME"

sudo nixos-rebuild switch --flake "$REPO_ROOT#$HOSTNAME" \
  --override-input keystone "path:$KEYSTONE_PATH"
```

This allows rapid iteration on Keystone modules without:
- Committing changes to the keystone repo
- Pushing to GitHub
- Running `nix flake update keystone`

Once changes are tested, commit and push keystone, then run `nix flake update keystone` in the consuming flake to lock the new version.
