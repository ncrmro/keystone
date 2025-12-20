# Keystone Roadmap

## Project Vision

Keystone is a NixOS-based self-sovereign infrastructure platform that enables users to deploy secure, encrypted infrastructure on any hardware. It provides a progressive path from secure servers to full desktop workstations, with consistent developer experience across all platforms.

> **Specification**: See [`specs/001-keystone-os/spec.md`](specs/001-keystone-os/spec.md) for functional requirements and [`specs/001-keystone-os/plan.md`](specs/001-keystone-os/plan.md) for technology implementation details.

## Version 0.0.1 (Alpha) - Secure Foundation
**Status**: 🟢 Core Complete | 🟡 Needs Polish

### Goal
Deploy a fully encrypted NixOS server with TPM2 automatic unlock and Secure Boot support.

### Features

#### ✅ Implemented & Working
- **ZFS Root with Native Encryption** (`modules/disko-single-disk-root/`)
  - Credstore pattern for key management
  - SystemD initrd integration
  - Automatic pool import and validation
- **TPM2 Enrollment** (`modules/tpm-enrollment/`)
  - PCR binding configuration (default: PCRs 1,7)
  - Enrollment check scripts
  - Login banner notifications for unenrolled systems
- **Secure Boot with Lanzaboote** (`modules/secure-boot/`)
  - Automatic key provisioning
  - UEFI variable management
  - Signed UKI generation
- **ISO Installer** (`modules/iso-installer.nix`)
  - Bootable installation media
  - SSH key injection support
  - nixos-anywhere compatibility
- **Server Base Module** (`modules/server/`)
  - SSH configuration
  - mDNS/Avahi discovery
  - Basic firewall rules

#### 🔧 Needs Polish Before Release
- [ ] Comprehensive installation documentation with screenshots
- [ ] Error recovery procedures for TPM enrollment failures
- [ ] Automated testing in CI for secure boot chain
- [ ] Validation script for post-installation security state
- [ ] Support for multiple disk configurations

### Installation Flow
```bash
# Build ISO with SSH key
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# Deploy to target machine
nixos-anywhere --flake .#your-server root@<installer-ip>

# Post-installation: enroll TPM
keystone-enroll-tpm
```

---

## Version 0.0.2 - Developer Environment
**Status**: 🟢 Core Complete | 🟡 Integration Needed

### Goal
SSH into your Keystone server from any client OS and have a complete terminal development environment via home-manager.

### Features

#### ✅ Implemented & Working
- **Terminal Dev Environment Module** (`home-manager/modules/terminal-dev-environment/`)
  - Helix editor with LSP support
  - Zsh with Oh My Zsh and utilities
  - Zellij multiplexer
  - Ghostty terminal emulator
  - Git with lazygit UI
- **User Management** (`modules/users/`)
  - Declarative user creation
  - SSH key management
  - Home-manager integration points

#### 🔧 Needs Polish Before Release
- [ ] Server-side home-manager integration module
- [ ] Remote development workflow documentation
- [ ] VS Code Remote SSH configuration guide
- [ ] Nix shell environment preservation over SSH
- [ ] Shared tmux/zellij session support for collaboration
- [ ] Automatic dotfiles synchronization

### Usage Pattern
```bash
# SSH from any client (Mac/Windows/Linux)
ssh user@keystone-server

# Full dev environment available immediately
hx ~/project/main.rs  # Helix with LSP
zellij                 # Terminal multiplexer
lazygit                # Git UI
```

---

## Version 0.0.3 - Workstation Desktop
**Status**: 🟢 Recently Implemented | 🟡 Testing Phase

### Goal
Deploy a Hyprland-based workstation that users can access remotely or use locally, maintaining development continuity regardless of client OS.

### Features

#### ✅ Implemented & Working
- **Hyprland Desktop Stack** (`modules/client/`)
  - UWSM session management
  - Greetd login manager with tuigreet
  - PipeWire audio system
  - NetworkManager with Bluetooth
- **Desktop Applications** (`modules/client/desktop/packages.nix`)
  - Firefox browser
  - VS Code editor
  - VLC media player
  - Hyprland utilities (hyprshot, hyprpicker, etc.)
- **Desktop Services**
  - Hyprlock screen locker
  - Hypridle automatic locking
  - Waybar status bar
  - Mako notifications
  - Hyprpaper wallpaper

