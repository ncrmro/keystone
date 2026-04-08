---
title: ISO Generation
description: Generate a Keystone installer ISO with SSH keys for remote installation
---

# ISO Generation

Generate a Keystone installer ISO with SSH keys for remote installation.

## Config repo (mkSystemFlake)

Flakes built with `mkSystemFlake` automatically produce an installer ISO when the flake
declares at least one Linux host. Add your SSH public keys to the `admin` block and build:

```nix
# flake.nix
keystone.lib.mkSystemFlake {
  admin = {
    fullName = "Your Name";
    username = "admin";
    email = "admin@example.com";
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG... user@host"
    ];
  };
  # ...
};
```

```bash
nix build .#packages.x86_64-linux.iso -o installer-iso
```

Replace `x86_64-linux` with the correct target system for your flake, such as
`aarch64-linux`, if you are not building for x86_64. The system is inferred
automatically from your Linux host inventory; set `defaults.system` to override.

The ISO includes the admin's terminal environment (helix, zsh, starship), SSH access
with the declared keys, and the Keystone TUI installer.

## Keystone repo (build-iso)

From the keystone repo itself, use the `build-iso` command:

```bash
# Build without SSH keys
./bin/build-iso

# Build with SSH key from file
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# Build with SSH key string directly
./bin/build-iso --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG... user@host"
```

The `--ssh-key` option accepts a file path (`~/.ssh/id_ed25519.pub`) or an inline key
string.

## Validate in a VM

Test the ISO before flashing to hardware:

```bash
# UEFI boot with QEMU (requires KVM and OVMF)
qemu-system-x86_64 -m 4096 -smp 2 -enable-kvm \
  -bios $(nix build nixpkgs#OVMF.fd --print-out-paths --no-link)/FV/OVMF.fd \
  -cdrom installer-iso/iso/*.iso
```

The VM boots to the Keystone TUI installer on the graphical console. SSH is available
at the VM's DHCP address if keys were configured.

## Write to USB

```bash
# Find USB device
lsblk

# Write ISO (WARNING: erases all data on target device)
sudo dd if=installer-iso/iso/*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## Use the ISO

1. Boot from USB (UEFI)
2. System auto-configures: SSH, DHCP, networking
3. Get IP: `ip addr show`
4. Connect: `ssh root@<ip-address>`
5. Install: `nixos-anywhere --flake .#hostname root@<ip-address>`

## Features

- Terminal environment (helix, zsh, starship) when built via `mkSystemFlake`
- SSH with your keys (public key auth only)
- DHCP networking via NetworkManager
- ZFS, disko, cryptsetup, sbctl, and TPM tools pre-installed
- Keystone TUI installer on tty1
- nixos-anywhere compatible

## Platform setup

Need to install Nix first? See [Build Platforms](build-platforms.md) for setup on
Ubuntu, macOS, Windows, and GitHub Actions.
