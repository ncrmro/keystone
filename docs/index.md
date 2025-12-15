---
layout: default
title: Home
---

# Keystone Documentation

Welcome to the Keystone documentation. Keystone is a NixOS-based self-sovereign infrastructure platform that enables users to deploy secure, encrypted infrastructure on any hardware.

## Core Concepts

<!-- TODO: add screenshots here -->

### Keystone TUI
Keystone TUI is an opinionated set of terminal tools and configuration options. It can replace hombrew on macOS or your OS's native package manager.

### Keystone OS
The immutable, secure operating system based on NixOS. It comes in two primary variants:
- **Server:** Optimized for headless operation, providing robust services, networking, and storage capabilities.
- **Desktop:** A feature-rich Graphical User Interface (GUI) environment tailored for **laptops** and workstations, offering a consistent and secure user experience.
- Comes installed with the Keystone TUI.

### Keystone HA
A distributed computing layer that ensures **High Availability** and resilience. It enables your services to remain operational even if individual nodes fail. Additionally
it allows clusters to share resources between super entities. Eg family, friends or other orginizations an enterprises.

## Quick Links

- **[Project Roadmap](https://github.com/ncrmro/keystone/blob/main/ROADMAP.md)** - Development milestones and future plans
- **[GitHub Repository](https://github.com/ncrmro/keystone)** - Source code and issue tracking
- **[Quick Start](#quick-start)** - Get up and running quickly

## Documentation Overview

### Getting Started

#### Installation & Deployment
- **[Installation Guide](installation.md)** - Complete installation process from ISO generation to first boot
- **[ISO Generation](iso-generation.md)** - Building custom installation media
- **[Examples](examples.md)** - Server and client deployment examples
- **[VM Testing](testing-vm.md)** - Virtual machine testing workflows
- **[Testing Procedures](testing-procedure.md)** - Comprehensive testing guide

#### Security & Encryption
- **[TPM Enrollment](tpm-enrollment.md)** - TPM2-based disk encryption setup
- **[Secure Boot Testing](examples/vm-secureboot-testing.md)** - Secure Boot configuration and testing
- **[User Management](users.md)** - User configuration and access control

### Module Documentation
- **[Terminal Development Environment](modules/terminal-dev-environment.md)** - Helix, Zsh, Zellij, and Ghostty setup

### Advanced Topics
- **[Build Platforms](build-platforms.md)** - Cross-platform build configuration
- **[Hardware NAS](HW_NAS.md)** - Network Attached Storage setup

## Quick Start

### 1. Build Installation ISO

```bash
# Clone the repository
git clone https://github.com/ncrmro/keystone.git
cd keystone

# Build ISO with your SSH key
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
```

### 2. Test in a VM (Optional)

```bash
# Quick VM test with automated build
./bin/build-vm terminal    # Terminal environment
./bin/build-vm desktop     # Full desktop environment

# Or use the full-stack VM testing
./bin/virtual-machine --name keystone-test-vm --start
```

### 3. Deploy to Hardware

```bash
# Boot target machine from ISO
# Get IP address from installer console

# Deploy from your development machine
nixos-anywhere --flake .#test-server root@<installer-ip>
```

### 4. Post-Installation

```bash
# SSH into deployed system
ssh root@<server-ip>

# Enroll TPM for automatic unlock
keystone-enroll-tpm

# Verify secure boot status
bootctl status
```

## Architecture Overview

### System Types

#### Servers
Always-on infrastructure providing:
- Network gateway and VPN services
- DNS with ad/tracker blocking
- Storage and backup services
- Media streaming
- Container hosting

#### Clients
Interactive systems featuring:
- **Workstations** - Always-on development machines with remote access
- **Laptops** - Portable devices with full desktop environments
- Hyprland Wayland compositor
- Terminal development environment
- Secure boot and full disk encryption

### Security Features

- **TPM2 Integration** - Hardware-based key storage and attestation
- **Full Disk Encryption** - LUKS + ZFS native encryption
- **Secure Boot** - Lanzaboote with custom key enrollment
- **Zero-Knowledge** - All data encrypted before leaving devices

### Key Technologies

- **NixOS** - Declarative, reproducible system configuration
- **ZFS** - Advanced filesystem with snapshots and compression
- **Disko** - Declarative disk partitioning
- **Home Manager** - User environment management
- **SystemD** - Service orchestration and boot management

## Development Roadmap

### Current Release: v0.0.1 (Alpha)
- ✅ Encrypted server with TPM2 unlock
- ✅ Secure Boot support
- ✅ ISO installer
- 🔧 Documentation and polish needed

### Upcoming Releases

#### v0.0.2 - Developer Environment
- Terminal development via SSH
- Home-manager integration
- Cross-platform development

#### v0.0.3 - Workstation Desktop
- Hyprland compositor
- Remote desktop access
- Full application suite

#### v0.0.4 - Universal Development
- GitHub Codespaces support
- macOS compatibility
- Portable configurations

See the full **[Roadmap](https://github.com/ncrmro/keystone/blob/main/ROADMAP.md)** for detailed version plans and future features.

## Contributing

We welcome contributions! Areas where help is particularly needed:

- Documentation improvements
- Testing and bug reports
- Security auditing
- Module development
- Platform support

Please see our [GitHub repository](https://github.com/ncrmro/keystone) for details on how to get involved.

## Community & Support

- **Issues** - [GitHub Issues](https://github.com/ncrmro/keystone/issues)
- **Discussions** - [GitHub Discussions](https://github.com/ncrmro/keystone/discussions)
- **Security** - Report security issues privately via GitHub Security Advisories

## License

Keystone is open source software licensed under the [MIT License](https://github.com/ncrmro/keystone/blob/main/LICENSE).

---

*This documentation is continuously updated. For the latest information, please check the [GitHub repository](https://github.com/ncrmro/keystone).*
