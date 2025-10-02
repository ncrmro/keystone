# Keystone Secure Installation Guide

Complete secure installation flow with TPM2, Secure Boot, and LUKS encryption for maximum security infrastructure.

## Overview

This guide covers the advanced secure installation process for Keystone, which provides enterprise-grade security through the integration of:

- **TPM2**: Hardware-based cryptographic key storage and attestation
- **Secure Boot**: Verified boot chain from firmware to kernel
- **LUKS**: Full disk encryption with multiple unlock methods

⚠️ **Important**: This is a multi-stage installation process that requires several reboots and password entries. The system will automatically progress through security stages after initial setup.

## Security Model

Keystone's security architecture combines multiple layers:

1. **Secure Boot** ensures only trusted bootloaders and kernels can run
2. **TPM2** provides hardware-based key storage and system attestation  
3. **LUKS** encrypts all data at rest with multiple unlock methods
4. **Measured Boot** records system state in TPM PCRs for attestation

### Unlock Methods

Your encrypted system can be unlocked using:
- **Password**: Manual password entry (always available)
- **TPM2**: Automatic unlock when system state is verified
- **Recovery Key**: Generated during installation for emergency access
- **Future**: FIDO2 keys and remote Tailscale unlock (planned features)

## Prerequisites

### Hardware Requirements

- **TPM2 chip**: Version 2.0 or later (check with `systemd-cryptenroll --tpm2-device=list`)
- **UEFI firmware**: Modern UEFI with Secure Boot support
- **Network connectivity**: Required for nixos-anywhere installation

### Pre-Installation Setup

⚠️ **CRITICAL**: You must configure your system firmware before starting the installation.

#### Step 1: Access UEFI/BIOS Setup

1. Boot into your system's UEFI/BIOS setup (usually F2, F12, or DEL during boot)
2. Navigate to the Security or Boot settings

#### Step 2: Configure Secure Boot

1. **Set Secure Boot to "Setup Mode" or "Custom Mode"**
   - This allows enrollment of custom keys
   - May be labeled as "Clear Secure Boot Keys" or "Custom Mode"
2. **Clear existing Secure Boot keys** if present
3. **Enable UEFI boot mode** (disable Legacy/CSM if enabled)

#### Step 3: Enable TPM2

1. **Enable TPM2/fTPM** in firmware settings
2. **Set TPM to version 2.0** if multiple versions are available
3. **Clear TPM** if previously used (optional but recommended)

#### Step 4: Verify Settings

- Secure Boot: Disabled/Setup Mode
- TPM2: Enabled and detected
- Boot Mode: UEFI only

Save settings and exit UEFI setup.

## Installation Process Overview

The installation consists of 4 automated stages:

```
Stage 1: Initial Installation
    ↓ (Reboot)
Stage 2: Key Generation  
    ↓ (Reboot + Manual UEFI setup)
Stage 3: Secure Boot Enrollment
    ↓ (Reboot)
Stage 4: TPM2 Integration
    ↓ (Complete)
```

**Expected Timeline**: 30-45 minutes total
**Password Entries**: 3-5 times during the process
**Reboots**: 3-4 automatic reboots

## Stage 1: Initial Installation

### Boot from Keystone ISO

1. Boot target machine from Keystone USB installer
2. Wait for network auto-configuration
3. Get the IP address: `ip addr show`

### Deploy with nixos-anywhere

From your local machine:

```bash
# Ensure your flake includes Keystone secure boot configuration
nixos-anywhere --flake .#your-secure-config root@<installer-ip>
```

### What Happens

- Disko partitions and encrypts the disk with LUKS
- Base NixOS system is installed with lanzaboote (Secure Boot support)
- System configured for TPM2 integration
- **First manual password entry**: LUKS encryption password

### Expected Output

```
Installing system...
Setting up LUKS encryption...
Installing bootloader with Secure Boot support...
Installation complete. System will reboot...
```

## Stage 2: First Boot and Key Generation

### Manual LUKS Unlock

When the system reboots, you'll see:

```
Enter passphrase for /dev/disk/by-uuid/[uuid]:
```

**Second manual password entry**: Enter your LUKS password to boot.

### Automatic Key Generation

Once booted, systemd services automatically:

1. Generate Secure Boot keys (DB, KEK, PK)
2. Sign the bootloader and kernel with new keys
3. Prepare for Secure Boot enrollment
4. Initialize TPM2 for future use

### Monitor Progress

```bash
# Check key generation status
systemctl status keystone-secureboot-keygen

# View logs
journalctl -u keystone-secureboot-keygen -f
```

### Expected Output

```
● keystone-secureboot-keygen.service - Generate Secure Boot Keys
   Status: "Generating Secure Boot certificates..."
   Status: "Signing bootloader and kernel..."
   Status: "Preparing for enrollment..."
   Status: "Key generation complete. Reboot required."
```

## Stage 3: Secure Boot Enrollment

### Automatic Reboot

The system will automatically reboot when key generation is complete.

### Manual UEFI Key Enrollment

1. **Third manual password entry**: Enter LUKS password at boot prompt
2. System will prompt: "Press F12 to enter UEFI setup for Secure Boot enrollment"
3. Enter UEFI setup and navigate to Secure Boot settings
4. **Enroll new keys**:
   - Load DB (Database) key from EFI partition
   - Load KEK (Key Exchange Key) 
   - Load PK (Platform Key) - this enables Secure Boot
5. **Save and exit** UEFI setup

### Key Enrollment Details

Keys are located at:
- DB: `/boot/EFI/secureboot/db.esl`
- KEK: `/boot/EFI/secureboot/KEK.esl` 
- PK: `/boot/EFI/secureboot/PK.esl`

