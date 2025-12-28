# Keystone

Self-sovereign NixOS infrastructure platform for deploying secure, encrypted systems on any hardware.

**[Documentation](https://ncrmro.github.io/keystone/)** | **[Roadmap](ROADMAP.md)**

---

## Overview

Keystone provides declarative, reproducible infrastructure with hardware-backed security:

- **Full disk encryption** with TPM2 auto-unlock
- **Secure Boot** with custom key enrollment
- **ZFS storage** with native encryption and snapshots
- **Portable configs** — migrate between bare-metal and cloud seamlessly

## Architecture

| Type | Purpose | Examples |
|------|---------|----------|
| **Server** | Always-on services (VPN, DNS, storage, backups) | Raspberry Pi, NUC, VPS |
| **Client** | Interactive workstations with Hyprland desktop | Desktop, laptop |

Both share the same security model: TPM2, LUKS encryption, Secure Boot attestation.

---

## Quick Start

### Using the Flake Template (Recommended)

```bash
# Initialize from template
nix flake init -t github:ncrmro/keystone

# Find required values
grep -n "TODO:" configuration.nix
head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '  # Generate hostId
ls -la /dev/disk/by-id/                                  # Find disk ID

# Deploy to target machine
nixos-anywhere --flake .#my-machine root@<installer-ip>
```

The template includes documented `keystone.os.*` options with TODO markers for required values.

### Building the Installer ISO

```bash
# x86_64 ISO with your SSH key
make build-iso-ssh

# aarch64 ISO (Apple Silicon Macs)
make build-iso-ssh-aarch64

# Or with explicit flags
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub --arch aarch64-linux
```

**No Nix installed?** Use the devcontainer with VS Code or GitHub Codespaces:
1. Open repo in devcontainer
2. Run `make build-iso-ssh-aarch64`
3. Copy `result/iso/*.iso` to USB

**Cross-compilation** (building aarch64 on x86_64):
```nix
# Add to NixOS config, then nixos-rebuild switch
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
```

### Deploying

```bash
# Write ISO to USB
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress

# Deploy to target machine
nixos-anywhere --flake .#your-server root@<installer-ip>

# Post-install: enroll TPM
ssh root@<target-ip> keystone-enroll-tpm
```

See [Installation Guide](docs/installation.md) for complete instructions.

---

## Using as a Flake Input

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
        # keystone.nixosModules.desktop  # Add for Hyprland
        {
          networking.hostId = "deadbeef";
          keystone.os = {
            enable = true;
            storage.devices = [ "/dev/disk/by-id/nvme-..." ];
            users.admin = {
              fullName = "Admin";
              extraGroups = [ "wheel" ];
              authorizedKeys = [ "ssh-ed25519 ..." ];
            };
          };
        }
      ];
    };
  };
}
```

### Available Modules

**NixOS** (`keystone.nixosModules.*`):
| Module | Description |
|--------|-------------|
| `operating-system` | Core OS (storage, secure boot, TPM, users, SSH, mDNS, firewall) |
| `desktop` | Hyprland desktop environment (audio, greetd login) |
| `isoInstaller` | Bootable installer configuration |

**Home Manager** (`keystone.homeModules.*`):
| Module | Description |
|--------|-------------|
| `terminal` | Dev environment (Helix, Zsh, Zellij, Ghostty, Git) |
| `desktop` | Full Hyprland desktop configuration |

---

## Development

```bash
# Fast config testing (no encryption overhead)
make build-vm-terminal    # SSH into terminal VM
make build-vm-desktop     # Hyprland desktop VM

# Full-stack testing (TPM + Secure Boot)
make vm-create            # Create libvirt VM
make vm-ssh               # SSH into test VM
make vm-reset             # Delete VM and artifacts

# Run tests
make test
```

See `make help` for all available targets.

---

## License

[MIT](LICENSE)
