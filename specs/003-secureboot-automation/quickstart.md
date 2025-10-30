# Quickstart: Secure Boot Automation

**Feature**: 003-secureboot-automation
**Audience**: Developers testing Keystone deployments
**Time to Complete**: 15-20 minutes

## Overview

This guide shows you how to run the extended test-deployment script that now includes automated Secure Boot enrollment and verification.

## Prerequisites

- NixOS or Linux with Nix installed
- QEMU/KVM installed
- At least 8GB RAM and 30GB free disk space
- SSH key pair generated (`~/.ssh/id_ed25519.pub`)

## Quick Start

### 1. Run the Test Script

From the Keystone repository root:

```bash
./bin/test-deployment
```

This will:
1. Start a VM from the Keystone installer ISO
2. Deploy NixOS with ZFS encryption
3. Automatically unlock the encrypted root via serial
4. **NEW**: Detect Secure Boot capability
5. **NEW**: Enroll custom Secure Boot keys
6. **NEW**: Verify Secure Boot is enabled and working
7. Verify the complete deployment

**Expected Duration**: 10-15 minutes

### 2. Watch the Output

You'll see progress through these new phases:

```
[5/8] Checking Secure Boot capability
ℹ Verifying UEFI mode and Secure Boot support...
✓ UEFI mode confirmed
✓ Secure Boot variables accessible

[6/8] Enrolling Secure Boot keys
ℹ Enrolling keys via sbctl...
✓ Keys enrolled successfully

[7/8] Verifying Secure Boot
ℹ Running Secure Boot verification checks...
✓ Secure Boot enabled
✓ Boot files properly signed
```

### 3. Access the Deployed System

After successful completion:

```bash
# SSH into the VM
ssh -p 22220 root@localhost

# Check Secure Boot status
bootctl status | grep "Secure Boot"
# Expected: Secure Boot: enabled (user)

# Verify keys enrolled
sbctl status
# Expected: Setup Mode: ✔ Disabled
#           Secure Boot: ✔ Enabled
```

## Common Scenarios

### Full Clean Test

Rebuild everything from scratch:

```bash
./bin/test-deployment --rebuild-iso --hard-reset
```

Use this when:
- Testing changes to the installer ISO
- VM is in a broken state
- You want a completely fresh test environment

### Skip Secure Boot

Test without Secure Boot automation:

```bash
./bin/test-deployment --skip-secureboot
```

Use this when:
- Testing on platforms without Secure Boot support
- Debugging other deployment issues
- Comparing with/without Secure Boot

### Rebuild ISO Only

Update the installer ISO with your current SSH key:

```bash
./bin/test-deployment --rebuild-iso
```

Use this when:
- Your SSH key changed
- You want to test ISO generation

## What Gets Tested

### ✅ Automated Testing Coverage

The script automatically verifies:

**Infrastructure**:
- ✓ VM boots in UEFI mode
- ✓ QEMU/KVM functioning correctly
- ✓ Network connectivity

**Deployment**:
- ✓ nixos-anywhere deploys successfully
- ✓ ZFS root pool created
- ✓ LUKS credstore encrypted
- ✓ TPM2 integration (if available)

**Secure Boot** (NEW):
- ✓ UEFI Secure Boot capability detected
- ✓ Custom keys generated (lanzaboote)
- ✓ Keys enrolled in firmware NVRAM
- ✓ Setup Mode → User Mode transition
- ✓ Secure Boot enabled and enforcing
- ✓ Bootloader and kernel properly signed

**Post-Deployment**:
- ✓ SSH access working
- ✓ ZFS pool healthy
- ✓ System services running

### ⚠️ Manual Verification (Optional)

For deeper inspection:

```bash
# Check UEFI variables directly
cat /sys/firmware/efi/efivars/SecureBoot-* | od -An -t u1

# Verify all boot files signed
sbctl verify

# List enrolled keys
sbctl list-enrolled-keys

# Check systemd-boot status
bootctl status
```

## Troubleshooting

### "Secure Boot not supported"

**Symptom**:
```
[5/8] Checking Secure Boot capability
⚠ UEFI Secure Boot not supported on this platform
ℹ Skipping Secure Boot enrollment and verification
```

**Cause**: VM firmware doesn't support Secure Boot

**Resolution**:
- This is expected on some older VM configurations
- Test continues without Secure Boot (not a failure)
- To enable: Update `vms/server.conf` to use OVMF with Secure Boot support

### "Failed to enroll Secure Boot keys"

**Symptom**:
```
[6/8] Enrolling Secure Boot keys
✗ Failed to enroll Secure Boot keys
```

**Resolution**:
1. Check sbctl status: `ssh -p 22220 root@localhost 'sbctl status'`
2. Look for firmware Setup Mode requirement
3. Try again with: `./bin/test-deployment --hard-reset`

