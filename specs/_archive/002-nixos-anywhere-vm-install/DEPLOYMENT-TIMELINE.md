# Deployment Timeline Guide

**Feature**: 002-nixos-anywhere-vm-install
**Last Updated**: 2025-10-28

## Overview

This document provides detailed timing expectations for deploying a Keystone server using nixos-anywhere. Understanding these timelines helps set realistic expectations and identify potential issues when deployments take longer than expected.

## Complete Deployment Timeline

### Fresh System (First-Time Deployment)

```
┌─────────────────────────────────────────────────────────────────┐
│ Phase 1: Preparation (5-10 minutes)                             │
├─────────────────────────────────────────────────────────────────┤
│ ├─ ISO Build: 2-5 minutes (first time)                          │
│ ├─ Configuration Validation: 1-2 minutes                        │
│ └─ VM/Hardware Boot from ISO: 30-60 seconds                     │
│                                                                  │
│ Phase 2: Deployment (5-10 minutes)                              │
├─────────────────────────────────────────────────────────────────┤
│ ├─ SSH Connection: 5-10 seconds                                 │
│ ├─ System Closure Build: 2-4 minutes                            │
│ ├─ Disk Partitioning: 10-30 seconds                             │
│ ├─ ZFS Pool Creation: 30-60 seconds                             │
│ ├─ Credstore Setup: 20-40 seconds                               │
│ ├─ System Installation: 2-4 minutes                             │
│ └─ Configuration Apply: 30-60 seconds                           │
│                                                                  │
│ Phase 3: First Boot (1-3 minutes)                               │
├─────────────────────────────────────────────────────────────────┤
│ ├─ System Reboot: 10-20 seconds                                 │
│ ├─ UEFI/BIOS Post: 5-15 seconds                                 │
│ ├─ Bootloader (systemd-boot): 2-5 seconds                       │
│ ├─ Initrd Load: 5-10 seconds                                    │
│ ├─ **User Action**: Credstore Password Entry: 10-60 seconds     │
│ ├─ ZFS Pool Import: 5-10 seconds                                │
│ ├─ Root Filesystem Mount: 2-5 seconds                           │
│ ├─ SystemD Init: 10-20 seconds                                  │
│ ├─ Service Startup (SSH, Avahi, etc.): 10-20 seconds            │
│ └─ System Ready: Total 1-3 minutes                              │
│                                                                  │
│ Phase 4: Verification (30 seconds)                              │
├─────────────────────────────────────────────────────────────────┤
│ └─ Verification Script: 10-30 seconds                           │
│                                                                  │
│ TOTAL TIME: 11-23 minutes                                       │
└─────────────────────────────────────────────────────────────────┘
```

### Subsequent Deployments (Cached)

When deploying the same or similar configuration again:

```
┌─────────────────────────────────────────────────────────────────┐
│ Phase 1: Preparation (1-2 minutes)                              │
├─────────────────────────────────────────────────────────────────┤
│ ├─ ISO Build: instant (cached)                                  │
│ ├─ Configuration Validation: 10-30 seconds (cached)             │
│ └─ VM/Hardware Boot: 30-60 seconds                              │
│                                                                  │
│ Phase 2: Deployment (3-6 minutes)                               │
├─────────────────────────────────────────────────────────────────┤
│ ├─ System Closure Build: 30-60 seconds (mostly cached)          │
│ ├─ Disk Operations: 1-2 minutes                                 │
│ └─ Installation: 1-3 minutes (cached packages)                  │
│                                                                  │
│ Phase 3: First Boot (1-3 minutes)                               │
│ Phase 4: Verification (30 seconds)                              │
│                                                                  │
│ TOTAL TIME: 5-11 minutes                                        │
└─────────────────────────────────────────────────────────────────┘
```

## Detailed Phase Breakdown

### Phase 1: Preparation

#### ISO Build (First Time)
- **Expected**: 2-5 minutes
- **Factors**: CPU speed, available cores, network (for downloads)
- **Cached**: Instant on subsequent builds
- **What's Happening**:
  - Nix evaluates configuration
  - Downloads required packages (if not cached)
  - Builds ISO image
  - Injects SSH keys

**Troubleshooting slow ISO builds**:
- Check internet connection (downloads required)
- Verify sufficient disk space (5GB+ free)
- Consider using binary cache: `nix.settings.substituters`

#### Configuration Validation
- **Expected**: 1-2 minutes (first time), 10-30 seconds (cached)
- **What's Happening**:
  - Nix evaluates configuration
  - Type checks all options
  - Resolves dependencies
  - Builds system closure

**Troubleshooting**:
- Configuration errors appear here
- Check syntax and module imports
- Verify all required options are set

#### Target Boot
- **Expected**: 30-60 seconds
- **VM**: Usually 30-45 seconds
- **Physical Hardware**: 45-90 seconds (depends on POST time)
- **What's Happening**:
  - UEFI/BIOS initialization
  - ISO boot
  - SystemD boots to ISO environment
  - SSH service starts
  - Network configuration

**Troubleshooting slow boots**:
- Check BIOS/UEFI settings (fast boot)
- Verify boot order (ISO/USB first)
- Check network configuration (DHCP delays)

