# Quickstart Guide: NixOS-Anywhere VM Installation

**Feature**: 002-nixos-anywhere-vm-install
**Last Updated**: 2025-10-22

## Overview

This guide walks you through deploying a minimal Keystone server to a VM using nixos-anywhere. You'll go from a booted ISO to a fully configured, encrypted server in under 10 minutes.

## Prerequisites

### On Development Machine

- Nix with flakes enabled
- `nixos-anywhere` installed (or available via `nix run`)
- SSH client
- Network connectivity to target VM

### On Target VM

- VM booted from Keystone installer ISO (see feature 001)
- SSH access enabled
- At least 20GB disk space
- Network connectivity

## Quick Start (5 Steps)

### 1. Build the Installer ISO

If you haven't already built an ISO with SSH keys:

```bash
# Build ISO with your SSH public key
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# OR use an existing ISO
nix build .#iso
```

### 2. Boot VM from ISO

Boot your VM using the built ISO. The VM should:
- Boot to NixOS installer
- Enable SSH server
- Display IP address on login screen

Note the IP address displayed (e.g., `192.168.122.50`).

### 3. Create Deployment Configuration

Create a configuration file for your test server:

```bash
# Create VM configuration directory
mkdir -p vms/test-server

# Create configuration file
cat > vms/test-server/configuration.nix <<'EOF'
{ config, pkgs, ... }:
{
  # System identity
  networking.hostName = "test-server";

  # Enable Keystone modules
  keystone = {
    # Disk configuration
    disko = {
      enable = true;
      device = "/dev/vda";  # Adjust for your VM (VirtualBox uses /dev/sda)
      enableEncryptedSwap = true;
      swapSize = "8G";  # Adjust based on VM RAM
    };

    # Server services
    server.enable = true;
  };

  # SSH access - REPLACE WITH YOUR PUBLIC KEY
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG... your-username@your-machine"
  ];

  # Timezone (optional)
  time.timeZone = "UTC";
}
EOF
```

**Important**: Replace the SSH public key with your actual key from `~/.ssh/id_ed25519.pub`.

### 4. Add Configuration to Flake

Edit `flake.nix` and add the new nixosConfiguration:

```nix
# In outputs section, add to nixosConfigurations:
nixosConfigurations.test-server = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    disko.nixosModules.disko
    ./modules/server
    ./modules/disko-single-disk-root
    ./vms/test-server/configuration.nix
  ];
};
```

Test the configuration builds:

```bash
nix build .#nixosConfigurations.test-server.config.system.build.toplevel
```

If this succeeds, your configuration is valid.

### 5. Deploy with nixos-anywhere

Deploy to the target VM:

```bash
# Replace 192.168.122.50 with your VM's IP address
nixos-anywhere --flake .#test-server root@192.168.122.50
```

**What happens**:
1. nixos-anywhere connects to the target via SSH
2. Partitions and formats the disk (`/dev/vda`)
3. Creates ZFS pool with encryption
4. Sets up credstore for encryption keys
5. Installs NixOS system
6. Configures all services
7. Reboots the VM

**Expected output**:
```
>>> Connecting to target...
>>> Partitioning disk /dev/vda...
>>> Creating ZFS pool...
>>> Installing system...
>>> System installed successfully
>>> Rebooting target...
```

Deployment typically takes 5-10 minutes depending on network speed.

### 6. First Boot and Verification

After deployment completes:

1. **Wait for reboot**: The VM will restart automatically
2. **Unlock credstore**: You'll see a password prompt on the console
   - This is expected in VMs without TPM2
   - Enter a password to unlock the encrypted credstore
   - Remember this password for future boots
3. **Wait for boot**: System continues booting after unlock
4. **Test SSH access**:

```bash
# SSH into the deployed server
ssh root@192.168.122.50

# Check hostname
hostname
# Should output: test-server

# Check ZFS pool
zpool status
# Should show healthy rpool

# Check services
systemctl status sshd
systemctl status avahi-daemon
systemctl status systemd-resolved

# Check mDNS (from dev machine)
ping test-server.local
```

## Verification Script (Optional)

Run the automated verification script:

```bash
# Once implemented in Phase 2
./scripts/verify-deployment.sh test-server 192.168.122.50
```

Expected output:
```
Verifying deployment: test-server at 192.168.122.50
✓ PASS: SSH connectivity
✓ PASS: Hostname matches configuration
✓ PASS: Firewall configured correctly
✓ PASS: ZFS pool healthy
✓ PASS: Encryption enabled
✓ PASS: Essential services running
✓ PASS: mDNS advertisement active

All checks passed! Deployment verified.
```

## Common Issues and Solutions

