# Quickstart: Secure Boot with Keystone

## Overview

Keystone now includes automatic Secure Boot setup during deployment. When you deploy a Keystone system using nixos-anywhere, Secure Boot keys are automatically generated and enrolled, and the bootloader is signed - all in a single deployment step.

## Prerequisites

- UEFI firmware in Setup Mode (VMs are automatically configured this way)
- x86_64 system with UEFI support
- Keystone ISO or nixos-anywhere deployment environment

## Quick Deploy

### 1. Verify Setup Mode (Optional)

If deploying to existing hardware, verify it's in Setup Mode:

```bash
# From a Linux live environment on the target
cat /sys/firmware/efi/efivars/SetupMode-* | od -An -t u1 | grep -q "1" && echo "Setup Mode: Yes" || echo "Setup Mode: No"
```

### 2. Deploy with Secure Boot

No changes needed to your deployment command:

```bash
# Standard deployment automatically includes Secure Boot
nixos-anywhere --flake .#your-config root@target-ip
```

That's it! Secure Boot is now enabled and will be active on first boot.

### 3. Verify Secure Boot Status

After deployment and first boot:

```bash
ssh root@target-ip
bootctl status | grep "Secure Boot"
# Expected: "Secure Boot: enabled (user)"
```

## Configuration Options

### Basic Configuration (Default)

Most users don't need any configuration. Secure Boot is automatically enabled for server deployments:

```nix
{
  keystone.server.enable = true;  # Secure Boot included automatically
}
```

### Explicit Configuration

If you want to explicitly control Secure Boot:

```nix
{
  keystone.secureBoot = {
    enable = true;        # Enable Secure Boot
    includeMS = false;    # Don't include Microsoft certificates (default)
    autoEnroll = true;    # Auto-enroll keys when in Setup Mode (default)
  };
}
```

### Dual-Boot Systems

For systems that dual-boot with Windows or run third-party UEFI drivers:

```nix
{
  keystone.secureBoot = {
    enable = true;
    includeMS = true;  # Include Microsoft certificates
  };
}
```

## Testing in a VM

### Quick Test

```bash
# One command to test Secure Boot deployment
./bin/test-deployment --rebuild-iso --hard-reset

# After deployment completes, verify:
ssh -o StrictHostKeyChecking=no root@192.168.100.99 bootctl status
```

### Manual VM Testing

```bash
# 1. Create a VM with UEFI firmware
./bin/virtual-machine --name secure-test --start

# 2. Deploy Keystone
nixos-anywhere --flake .#test-server root@192.168.100.99

# 3. VM automatically reboots with Secure Boot enabled
# No manual intervention required!
```

## Troubleshooting

### "Not in Setup Mode" Error

If deployment fails with Setup Mode error:

1. **Physical System**: Enter UEFI settings and reset to Setup Mode
2. **VM**: Reset NVRAM to Setup Mode:
   ```bash
   virsh shutdown your-vm
   ./bin/virtual-machine --reset-setup-mode your-vm
   virsh start your-vm
   ```

### Keys Already Enrolled

If you see "Already in User Mode":
- System already has Secure Boot configured
- Deployment continues using existing keys
- To re-enroll, reset to Setup Mode first

### Verification Commands

Check various aspects of Secure Boot:

```bash
# Full Secure Boot status
bootctl status

# Check if keys are enrolled
sbctl status

# List enrolled keys
sbctl list-files

# Verify specific file signatures
sbctl verify
```

## Migration from Old Process

If you previously used the post-install-provisioner:

1. **No action required** for new deployments
2. **Existing systems** continue to work (already enrolled)
3. **Re-deployment** automatically uses new integrated process

The `bin/post-install-provisioner` script is now deprecated and will be removed in a future version.

## Security Considerations

- **Keys are unique per deployment**: Each installation generates new keys
- **Keys are stored in**: `/var/lib/sbctl/keys/`
- **No key backup by default**: Keys are regenerated on reinstall
- **Physical security**: Setup Mode reset requires physical/console access

## Advanced Usage

### Custom PKI Location

```nix
{
  keystone.secureBoot = {
    enable = true;
    pkiBundle = "/custom/path/to/keys";  # Non-standard key location
  };
}
```

### Manual Enrollment

Generate keys without enrolling (for custom enrollment process):

```nix
{
  keystone.secureBoot = {
    enable = true;
    autoEnroll = false;  # Generate but don't enroll
  };
}

# Then manually enroll:
# sbctl enroll-keys --yes-this-might-brick-my-machine
```

## What's Happening Behind the Scenes

1. **During `nixos-anywhere` deployment**:
   - Disko partitions the disk
   - Post-create hook checks Setup Mode
   - sbctl generates unique Secure Boot keys
   - Keys are enrolled in UEFI firmware
   - Firmware transitions to User Mode

2. **During NixOS installation**:
   - Lanzaboote module detects keys
   - Bootloader and kernel are signed
   - Signed artifacts are installed

3. **On first boot**:
   - UEFI verifies signatures
   - Secure Boot is active
   - No manual steps needed!

## Support

- **Issues**: Report at https://github.com/ncrmro/keystone/issues
- **Documentation**: See `modules/secure-boot/README.md`
- **Examples**: Check `examples/secure-boot-*.nix`