#### 🔧 Needs Polish Before Release
- [ ] Remote desktop access setup (RDP/VNC/Sunshine)
- [ ] Display manager theme customization
- [ ] Power profiles for desktop vs laptop
- [ ] Multi-monitor configuration templates
- [ ] Application launcher (rofi/wofi) integration
- [ ] Clipboard manager setup
- [ ] Default hyprland.conf refinement

### Deployment Options
```bash
# Option 1: Direct installation on workstation
nixos-anywhere --flake .#your-workstation root@<installer-ip>

# Option 2: Test in VM first
./bin/build-vm desktop

# Option 3: Remote workstation access
ssh -X user@keystone-workstation  # X11 forwarding
# or use Sunshine/Moonlight for gaming-grade streaming
```

### Explicitly Out of Scope for 0.0.3
- Laptop-specific features (suspend/hibernate, battery management)
- Complex multi-GPU setups
- Fractional scaling configurations

---

## Version 0.0.4 - Universal Development
**Status**: 📝 Planning Phase

### Goal
Take your home-manager configuration everywhere - GitHub Codespaces, macOS, or any Nix-supported platform.

### Planned Features

#### Core Capabilities
- **Standalone Home-Manager Flake**
  - Extracted terminal dev environment
  - Platform detection and adaptation
  - Minimal dependencies

- **GitHub Codespaces Integration**
  - Automatic home-manager activation
  - Persistent user settings
  - Devcontainer.json templates

- **macOS Support via nix-darwin**
  - Homebrew integration for GUI apps
  - macOS-specific keybindings
  - System preferences management

- **Cross-Platform Sync**
  - Git-based configuration management
  - Secure secrets handling (agenix/sops-nix)
  - State synchronization strategies

### Usage Scenarios
```bash
# Codespaces: Automatic setup on container start
# .devcontainer/devcontainer.json references home-manager

# macOS: One-time setup
nix run github:ncrmro/keystone#home-manager -- switch

# Any Linux with Nix
nix-shell -p home-manager --run "home-manager switch --flake github:ncrmro/keystone#portable"
```

### Technical Requirements
- [ ] Separate flake output for portable configurations
- [ ] Platform detection module
- [ ] Conditional package installation based on OS
- [ ] Documentation for each platform
- [ ] CI testing across platforms

---

## Future Versions (Tentative)

### Version 0.1.0 - Production Ready
- Automated backups with ZFS snapshots
- Monitoring and alerting stack
- Secrets management (agenix/sops-nix)
- Multi-host deployment strategies
- Disaster recovery procedures

### Version 0.2.0 - Advanced Infrastructure
- Kubernetes/k3s integration
- Self-hosted services catalog (Nextcloud, Gitea, etc.)
- Mesh VPN with Headscale/Tailscale
- Distributed storage with Ceph/GlusterFS
- High availability configurations

### Version 0.3.0 - Enterprise Features
- LDAP/Active Directory integration
- Compliance automation (CIS, STIG)
- Audit logging and SIEM integration
- Certificate management with step-ca
- Policy-as-code with Open Policy Agent

---

## Testing Infrastructure

### Available Now
- `./bin/build-vm` - Quick iteration VM testing
- `./bin/virtual-machine` - Full-stack libvirt VMs
- `./bin/test-deployment` - Integration testing
- GitHub Actions CI for basic builds

### Migration to Flake Checks
Tests are being migrated to proper `nix flake check` outputs for better CI integration. See [`specs/001-keystone-os/plan.md`](specs/001-keystone-os/plan.md#testing-infrastructure) for the migration plan.

Target structure:
- `checks.x86_64-linux.vm-*` - Fast iteration VMs
- `checks.x86_64-linux.integration-*` - Full stack testing with TPM emulation
- `checks.x86_64-linux.nixos-*` - Module unit tests

### Needed for v0.0.1
- Automated secure boot testing
- TPM emulation in CI
- Installation success validation
- Security posture verification

---

## Contributing

Each version should include:
1. Complete documentation
2. Integration tests
3. Migration guides from previous versions
4. Security considerations
5. Performance benchmarks

See `CONTRIBUTING.md` for development guidelines and `docs/` for technical documentation.

---

## Current Development Focus

**Immediate Priority**: Polish v0.0.1 for alpha release
- Complete installation documentation
- Add error recovery procedures
- Implement automated testing
- Create demonstration videos

**Next Sprint**: Finalize v0.0.2 integration
- Server home-manager module
- Remote development guides
- SSH workflow optimization

**Following Sprint**: v0.0.3 stabilization
- Remote desktop setup
- Multi-monitor support
- Performance optimization