### Phase 2: Deployment

#### System Closure Build
- **Expected**: 2-4 minutes (first time), 30-60 seconds (cached)
- **What's Happening**:
  - nixos-anywhere builds complete system
  - Resolves all dependencies
  - Downloads packages if needed
  - Prepares installation artifacts

**This is the longest step on first deployment**

**Factors affecting build time**:
- Number of packages in configuration
- Binary cache availability
- Network speed (for downloads)
- CPU speed
- Available RAM

#### Disk Partitioning
- **Expected**: 10-30 seconds
- **What's Happening**:
  - Creates GPT partition table
  - Creates EFI System Partition (ESP)
  - Creates ZFS partition

**Troubleshooting**:
- Disk in use errors: ensure disk is not mounted
- Device not found: verify disk path is correct
- Permission errors: check SSH access as root

#### ZFS Pool Creation
- **Expected**: 30-60 seconds
- **What's Happening**:
  - Creates ZFS pool "rpool"
  - Sets up pool features and properties
  - Creates initial datasets
  - Generates encryption keys

**This step is CPU-intensive (key generation)**

#### Credstore Setup
- **Expected**: 20-40 seconds
- **What's Happening**:
  - Creates credstore zvol
  - Formats LUKS volume
  - Mounts credstore
  - Stores ZFS encryption keys

#### System Installation
- **Expected**: 2-4 minutes
- **What's Happening**:
  - Copies Nix store to target
  - Installs bootloader
  - Generates system configuration
  - Sets up systemd services

**Network-dependent**: slow networks = longer install

#### Configuration Apply
- **Expected**: 30-60 seconds
- **What's Happening**:
  - Activates systemd services
  - Applies final configuration
  - Sets up users and permissions
  - Generates SSH host keys

### Phase 3: First Boot

#### System Reboot
- **Expected**: 10-20 seconds
- **What's Happening**:
  - Cleanly unmounts filesystems
  - Exports ZFS pool
  - Closes credstore LUKS device
  - System shutdown and restart

**With fix**: Credstore cleanup prevents hanging

#### UEFI/BIOS Post
- **Expected**: 5-15 seconds (VM), 15-60 seconds (hardware)
- **Hardware Factor**: Varies greatly by system
- **VMs**: Usually very fast
- **Physical**: Can be slow on servers with lots of RAM

#### Bootloader
- **Expected**: 2-5 seconds
- **What's Happening**:
  - systemd-boot menu (may not be visible)
  - Loads kernel
  - Loads initrd

#### Initrd Execution
- **Expected**: 5-10 seconds
- **What's Happening**:
  - Mounts ESP
  - Loads TPM2 modules (if available)
  - Prepares to unlock credstore

#### **🔐 Credstore Password Entry** (User Action Required)
- **Expected**: 10-60 seconds (depends on user)
- **VMs**: Always requires password (no TPM2)
- **Hardware with TPM2**: Automatic unlock (no password)
- **What's Happening**:
  - System waits for LUKS passphrase
  - User types password at console
  - LUKS unlocks credstore volume

**This is a BLOCKING step - system will wait indefinitely**

**Tips**:
- Use strong but memorable passphrase
- Store passphrase securely
- Test password entry in VM before production
- Consider hardware TPM2 for automatic unlock

#### ZFS Pool Import
- **Expected**: 5-10 seconds
- **What's Happening**:
  - Imports rpool
  - Loads ZFS encryption keys from credstore
  - Mounts encrypted datasets

#### Root Filesystem Mount
- **Expected**: 2-5 seconds
- **What's Happening**:
  - Mounts root (rpool/crypt/root)
  - Mounts /nix (rpool/crypt/nix)
  - Mounts /var (rpool/crypt/var)
  - Mounts /home (rpool/crypt/home)
  - Pivots to real root

#### SystemD Initialization
- **Expected**: 10-20 seconds
- **What's Happening**:
  - SystemD starts
  - Mounts remaining filesystems
  - Starts system services

#### Service Startup
- **Expected**: 10-20 seconds
- **What's Happening**:
  - SSH daemon starts
  - Avahi (mDNS) starts
  - Firewall activates
  - Network configuration applies
  - System reaches multi-user.target

**System is now ready for SSH access**

### Phase 4: Verification

- **Expected**: 10-30 seconds
- **What's Happening**:
  - SSH connectivity check
  - Hostname verification
  - Firewall rules check
  - ZFS pool status
  - Encryption verification

## Performance Optimization

### For Faster Deployments

1. **Use Binary Cache**:
   ```nix
   nix.settings.substituters = [
     "https://cache.nixos.org"
   ];
   ```

2. **Optimize Build Settings**:
   ```nix
   nix.settings = {
     max-jobs = "auto";  # Use all available cores
     cores = 0;          # Use all cores per job
   };
   ```

3. **Minimize Package Set**:
   - Only include necessary packages
   - Use server module as-is (already optimized)
   - Avoid heavy desktop packages

4. **Local Binary Cache** (for multiple deployments):
   - Set up a local cache server
   - Share cache across team
   - Drastically reduces build times

