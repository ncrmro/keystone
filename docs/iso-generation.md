# ISO Generation Guide

Generate a Keystone installer ISO with SSH keys for remote installation.

## Quick Build

```bash
# Clone and build
git clone https://github.com/yourusername/keystone
cd keystone

# Build without SSH keys
./bin/build-iso

# Build with SSH key from file
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# Build with SSH key string directly
./bin/build-iso --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG... user@host"
```

## SSH Key Options

The `--ssh-key` option accepts either:

### File Path
```bash
# File paths (starts with /, ~, or .)
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
./bin/build-iso --ssh-key /home/user/.ssh/authorized_keys
./bin/build-iso --ssh-key ./my-keys.txt
```

### Direct Key String
```bash
# SSH key string directly
./bin/build-iso --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG... user@host"
./bin/build-iso --ssh-key "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD... user@host"
```

## Get Your SSH Key

```bash
# Ed25519 (recommended)
cat ~/.ssh/id_ed25519.pub

# RSA
cat ~/.ssh/id_rsa.pub

# Generate if needed
ssh-keygen -t ed25519 -C "your-email@example.com"
```

## Write to USB

```bash
# Find USB device
lsblk

# Write ISO
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress
sync
```

⚠️ **Warning**: `dd` will erase all data on target device.

## Use the ISO

1. Boot from USB
2. System auto-configures: SSH, DHCP, tools
3. Get IP: `ip addr show`
4. Connect: `ssh root@<ip-address>`

## Features

- SSH with your keys
- DHCP networking
- Essential tools (git, vim, parted, etc.)
- ZFS support
- nixos-anywhere compatible

## Advanced Usage

```bash
./bin/build-iso --help              # Show all options
./bin/build-iso -o custom-dir       # Custom output directory

# Direct Nix commands (no SSH keys)
nix build .#iso                     # Build ISO directly
```

## Platform Setup

Need to install Nix first? See **[Build Platforms](build-platforms.md)** for setup instructions on Ubuntu, macOS, Windows, and GitHub Actions.

## File Format

When using a file path, SSH keys file should contain one public key per line:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG... user@workstation  
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD... admin@server
```