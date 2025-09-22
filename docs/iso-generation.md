# ISO Generation Guide

This guide explains how to generate a Keystone installer ISO with your SSH public keys.

## Quick Start

### Method 1: Using the main flake (no SSH keys)

```bash
# Build the ISO without SSH keys
nix build .#nixosConfigurations.keystoneIso.config.system.build.isoImage

# The ISO will be available at: result/iso/keystone-installer.iso
```

### Method 2: Create your own flake with SSH keys

1. Create a new directory for your custom ISO:
```bash
mkdir my-keystone-iso
cd my-keystone-iso
```

2. Create a `flake.nix` file:
```nix
{
  description = "My custom Keystone ISO with SSH keys";
  
  inputs = {
    keystone.url = "github:yourusername/keystone";  # or path:../path/to/keystone
    nixpkgs.follows = "keystone/nixpkgs";
  };
  
  outputs = { self, keystone, nixpkgs }: {
    nixosConfigurations = {
      myKeystoneIso = keystone.lib.mkKeystoneIso {
        sshKeys = [
          # Add your SSH public keys here
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG... user@workstation"
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD... admin@server"
        ];
      };
    };
    
    packages.x86_64-linux.default = 
      self.nixosConfigurations.myKeystoneIso.config.system.build.isoImage;
  };
}
```

3. Build your custom ISO:
```bash
nix build
```

## Getting Your SSH Public Key

To find your SSH public key:

```bash
# For Ed25519 keys (recommended)
cat ~/.ssh/id_ed25519.pub

# For RSA keys
cat ~/.ssh/id_rsa.pub

# If you don't have a key, generate one:
ssh-keygen -t ed25519 -C "your-email@example.com"
```

## Writing to USB Drive

### Using the convenience script (if available)
```bash
nix run .#write-usb /dev/sdX  # Replace X with your USB drive letter
```

### Manual method
```bash
# Find your USB device
lsblk

# Write the ISO (replace /dev/sdX with your actual device)
sudo dd if=result/iso/keystone-installer.iso of=/dev/sdX bs=4M status=progress
sync
```

⚠️ **Warning**: Double-check your device path! The `dd` command will overwrite all data on the target device.

## Using the ISO

1. Boot from the USB drive
2. The system will automatically:
   - Start SSH daemon
   - Configure networking via DHCP
   - Load your SSH keys for root access

3. Find the IP address:
```bash
ip addr show
```

4. Connect remotely:
```bash
ssh root@<ip-address>
```

## Features Included

The Keystone installer ISO includes:

- **SSH access**: Preconfigured with your public keys
- **Networking**: DHCP enabled by default
- **Essential tools**: git, curl, vim, htop, parted, cryptsetup
- **ZFS support**: Ready for advanced filesystem setups
- **nixos-anywhere compatibility**: Works with automated deployment tools

## Troubleshooting

### ISO build fails
- Ensure you have enough disk space (builds can be several GB)
- Check that all SSH keys are valid public keys
- Verify your flake syntax with `nix flake check`

### Can't connect via SSH
- Verify the machine has network connectivity
- Check that SSH is running: `systemctl status sshd`
- Ensure your private key corresponds to the public key in the ISO
- Try connecting with verbose output: `ssh -v root@<ip>`

### USB won't boot
- Ensure UEFI/BIOS is configured to boot from USB
- Try a different USB port or drive
- Verify the ISO was written correctly by checking the file size

## Advanced Usage

### Custom hostname
```nix
# In your flake.nix modules list:
{
  networking.hostName = "my-installer";
}
```

### Additional packages
```nix
# In your flake.nix modules list:
{
  environment.systemPackages = with pkgs; [
    tmux
    ripgrep
    # ... other packages
  ];
}
```

### Wireless networking
```nix
# In your flake.nix modules list:
{
  networking.wireless.enable = true;
  networking.wireless.networks = {
    "MyWiFi" = {
      psk = "password";
    };
  };
}
```