### Verification

After enrollment, verify Secure Boot is active:

```bash
# Should show "Secure Boot: enabled"
bootctl status
```

## Stage 4: TPM2 Integration

### Automatic TPM2 Setup

On the next boot, the system automatically:

1. Measures boot state into TPM PCRs
2. Enrolls LUKS key with TPM2
3. Configures automatic unlock policy
4. Tests TPM2 unlock capability

### TPM2 Policy Configuration

The system creates a PCR policy that allows automatic unlock when:
- Secure Boot is enabled and verified
- Bootloader and kernel signatures are valid
- System configuration hasn't changed unexpectedly

### Verification

```bash
# Check TPM2 enrollment status
systemd-cryptenroll /dev/nvme0n1p2

# Verify TPM2 device
systemd-cryptenroll --tpm2-device=list

# Test unlock capability  
systemctl status systemd-cryptsetup@luks\x2d[uuid].service
```

## Post-Installation Configuration

### Generate Recovery Key

⚠️ **CRITICAL**: Generate and securely store a recovery key:

```bash
# Generate recovery key
systemd-cryptenroll --recovery-key /dev/nvme0n1p2

# Store the output in a secure location!
```

### Additional Disk Setup

For additional disks, the system automatically:

1. Creates ZFS pools on unmanaged disks
2. Encrypts additional LUKS devices
3. Enrolls them with the same TPM2 policy
4. Reuses encryption keys from root disk

### System Health Check

```bash
# Verify all components
keystone-security-check

# Check ZFS pools
zpool list
zfs list

# Verify TPM2 functionality
tpm2_pcrread
```

## Verification and Testing

### Complete Security Verification

```bash
# 1. Verify Secure Boot
bootctl status | grep "Secure Boot"

# 2. Verify TPM2 integration
systemd-cryptenroll /dev/nvme0n1p2 | grep tpm2

# 3. Test boot process
systemctl reboot
# Should boot without password prompt
```

### LUKS Unlock Method Testing

Test each unlock method:

1. **TPM2 unlock**: Normal boot (no password)
2. **Password unlock**: Boot with TPM disabled in UEFI  
3. **Recovery key**: Use generated recovery key

## Troubleshooting

### Common Issues

#### TPM2 Not Detected

```bash
# Check TPM2 presence
ls /dev/tpm*
systemd-cryptenroll --tpm2-device=list

# If not found, check UEFI settings
```

#### Secure Boot Keys Not Enrolling

1. Verify Secure Boot is in "Setup Mode"
2. Clear all existing keys first
3. Check key file locations in `/boot/EFI/secureboot/`
4. Try manual enrollment via UEFI interface

#### System Won't Boot After Secure Boot

1. Boot from Keystone ISO
2. Mount encrypted root: `cryptsetup open /dev/nvme0n1p2 luks-root`
3. Mount system: `mount /dev/mapper/luks-root /mnt`
4. Chroot and investigate: `nixos-enter --root /mnt`

#### TPM2 Unlock Failing

```bash
# Check PCR values
tpm2_pcrread

# Re-enroll with current state
systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2
systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p2
```

### Recovery Procedures

#### Emergency Access

1. **Boot from Keystone ISO**
2. **Mount encrypted system**:
   ```bash
   cryptsetup open /dev/nvme0n1p2 luks-root
   mount /dev/mapper/luks-root /mnt
   mount /dev/nvme0n1p1 /mnt/boot
   ```
3. **Chroot for repairs**:
   ```bash
   nixos-enter --root /mnt
   ```

#### Reset TPM2 Integration

```bash
# Remove TPM2 enrollment
systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2

# Re-configure
systemctl restart keystone-tpm2-setup
```

## Advanced Configuration

### Custom PCR Policies

For stricter security, customize PCR selection:

```nix
# In your NixOS configuration
boot.initrd.luks.devices."luks-root".tpm2 = {
  enable = true;
  pcrList = [ 0 1 2 3 4 5 6 7 ];  # Customize as needed
};
```

### Future Features

The following unlock methods are planned:

- **FIDO2 Integration**: Hardware security keys for unlock
- **Remote Tailscale Unlock**: Secure network-based unlock
- **Multi-factor Authentication**: Combine multiple methods

## Security Considerations

### Threat Model

This configuration protects against:
- Unauthorized physical access to hardware
- Firmware tampering and rootkits
- Offline disk attacks
- Boot process manipulation

### Limitations

- Physical access to live system still allows data access
- TPM2 policies may need updates for hardware changes
- Recovery keys must be stored securely

### Best Practices

1. **Store recovery keys offline** in multiple secure locations
2. **Regularly update firmware** following security procedures
3. **Monitor system integrity** using built-in attestation
4. **Test recovery procedures** before relying on the system

## Backup and Recovery

### Before Major Changes

```bash
# Backup LUKS headers
cryptsetup luksHeaderBackup /dev/nvme0n1p2 --header-backup-file luks-header.backup

# Backup Secure Boot keys
cp -r /boot/EFI/secureboot/ ~/secureboot-keys-backup/
```

### System Migration

For moving to new hardware:
1. Backup encrypted data
2. Save recovery keys and LUKS headers
3. Note hardware-specific TPM2 will require re-enrollment

## Support

For issues specific to this secure installation process:

1. Check system logs: `journalctl -b`
2. Verify hardware compatibility
3. Review UEFI firmware documentation
4. Consult NixOS lanzaboote documentation

This secure installation provides enterprise-grade protection for your self-sovereign infrastructure while maintaining the flexibility and declarative nature of NixOS.