### For Faster Boots

1. **BIOS/UEFI Settings**:
   - Enable fast boot
   - Disable unnecessary hardware checks
   - Set boot timeout to minimum

2. **SystemD Optimization**:
   ```nix
   systemd.services = {
     # Disable unnecessary services
   };
   ```

3. **ZFS Tuning**:
   ```nix
   boot.zfs.forceImportAll = false;  # Don't import all pools
   ```

## Monitoring Deployment Progress

### During Deployment

Watch for these progress indicators:

```
>>> Connecting to target system...        # SSH connection
>>> Building system closure...            # System build
building '/nix/store/...drv'...           # Package downloads/builds
>>> Formatting disk...                     # Disk operations
>>> Creating ZFS pool...                   # ZFS setup
>>> Installing system...                   # System install
copying path '/nix/store/...'             # File copies
>>> Rebooting system...                    # Cleanup and reboot
```

### During First Boot

Console output shows:

```
[    0.000000] Linux version 6.12...     # Kernel loading
[    2.345678] zfs: ...                   # ZFS modules
Please enter passphrase for disk...       # PASSWORD PROMPT
[    5.123456] systemd[1]: ...            # SystemD init
NixOS 24.11 (x86_64) - tty1               # Login prompt
```

## Troubleshooting Slow Deployments

### Deployment Hangs at "Building system closure"
- **Cause**: Downloading packages or building from source
- **Solution**: Check network connection, wait for completion
- **Prevention**: Pre-populate binary cache

### Deployment Hangs at "Installing system"
- **Cause**: Network issues during file copy
- **Solution**: Check SSH connection stability
- **Prevention**: Use wired connection, not WiFi

### Deployment Hangs at "Rebooting system"
- **Cause**: Pool export failing (credstore still open)
- **Solution**: This is fixed in current version
- **Verification**: Check for credstore cleanup messages

### Boot Hangs at Password Prompt
- **Cause**: Waiting for user input
- **Solution**: Enter the credstore password
- **Not a hang**: System is waiting for you!

### Boot Hangs After Password
- **Cause**: ZFS import or mount issues
- **Solution**: Check console for error messages
- **Recovery**: Boot from ISO and inspect pool

## Expected Timeline Summary

| Scenario | First Time | Cached | With Binary Cache |
|----------|-----------|--------|-------------------|
| **Development VM** | 10-15 min | 5-8 min | 6-10 min |
| **Production Server** | 15-25 min | 8-12 min | 10-15 min |
| **High-spec Hardware** | 8-12 min | 4-6 min | 5-8 min |
| **Low-spec Hardware** | 20-30 min | 10-15 min | 12-18 min |

## When to Be Concerned

| Phase | Normal | Concerning | Investigate |
|-------|--------|------------|-------------|
| ISO Build | < 5 min | 5-10 min | > 10 min |
| Config Build | < 2 min | 2-5 min | > 5 min |
| System Closure | < 4 min | 4-8 min | > 8 min |
| Disk Format | < 30 sec | 30-60 sec | > 60 sec |
| ZFS Create | < 60 sec | 1-2 min | > 2 min |
| Installation | < 4 min | 4-8 min | > 8 min |
| First Boot | < 3 min | 3-5 min | > 5 min |
| Password Wait | Any | - | Never hangs |
| Post-Password | < 30 sec | 30-60 sec | > 60 sec |

## Real-World Examples

### Example 1: Development Laptop
- **Hardware**: i7-10700K, 32GB RAM, NVMe SSD, QEMU VM
- **First Deployment**: 11 minutes
- **Second Deployment**: 6 minutes
- **Notes**: Binary cache enabled, fast internet

### Example 2: Cloud VPS
- **Hardware**: 4 vCPU, 8GB RAM, 80GB SSD
- **First Deployment**: 18 minutes
- **Second Deployment**: 9 minutes
- **Notes**: Network latency to binary cache

### Example 3: Home Server
- **Hardware**: Raspberry Pi 4, 8GB RAM, USB SSD
- **First Deployment**: 45 minutes
- **Second Deployment**: 22 minutes
- **Notes**: ARM architecture, limited cache hits

### Example 4: Workstation (Bare Metal)
- **Hardware**: AMD Ryzen 9 5950X, 64GB RAM, NVMe RAID
- **First Deployment**: 8 minutes
- **Second Deployment**: 4 minutes
- **Notes**: Local binary cache, very fast hardware

## Additional Resources

- **NixOS Manual**: https://nixos.org/manual/nixos/stable/
- **nixos-anywhere Docs**: https://github.com/nix-community/nixos-anywhere
- **ZFS Best Practices**: https://openzfs.github.io/openzfs-docs/
- **SystemD Boot**: https://www.freedesktop.org/wiki/Software/systemd/

## Conclusion

Understanding deployment timelines helps you:
- Set realistic expectations
- Identify performance issues early
- Optimize your deployment workflow
- Troubleshoot problems effectively

Most deployments complete within 10-15 minutes on modern hardware with good network connectivity. If your deployment takes significantly longer, use this guide to identify the bottleneck and optimize accordingly.
