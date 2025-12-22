# Test Virtiofs VM Configuration

This directory contains a test configuration for virtiofs filesystem sharing between host and guest.

## ⚠️ Incomplete Configuration

This configuration is a **template** and requires manual disk partitioning setup. It demonstrates how to use the virtiofs guest module but is not ready for automated deployment.

## Prerequisites

### Host Setup

1. Enable virtiofsd on the host:
   ```nix
   # /etc/nixos/configuration.nix
   imports = [ ./path/to/keystone/modules/virtualization/host-virtiofs.nix ];
   keystone.virtualization.host.virtiofs.enable = true;
   ```

2. Rebuild: `sudo nixos-rebuild switch`

### Create VM

```bash
./bin/virtual-machine --name test-virtiofs --enable-virtiofs --start
```

## Manual Setup

Since this is a template, you need to:

1. Boot the VM from the Keystone installer ISO
2. Partition the disk manually or use disko
3. Install NixOS with this configuration
4. The configuration will automatically mount the host's /nix/store via virtiofs

## What This Configuration Demonstrates

- Importing the `guest-virtiofs.nix` module
- Enabling virtiofs with `keystone.virtualization.guest.virtiofs.enable = true`
- Verification service that checks virtiofs is working correctly
- MOTD displaying virtiofs status information

## For Complete Examples

See the example configurations:
- `examples/virtiofs-guest-config.nix` - Complete guest configuration
- `examples/virtiofs-host-config.nix` - Complete host configuration
- `docs/virtiofs-setup.md` - Full setup guide

## Using with Keystone OS Module

For a complete deployment-ready configuration that includes encryption, secure boot, and virtiofs:

```nix
{
  imports = [
    keystone.nixosModules.operating-system
    keystone.nixosModules.virtiofs-guest
  ];

  keystone.os = {
    enable = true;
    storage = { /* ... */ };
    secureBoot.enable = true;
    # ... other options
  };

  keystone.virtualization.guest.virtiofs = {
    enable = true;
    shareName = "nix-store-share";
  };
}
```

**Note**: When using virtiofs with the OS module, the `/nix/store` will be shared from the host, but encryption and secure boot will still protect the rest of the system.