### Issue: "Connection refused" when running nixos-anywhere

**Cause**: SSH service not running on target, or wrong IP address

**Solution**:
1. Verify IP address displayed on VM console
2. Test SSH manually: `ssh root@<ip>`
3. Check VM network is bridged or NAT with port forwarding

### Issue: "Device /dev/vda not found"

**Cause**: Wrong disk device name for your VM type

**Solution**:
- QEMU/KVM VMs: Use `/dev/vda`
- VirtualBox VMs: Use `/dev/sda`
- Check with: `lsblk` on the target system

### Issue: "No authorized keys" after deployment

**Cause**: SSH key not added to configuration or wrong key format

**Solution**:
1. Verify SSH public key in `vms/test-server/configuration.nix`
2. Ensure key is complete single line (no line breaks)
3. Redeploy with corrected configuration

### Issue: Password prompt appears on every boot

**Cause**: Normal behavior in VMs without TPM2

**Solution**:
- This is expected - VMs don't have hardware TPM2 by default
- Enter the password you set on first boot
- For production deployments on bare metal, TPM2 enables automatic unlock

### Issue: Deployment succeeds but system won't boot

**Cause**: Disk encryption configuration issue or VM boot settings

**Solution**:
1. Check VM boot order (UEFI, disk first)
2. Verify ZFS pool imported: `zpool import -N rpool`
3. Check credstore: `cryptsetup status credstore`
4. Review boot logs for errors

## Next Steps

After successful deployment:

1. **Test reproducibility**: Destroy the VM and redeploy
2. **Test configuration changes**: Modify config and redeploy
3. **Explore mDNS**: Access server via `test-server.local`
4. **Add monitoring**: Install additional services
5. **Deploy to production**: Use same process with production config

## Advanced Usage

### Deploying to Physical Hardware

Change the disk device to a stable identifier:

```nix
keystone.disko.device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0W127373V";
```

List available devices on target:
```bash
ls -l /dev/disk/by-id/
```

### Multiple SSH Keys

Add multiple authorized keys for team access:

```nix
users.users.root.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3... admin@workstation"
  "ssh-ed25519 AAAAC3... developer@laptop"
  "ssh-ed25519 AAAAC3... backup@backup-server"
];
```

### Customizing Swap Size

Adjust swap based on system RAM:

```nix
keystone.disko = {
  enable = true;
  device = "/dev/vda";
  swapSize = "32G";  # 2x RAM is common guideline
};
```

Or disable swap entirely:

```nix
keystone.disko = {
  enable = true;
  device = "/dev/vda";
  enableEncryptedSwap = false;
};
```

### Testing Configuration Locally

Build and test before deploying:

```bash
# Build the full system
nix build .#nixosConfigurations.test-server.config.system.build.toplevel

# Check what packages will be installed
nix-store -q --tree ./result | less

# View configuration JSON
nix eval .#nixosConfigurations.test-server.config --json | jq
```

## Reference Commands

```bash
# Build installer ISO
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# Validate configuration
nix build .#nixosConfigurations.test-server.config.system.build.toplevel

# Deploy to target
nixos-anywhere --flake .#test-server root@<target-ip>

# SSH to deployed server
ssh root@<target-ip>
# or
ssh root@test-server.local

# Check system status
systemctl status
zpool status
df -h

# View logs
journalctl -xe
journalctl -u sshd
journalctl -b  # Current boot logs
```

## Timeline Expectations

- **ISO Build**: 2-5 minutes (first time), instant (cached)
- **VM Boot**: 30-60 seconds
- **Configuration Build**: 1-2 minutes (first time), 10-30 seconds (cached)
- **Deployment**: 5-10 minutes
- **First Boot**: 1-2 minutes
- **Verification**: 10-30 seconds

**Total time for first deployment**: ~10-15 minutes
**Total time for subsequent deployments**: ~5-8 minutes

## Getting Help

If you encounter issues:

1. Check this guide's "Common Issues" section
2. Review logs: `journalctl -xe` on target
3. Verify configuration: `nix build .#nixosConfigurations.test-server...`
4. Check networking: `ping`, `ssh -v`
5. Consult NixOS documentation: https://nixos.org/manual/nixos/stable/

## Summary

You've successfully:
- ✅ Created a deployment configuration
- ✅ Added it to your flake
- ✅ Deployed via nixos-anywhere
- ✅ Verified the installation
- ✅ Accessed the server via SSH

Your Keystone server is now running with:
- Full disk encryption (ZFS + LUKS)
- Secure SSH-only access
- mDNS network discovery
- Automated garbage collection
- Server-optimized configuration

This same workflow scales from testing VMs to production deployments!
