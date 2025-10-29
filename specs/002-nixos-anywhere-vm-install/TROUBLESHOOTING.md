# Troubleshooting Guide

**Feature**: 002-nixos-anywhere-vm-install
**Last Updated**: 2025-10-28

## Overview

This guide provides solutions to common problems encountered when deploying Keystone servers using nixos-anywhere. Issues are organized by deployment phase and include diagnostic steps and solutions.

## Quick Diagnostic Checklist

Before diving into specific issues, run through this quick checklist:

- [ ] Can you ping the target system?
- [ ] Can you SSH to the target manually?
- [ ] Does the configuration build locally? (`nix build .#nixosConfigurations.NAME...`)
- [ ] Is the target booted from the Keystone ISO?
- [ ] Is there sufficient disk space (minimum 20GB)?
- [ ] Is the disk device path correct in configuration?
- [ ] Are your SSH keys properly configured?

## Table of Contents

1. [Pre-Deployment Issues](#pre-deployment-issues)
2. [Configuration Issues](#configuration-issues)
3. [Network and Connectivity Issues](#network-and-connectivity-issues)
4. [Deployment Failures](#deployment-failures)
5. [Boot and Post-Deployment Issues](#boot-and-post-deployment-issues)
6. [ZFS and Encryption Issues](#zfs-and-encryption-issues)
7. [Performance Issues](#performance-issues)
8. [Recovery Procedures](#recovery-procedures)

---

## Pre-Deployment Issues

### Issue: ISO Build Fails

**Symptoms**:
```
error: builder for '/nix/store/...iso.drv' failed
```

**Diagnostic Steps**:
```bash
# Check Nix installation
nix --version

# Verify flake is valid
nix flake check

# Check disk space
df -h /nix
```

**Common Causes**:

1. **Insufficient disk space**
   - **Solution**: Free up space in /nix/store
   ```bash
   nix-collect-garbage -d
   sudo nix-collect-garbage -d
   ```

2. **Network issues downloading packages**
   - **Solution**: Check internet connection
   - **Solution**: Try binary cache manually:
   ```bash
   nix-store --verify --check-contents
   ```

3. **Flake syntax errors**
   - **Solution**: Check flake.nix syntax
   - **Solution**: Run `nix flake show` to validate

**Prevention**:
- Keep at least 10GB free in /nix/store
- Regularly run garbage collection
- Test flake syntax before building ISOs

---

### Issue: Configuration Validation Fails

**Symptoms**:
```
error: attribute 'nixosConfigurations.test-server' missing
error: infinite recursion encountered
error: undefined variable 'config'
```

**Diagnostic Steps**:
```bash
# Test configuration evaluation
nix eval .#nixosConfigurations.test-server.config.system.name

# Check for syntax errors
nix-instantiate --parse flake.nix

# Verify module imports
nix flake show
```

**Common Causes**:

1. **Missing module imports**
   - **Solution**: Ensure all required modules are imported in flake.nix
   ```nix
   modules = [
     disko.nixosModules.disko  # Required!
     ./modules/server
     ./modules/disko-single-disk-root
     ./your-config.nix
   ];
   ```

2. **Typo in configuration name**
   - **Solution**: Verify exact name in flake.nix matches command

3. **Missing required options**
   - **Solution**: Check error message for which option is missing
   - **Common missing options**:
     - `networking.hostName`
     - `keystone.disko.device`
     - `users.users.root.openssh.authorizedKeys.keys`

**Prevention**:
- Use `nix build` to validate before deployment
- Keep configurations in version control
- Use examples as templates

---

## Configuration Issues

### Issue: "disk device not found" during deployment

**Symptoms**:
```
error: disk /dev/vda not found
error: cannot stat '/dev/sda': No such file or directory
```

**Diagnostic Steps**:
```bash
# SSH to target and list available disks
ssh root@target-ip "lsblk"
ssh root@target-ip "ls -l /dev/disk/by-id/"
```

**Solution**:

1. **Identify correct disk device**:
   ```bash
   # On target (booted from ISO)
   lsblk -d -o NAME,SIZE,TYPE
   ```

2. **Update configuration** with correct device:
   ```nix
   keystone.disko.device = "/dev/vda";  # For QEMU VMs
   # OR
   keystone.disko.device = "/dev/sda";  # For VirtualBox
   # OR (recommended for production)
   keystone.disko.device = "/dev/disk/by-id/nvme-Samsung...";
   ```

**Common Device Paths**:
- QEMU/KVM VMs: `/dev/vda`
- VirtualBox VMs: `/dev/sda`
- Physical NVMe: `/dev/disk/by-id/nvme-...`
- Physical SATA: `/dev/disk/by-id/ata-...`

**Prevention**:
- Always verify disk device on target before deployment
- Use `/dev/disk/by-id/` paths for production
- Document device paths in configuration comments

---

### Issue: SSH Access Fails After Deployment

**Symptoms**:
```
Permission denied (publickey)
Connection refused
ssh: connect to host X.X.X.X port 22: No route to host
```

**Diagnostic Steps**:
```bash
# Test SSH with verbose output
ssh -vvv root@target-ip

# Check if SSH keys are correct
cat ~/.ssh/id_ed25519.pub

# Verify target is up
ping target-ip
```

**Common Causes**:

1. **SSH keys not added to configuration**
   - **Solution**: Add your public key:
   ```nix
   users.users.root.openssh.authorizedKeys.keys = [
     "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@host"
   ];
   ```

2. **Wrong SSH key format**
   - **Problem**: Key has line breaks or is truncated
   - **Solution**: Ensure key is single line, complete string

3. **Firewall blocking SSH**
   - **Diagnostic**: Check from target console
   ```bash
   nft list ruleset | grep 22
   systemctl status firewall
   ```
   - **Solution**: The server module should allow SSH by default

4. **Network configuration issues**
   - **Solution**: Check target's network configuration
   - **Solution**: Verify routing and gateway settings

**Prevention**:
- Always test SSH keys before deployment
- Keep backup of SSH private keys
- Document which key is used for which system

---

## Network and Connectivity Issues

### Issue: Target Not Reachable

**Symptoms**:
```
ssh: connect to host X.X.X.X port 22: No route to host
ping: X.X.X.X: Host is unreachable
```

**Diagnostic Steps**:
```bash
# Check local network
ip addr
ip route

# Test connectivity
ping target-ip
traceroute target-ip

# Check if target is up (look at console/VM window)
```

**Common Causes**:

1. **Wrong IP address**
   - **Solution**: Verify IP on target console
   - **VM**: Check VM configuration for network adapter

2. **Network not bridged (VMs)**
   - **Solution**: Change VM network from NAT to Bridged
   - **Alternative**: Use port forwarding

3. **Firewall on development machine**
   - **Solution**: Allow outbound SSH
   ```bash
   # Check firewall rules
   sudo ufw status
   sudo iptables -L
   ```

4. **Target not on same network**
   - **Solution**: Ensure both systems can communicate
   - **Solution**: Check network segmentation/VLANs

**Prevention**:
- Use static IPs or DHCP reservations
- Document network topology
- Test connectivity before deploying

---

### Issue: Deployment Hangs "Building system closure"

**Symptoms**:
```
>>> Building system closure...
building '/nix/store/...drv'...
[Hangs here for extended period]
```

**Diagnostic Steps**:
```bash
# Check if actually hanging or just slow
# Watch nix build progress in another terminal
nix build .#nixosConfigurations.NAME.config.system.build.toplevel --print-build-logs

# Check network activity
nethogs  # or iftop, bmon
```

**Common Causes**:

1. **Downloading large packages**
   - **Not actually hung**: Just slow network
   - **Solution**: Wait for download to complete
   - **Monitor**: Watch network usage

2. **Building from source**
   - **Cause**: Package not in binary cache
   - **Solution**: Wait for build (can take time)
   - **Prevention**: Use binary cache:
   ```nix
   nix.settings.substituters = [
     "https://cache.nixos.org"
   ];
   ```

3. **Out of memory**
   - **Symptom**: Build process killed
   - **Solution**: Increase RAM or swap
   - **Solution**: Reduce concurrent builds:
   ```nix
   nix.settings.max-jobs = 2;
   ```

**Prevention**:
- Pre-populate binary cache
- Use local cache server for team deployments
- Test configuration builds locally first

---

## Deployment Failures

### Issue: "ZFS modules not available"

**Symptoms**:
```
error: cannot load zfs modules
modprobe: FATAL: Module zfs not found
The following modules could not be loaded: zfs
```

**Diagnostic Steps**:
```bash
# Check if ZFS is available in ISO
ssh root@target-ip "modprobe zfs && lsmod | grep zfs"

# Check ISO kernel version
ssh root@target-ip "uname -r"
```

**Common Causes**:

1. **Kernel/ZFS version mismatch**
   - **Solution**: Rebuild ISO with compatible kernel
   - **Fix**: Update modules/iso-installer.nix:
   ```nix
   boot.kernelPackages = pkgs.linuxPackages_6_12;
   ```

2. **Using old ISO**
   - **Solution**: Rebuild ISO with latest configuration
   ```bash
   ./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
   ```

**Prevention**:
- Always use freshly built ISO
- Document ISO kernel version
- Test ZFS availability before deployment

---

### Issue: Disk Formatting Fails

**Symptoms**:
```
error: cannot create partition table
error: device or resource busy
wipefs: error: /dev/vda: probing initialization failed
```

**Diagnostic Steps**:
```bash
# Check if disk is in use
ssh root@target-ip "lsblk"
ssh root@target-ip "mount | grep vda"

# Check for existing partitions
ssh root@target-ip "fdisk -l /dev/vda"
```

**Common Causes**:

1. **Disk already mounted**
   - **Solution**: Unmount before deployment
   ```bash
   umount /mnt/*
   swapoff -a
   ```

2. **Existing ZFS pool**
   - **Solution**: Export pool first
   ```bash
   zpool export -a
   ```

3. **Disk has partition table**
   - **Solution**: nixos-anywhere should wipe automatically
   - **Manual fix**:
   ```bash
   wipefs -a /dev/vda
   ```

**Prevention**:
- Start with clean disk
- Document disk preparation steps
- Use `--hard-reset` flag in test script

---

### Issue: Deployment Hangs at Pool Export

**Symptoms**:
```
>>> Rebooting system...
[Hangs indefinitely]
```

**This Issue is FIXED in Current Version**

**Diagnostic Steps**:
```bash
# Check if credstore cleanup is in script
grep "cryptsetup close credstore" bin/test-deployment

# Verify credstore cleanup in deploy-vm.sh
grep "cryptsetup" scripts/deploy-vm.sh
```

**Explanation**:
- Old versions hung because credstore LUKS device remained open
- ZFS cannot export pool when zvol devices are in use
- **Fix**: Close credstore before exporting pool

**If Using Old Version**:
1. Interrupt deployment (Ctrl+C)
2. Manually close credstore:
   ```bash
   ssh root@target-ip "cryptsetup close credstore && zpool export -a && reboot"
   ```
3. Update to latest version with fix

**Prevention**:
- Use latest version of deployment scripts
- Test with `./bin/test-deployment --hard-reset`

---

## Boot and Post-Deployment Issues

### Issue: System Hangs at Password Prompt

**THIS IS NOT A BUG - User Action Required**

**Symptoms**:
- Console shows: "Please enter passphrase for disk..."
- System appears to be waiting

**Explanation**:
- VMs don't have TPM2, so manual password is required
- This is **expected behavior** for encrypted storage
- System is waiting for you to enter password

**Solution**:
1. Look at VM console window or physical system screen
2. Type a password (any password for first boot)
3. Press Enter
4. System will continue booting

**Remember this password**:
- You'll need it on every boot
- Store in password manager
- Document in secure location

**Prevention**:
- Expect this prompt on VMs
- For production with TPM2: automatic unlock
- Test password entry during initial deployment

---

### Issue: System Won't Boot After Deployment

**Symptoms**:
- System reboots but doesn't reach login prompt
- Stuck at GRUB/bootloader
- Kernel panic

**Diagnostic Steps**:
```bash
# Boot from ISO again
# Check ZFS pool
zpool import -N
zpool status

# Check boot configuration
ls /mnt/boot/EFI/
ls /mnt/boot/loader/
```

**Common Causes**:

1. **Boot partition not mounted**
   - **Solution**: Reinstall bootloader
   ```bash
   nixos-install --root /mnt
   ```

2. **ZFS pool not exported cleanly**
   - **Solution**: Force import and re-export
   ```bash
   zpool import -f rpool
   zpool scrub rpool
   zpool export rpool
   ```

3. **Corrupted boot files**
   - **Solution**: Redeploy with fresh installation

**Prevention**:
- Use credstore cleanup fix
- Don't interrupt deployment during boot setup
- Verify boot configuration before deployment

---

### Issue: Can't SSH After First Boot

**Symptoms**:
```
ssh: connect to host X.X.X.X port 22: Connection refused
ssh: connect to host X.X.X.X port 22: Connection timed out
```

**Diagnostic Steps**:
1. Check if system booted successfully (look at console)
2. Verify network configuration
3. Check SSH service status (from console):
   ```bash
   systemctl status sshd
   journalctl -u sshd
   ```

**Common Causes**:

1. **SSH service not started**
   - **From console**: `systemctl start sshd`
   - **Check logs**: `journalctl -u sshd -n 50`

2. **Wrong IP address**
   - **Solution**: Check actual IP on target
   ```bash
   ip addr show
   ```

3. **Firewall blocking (shouldn't happen with server module)**
   - **From console**: `nft list ruleset`
   - **Fix**: `nft add rule inet filter input tcp dport 22 accept`

4. **System still booting**
   - **Solution**: Wait another minute
   - **Check**: `systemctl is-system-running`

**Prevention**:
- Wait 2-3 minutes after reboot before attempting SSH
- Verify deployment with verification script
- Check system logs after first successful SSH

---

## ZFS and Encryption Issues

### Issue: ZFS Pool Not Imported

**Symptoms**:
```
cannot open 'rpool': no such pool
zfs list: cannot open 'rpool/crypt': dataset does not exist
```

**Diagnostic Steps**:
```bash
# Check available pools
zpool import

# Check pool status
zpool status rpool

# Check for import errors
journalctl | grep zfs
```

**Common Causes**:

1. **Pool needs manual import**
   - **Solution**:
   ```bash
   zpool import -N rpool
   zpool import rpool
   ```

2. **Credstore not unlocked**
   - **Solution**: Unlock credstore first, then import pool

3. **Pool is degraded**
   - **Check**: `zpool status -v rpool`
   - **Solution**: Investigate disk issues

**Prevention**:
- Verify credstore unlock procedure
- Test pool import after deployment
- Monitor pool health regularly

---

### Issue: Cannot Access Encrypted Datasets

**Symptoms**:
```
cannot mount '/': Input/output error
Key load error: Key material not available
```

**Diagnostic Steps**:
```bash
# Check encryption status
zfs get encryption rpool/crypt

# Check key status
zfs get keystatus rpool/crypt

# Check credstore
ls -l /etc/credstore/
```

**Common Causes**:

1. **Encryption key not loaded**
   - **Solution**:
   ```bash
   zfs load-key -L file:///etc/credstore/zfs-rpool-crypt-enckey rpool/crypt
   zfs mount -a
   ```

2. **Credstore not mounted**
   - **Solution**: Unlock and mount credstore first

3. **Key file missing or corrupt**
   - **Recovery**: May need to restore from backup
   - **Prevention**: Back up encryption keys securely

**Prevention**:
- Test encryption setup during deployment
- Document key management procedures
- Regular backup of credstore

---

### Issue: "pool export failed" Error

**Symptoms**:
```
cannot export 'rpool': pool is busy
```

**Diagnostic Steps**:
```bash
# Check what's using the pool
lsof | grep rpool
fuser -vm /mnt

# Check for open LUKS devices
dmsetup ls
cryptsetup status credstore
```

**Common Causes**:

1. **Credstore still open** (should be fixed in current version)
   - **Solution**:
   ```bash
   cryptsetup close credstore
   zpool export rpool
   ```

2. **Datasets still mounted**
   - **Solution**:
   ```bash
   umount -R /mnt
   zpool export rpool
   ```

3. **ZFS snapshots held open**
   - **Solution**:
   ```bash
   zfs list -t snapshot
   # Delete if safe
   ```

**Prevention**:
- Use deployment wrapper with credstore cleanup
- Follow proper shutdown procedure
- Don't interrupt reboot process

---

## Performance Issues

### Issue: Deployment Takes Too Long

**Symptoms**:
- Deployment exceeds 20 minutes
- "Building system closure" takes > 10 minutes
- Network copy very slow

**Diagnostic Steps**:
```bash
# Check network speed
iperf3 -s  # on target
iperf3 -c target-ip  # on dev machine

# Check binary cache
nix-store --verify --check-contents

# Monitor build progress
nix build --print-build-logs
```

**Common Causes**:

1. **Slow network**
   - **Solution**: Use wired connection
   - **Solution**: Deploy from same network as target

2. **Building from source**
   - **Solution**: Enable binary cache
   - **Solution**: Use local cache server

3. **Low-spec hardware**
   - **Expected**: Slower on ARM, older CPUs
   - **Solution**: Be patient, or upgrade hardware

4. **Downloading large packages**
   - **Solution**: Pre-download on fast connection
   - **Solution**: Use mirror closer to your location

**Prevention**:
- Configure binary cache
- Test deployment in VM first
- Use fast network connections

---

### Issue: System Slow After Deployment

**Symptoms**:
- SSH commands slow to respond
- High CPU usage
- System feels sluggish

**Diagnostic Steps**:
```bash
# Check system load
top
htop

# Check disk I/O
iotop

# Check ZFS ARC usage
cat /proc/spl/kstat/zfs/arcstats

# Check for errors
journalctl -p err -n 50
```

**Common Causes**:

1. **ZFS scrub running**
   - **Check**: `zpool status`
   - **Solution**: Wait for scrub to complete
   - **Disable**: `zpool scrub -s rpool`

2. **Insufficient RAM**
   - **ZFS wants lots of RAM**
   - **Solution**: Add more RAM or tune ARC
   ```nix
   boot.kernelParams = ["zfs.zfs_arc_max=4294967296"];  # 4GB
   ```

3. **Swap thrashing**
   - **Check**: `free -h`
   - **Solution**: Add more swap or RAM

**Prevention**:
- Size system appropriately (16GB+ RAM recommended)
- Tune ZFS for your workload
- Monitor system resources

---

## Recovery Procedures

### Emergency Access via ISO

If you can't SSH to the deployed system:

1. **Boot from Keystone ISO**

2. **Import ZFS pool**:
   ```bash
   zpool import -f rpool
   ```

3. **Unlock credstore**:
   ```bash
   cryptsetup open /dev/zvol/rpool/credstore-enc credstore
   mount /dev/mapper/credstore /mnt
   ```

4. **Load ZFS keys**:
   ```bash
   zfs load-key -L file:///mnt/zfs-rpool-crypt-enckey rpool/crypt
   ```

5. **Mount filesystems**:
   ```bash
   mount -t zfs rpool/crypt/root /mnt
   mount -t zfs rpool/crypt/nix /mnt/nix
   mount -t zfs rpool/crypt/var /mnt/var
   mount -t zfs rpool/crypt/home /mnt/home
   mount /dev/vda1 /mnt/boot
   ```

6. **Chroot and fix**:
   ```bash
   nixos-enter --root /mnt
   # Fix configuration
   # Rebuild
   nixos-rebuild switch
   ```

---

### Recovering from Failed Deployment

If deployment fails partway through:

1. **Don't panic** - nixos-anywhere is mostly idempotent

2. **Check what failed**:
   - Read error messages carefully
   - Check logs on target

3. **Fix the issue**:
   - Correct configuration
   - Fix network
   - Free up disk space

4. **Try again**:
   ```bash
   # Clean start recommended
   ./bin/test-deployment --hard-reset

   # Or redeploy to same system
   nixos-anywhere --flake .#config root@target-ip
   ```

5. **If repeatedly failing**:
   - Test configuration build locally
   - Verify target hardware compatibility
   - Check for hardware issues (bad disk, RAM)

---

### Complete System Rebuild

If system is completely broken:

1. **Backup important data** (if possible)

2. **Boot from ISO**

3. **Wipe disk completely**:
   ```bash
   wipefs -a /dev/vda
   sgdisk --zap-all /dev/vda
   ```

4. **Redeploy fresh**:
   ```bash
   nixos-anywhere --flake .#config root@target-ip
   ```

---

## Getting Help

If you're still stuck after trying these solutions:

1. **Gather information**:
   - Exact error messages
   - System logs (`journalctl -xe`)
   - Configuration files
   - Steps to reproduce

2. **Check resources**:
   - NixOS Manual: https://nixos.org/manual/nixos/stable/
   - NixOS Discourse: https://discourse.nixos.org/
   - nixos-anywhere Issues: https://github.com/nix-community/nixos-anywhere/issues

3. **Ask for help**:
   - Include all gathered information
   - Be specific about what you tried
   - Provide minimal reproduction case

---

## Prevention Best Practices

Avoid issues before they happen:

1. **Test in VMs first**
2. **Keep backups of working configurations**
3. **Use version control (Git)**
4. **Document your setup**
5. **Regular system updates**
6. **Monitor system health**
7. **Test recovery procedures**
8. **Keep ISO build updated**
9. **Verify prerequisites before deployment**
10. **Read error messages carefully**

---

## Conclusion

Most deployment issues are solvable with careful diagnosis and the right tools. This guide covers the most common problems, but every deployment can be unique. When in doubt:

1. Read the error message carefully
2. Check logs
3. Test in isolation
4. Ask for help with detailed information

Good luck with your deployments!