### SSH Connection Timeout

**Symptom**:
```
[2/8] Waiting for SSH access
  Attempt 10/10...
✗ SSH never became available
```

**Resolution**:
1. Check if port 22220 is already in use: `lsof -i :22220`
2. Verify VM is running: `pgrep -f 'qemu.*server'`
3. Rebuild ISO with SSH key: `./bin/test-deployment --rebuild-iso --hard-reset`

### VM Won't Start

**Symptom**:
```
[1/8] Starting VM from ISO
✗ Failed to start VM
```

**Resolution**:
1. Check for conflicting VMs: `pgrep qemu`
2. Clean up: `./bin/test-deployment --hard-reset` (then try again)
3. Verify `vms/server.conf` exists
4. Check available disk space: `df -h`

## Understanding the Output

### Success Indicators

```
✓ Green checkmarks = Phase passed
ℹ Cyan info = Informational message
⚠ Yellow warning = Non-fatal issue
✗ Red X = Phase failed
```

### Phase Timing

| Phase | Typical Duration | What's Happening |
|-------|------------------|------------------|
| VM Start | 30s | QEMU boots VM from ISO |
| SSH Wait | 10-30s | Waiting for installer network |
| Deployment | 5-10min | nixos-anywhere installs NixOS |
| Reboot to Disk | 40s | Boot installed system, unlock LUKS |
| SB Capability Check | 5s | Detect Secure Boot support |
| SB Enrollment | 10-15s | Enroll custom keys in firmware |
| SB Reboot | 60s | Boot with new keys |
| SB Verification | 10s | Verify Secure Boot active |
| Final Verification | 30s | System health checks |

**Total**: ~10-15 minutes for full test

### Exit Codes

- `0` = All tests passed
- `1` = One or more tests failed
- `130` = User interrupted (Ctrl+C)

## Next Steps

### Examine the Deployed System

```bash
# SSH into VM
ssh -p 22220 root@localhost

# Check ZFS encryption
zfs get encryption rpool/crypt

# View TPM2 status
systemctl status systemd-tpm2-setup

# Check Secure Boot details
bootctl status
sbctl status
sbctl verify
```

### Customize Configuration

Edit `examples/test-server.nix` to:
- Enable/disable Secure Boot
- Change disk encryption settings
- Add additional services
- Modify TPM2 configuration

Then rebuild:
```bash
./bin/test-deployment --hard-reset
```

### Run in CI/CD

The test script is designed for automation:

```yaml
# .github/workflows/test.yml
- name: Test Secure Boot Deployment
  run: |
    nix develop -c ./bin/test-deployment
```

### Explore Secure Boot Configuration

The deployed system uses **lanzaboote** for Secure Boot:

```nix
# In your NixOS configuration
{
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
}
```

See `examples/test-server.nix` for the complete configuration.

## Key Concepts

### Secure Boot Enrollment Flow

1. **Key Generation**: Lanzaboote module creates keys during deployment
2. **Setup Mode**: OVMF firmware starts in Setup Mode (allows key enrollment)
3. **Enrollment**: Script triggers `sbctl enroll-keys` via SSH
4. **User Mode**: Firmware transitions to User Mode (keys locked)
5. **Verification**: Script confirms Secure Boot enabled and enforcing

### What Gets Signed

Lanzaboote automatically signs:
- Systemd-boot bootloader (`systemd-bootx64.efi`)
- NixOS kernel EFI stubs (`nixos-generation-*.efi`)
- Any boot components in `/boot/EFI/`

The kernel, initrd, and everything after boot are verified by other mechanisms (dm-verity, IMA, etc.).

### Why Automated Testing Matters

Manual Secure Boot setup requires:
1. Entering UEFI/BIOS settings
2. Enabling Setup Mode
3. Rebooting to OS
4. Running enrollment commands
5. Rebooting back to BIOS
6. Enabling Secure Boot
7. Final reboot and verification

This script automates the entire workflow for rapid iteration and CI/CD integration.

## Resources

- [Lanzaboote Documentation](https://github.com/nix-community/lanzaboote)
- [NixOS Secure Boot Wiki](https://nixos.wiki/wiki/Secure_Boot)
- [UEFI Secure Boot Spec](https://uefi.org/specs/UEFI/2.10/32_Secure_Boot_and_Driver_Signing.html)
- Keystone CLAUDE.md for project architecture

## Getting Help

If you encounter issues:

1. Check this quickstart's Troubleshooting section
2. Review the test script output for specific error messages
3. Examine `specs/003-secureboot-automation/research.md` for technical details
4. Open an issue with:
   - Full test script output
   - Output of `bootctl status` and `sbctl status` from VM
   - Your `vms/server.conf` configuration
