# Keystone ISO Installer Example

This example demonstrates how to create a USB installer with your SSH keys for remote installation using nixos-anywhere.

## Setup

1. **Add your SSH keys**: Edit the `flake.nix` file and replace the example SSH keys with your actual public keys:

```nix
exampleSshKeys = [
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7... your-user@your-machine"
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your-user@your-machine"
];
```

2. **Build the ISO**:
```bash
nix build .#iso
```

The ISO will be created in `./result/iso/keystone-installer.iso`.

## Writing to USB

### Automatic (recommended)
```bash
nix run .#write-usb /dev/sdX
```
Replace `/dev/sdX` with your USB device path (e.g., `/dev/sdb`).

### Manual
```bash
sudo dd if=result/iso/keystone-installer.iso of=/dev/sdX bs=4M status=progress
sync
```

## Using the Installer

1. **Boot from USB**: Boot the target machine from the USB drive
2. **Get IP address**: The installer will automatically get an IP via DHCP
3. **Connect via SSH**: Connect to the installer using your private key:
   ```bash
   ssh root@<installer-ip>
   ```
4. **Run nixos-anywhere**: Use nixos-anywhere to install NixOS remotely

## nixos-anywhere Integration

This installer is designed to work seamlessly with [nixos-anywhere](https://github.com/numtide/nixos-anywhere):

```bash
# From your local machine
nixos-anywhere --flake .#your-config root@<installer-ip>
```

The installer includes all necessary tools for partitioning, formatting, and installing NixOS.

## Customization

You can further customize the installer by modifying the `flake.nix` file to:
- Add additional SSH keys
- Include extra packages
- Modify network configuration
- Add custom scripts or configurations

## Security Notes

- The installer allows root SSH access with key-based authentication only
- Password authentication is disabled
- Consider using a dedicated SSH key pair for the installer
- The installer ISO contains your public keys, so treat it accordingly