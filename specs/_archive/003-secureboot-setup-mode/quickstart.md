# Quickstart: Secure Boot Setup Mode Testing

**Feature**: 003-secureboot-setup-mode
**Audience**: Keystone developers testing Secure Boot integration
**Time**: 5-10 minutes

## Overview

This guide shows how to create a VM in Secure Boot setup mode and verify the configuration. Use this for testing Keystone's Secure Boot integration, lanzaboote configuration, and custom key enrollment.

## Prerequisites

**On your NixOS development machine**:

```nix
# In configuration.nix
virtualisation.libvirtd.enable = true;
users.users.<youruser>.extraGroups = [ "libvirtd" ];
```

**Required packages** (provided by NixOS):
- libvirt
- QEMU with OVMF firmware
- remote-viewer (for graphical console)

## Quick Start

### 1. Create VM in Setup Mode

```bash
# Create and start VM with default settings
./bin/virtual-machine --name secureboot-test --start
```

**What happens**:
- ✅ VM created with UEFI Secure Boot enabled
- ✅ NVRAM initialized from empty OVMF_VARS template (no pre-enrolled keys)
- ✅ Boots into Setup Mode automatically
- ✅ Keystone installer ISO loaded (if available at vms/keystone-installer.iso)

**Expected output**:
```
✓ Connected to libvirt
Searching for OVMF firmware...
✓ Found OVMF CODE: /nix/store/.../edk2-x86_64-secure-code.fd
✓ Found OVMF VARS: /nix/store/.../edk2-i386-vars.fd
✓ Created NVRAM: /home/user/keystone/vms/secureboot-test/OVMF_VARS.fd
✓ Secure Boot enabled
✓ VM 'secureboot-test' defined successfully
✓ VM 'secureboot-test' started
```

### 2. Connect to VM

**Option A: Serial Console** (recommended for automated testing):
```bash
virsh console secureboot-test
```

**Option B: Graphical Display** (recommended for interactive use):
```bash
remote-viewer $(virsh domdisplay secureboot-test)
```

### 3. Verify Setup Mode

**Inside the VM** (after booting from Keystone installer):

```bash
# Check Secure Boot status
bootctl status
```

**Expected output**:
```
System:
     Firmware: UEFI 2.70 (EDK II 1.00)
  Secure Boot: disabled (setup)
   Setup Mode: setup
```

**Interpretation**:
- ✅ `Secure Boot: disabled (setup)` = Firmware has Secure Boot capability, currently in setup mode
- ✅ `Setup Mode: setup` = No Platform Key enrolled, ready for key enrollment
- ✅ This is the correct state for testing Keystone installer

### 4. Alternative Verification (from host)

**Check NVRAM file size**:
```bash
stat -c%s vms/secureboot-test/OVMF_VARS.fd
```

**Expected**: `540672` bytes (empty template, no pre-enrolled keys)

**Inspect NVRAM with dumpxml** (optional):
```bash
virsh dumpxml secureboot-test | grep -A 5 "<os"
```

**Expected output**:
```xml
<os>
  <type arch='x86_64' machine='q35'>hvm</type>
  <loader readonly='yes' secure='yes' type='pflash'>/nix/store/.../edk2-x86_64-secure-code.fd</loader>
  <nvram>/home/user/keystone/vms/secureboot-test/OVMF_VARS.fd</nvram>
  <boot dev='hd'/>
</os>
```

Note: `secure='yes'` confirms Secure Boot is enabled.

## Common Workflows

### Test Keystone Installer with Secure Boot

```bash
# 1. Build Keystone installer ISO with SSH key
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# 2. Create VM in setup mode
./bin/virtual-machine --name keystone-install-test --start

# 3. VM boots from ISO automatically

# 4. Connect via SSH (wait ~30 seconds for boot)
ssh -p 22220 root@localhost

# 5. Verify setup mode
bootctl status
# Should show "Secure Boot: disabled (setup)"

# 6. Run installer (will enroll keys and transition to User Mode)
# ... installer commands ...

# 7. After installation, verify User Mode
bootctl status
# Should show "Secure Boot: enabled (user)"
```

### Reset VM to Setup Mode

```bash
# Delete VM completely
./bin/virtual-machine --reset secureboot-test

# Recreate fresh (automatically in setup mode)
./bin/virtual-machine --name secureboot-test --start
```

### Test Multiple Secure Boot Scenarios

```bash
# Scenario 1: Setup Mode (no keys)
./bin/virtual-machine --name test-setup --start
virsh console test-setup
# bootctl status → setup mode

# Scenario 2: User Mode (keys enrolled by installer)
# ... let installer enroll keys ...
# bootctl status → user mode

# Scenario 3: Return to Setup Mode
./bin/virtual-machine --reset test-setup
./bin/virtual-machine --name test-setup --start
# bootctl status → setup mode again
```

## Troubleshooting

### OVMF Firmware Not Found

**Error**:
```
ERROR: OVMF firmware not found!
```

**Solution**:
```bash
# Ensure libvirtd is enabled (provides OVMF firmware)
# In configuration.nix:
virtualisation.libvirtd.enable = true;

# Rebuild system
sudo nixos-rebuild switch
```

### VM Shows "Secure Boot: enabled (user)"

**Symptom**: `bootctl status` shows user mode instead of setup mode

**Cause**: NVRAM file already has Platform Key enrolled

**Solution**:
```bash
# Reset to setup mode by deleting and recreating
./bin/virtual-machine --reset <vm-name>
./bin/virtual-machine --name <vm-name> --start
```

### Cannot Connect with virsh console

**Error**:
```
error: failed to get domain 'secureboot-test'
```

**Solution**:
```bash
# Ensure you're in libvirtd group
groups | grep libvirtd

# If not, add yourself:
# In configuration.nix:
users.users.<youruser>.extraGroups = [ "libvirtd" ];

# Rebuild and re-login
sudo nixos-rebuild switch
# Log out and log back in
```

### bootctl Shows "Secure Boot: n/a"

**Symptom**: `bootctl status` doesn't show Secure Boot information

**Possible Causes**:
1. VM didn't boot with UEFI (check machine type = q35)
2. Kernel doesn't expose efivars (check /sys/firmware/efi/efivars exists)
3. Running bootctl outside of UEFI environment

**Solution**:
```bash
# Verify UEFI boot
ls /sys/firmware/efi
# Should list efi directories

# Check efivars are mounted
mount | grep efivars
# Should show efivars filesystem

# If missing, you may be in BIOS mode not UEFI
```

## Advanced Usage

### Inspect UEFI Variables Directly

**From inside VM**:
```bash
# Check SetupMode variable
cat /sys/firmware/efi/efivars/SetupMode-* | od -An -t u1
# Expected: 1 (setup mode active)

# Check SecureBoot variable
cat /sys/firmware/efi/efivars/SecureBoot-* | od -An -t u1
# Expected: 0 (Secure Boot not enforcing in setup mode)

# List all Secure Boot related variables
ls /sys/firmware/efi/efivars/ | grep -i secure
```

### Monitor Secure Boot State Transitions

```bash
# Before installer runs
bootctl status
# Secure Boot: disabled (setup)

# ... installer enrolls keys ...

# After installer completes
bootctl status
# Secure Boot: enabled (user)

# This transition confirms successful key enrollment
```

### Custom VM Configuration

```bash
# Large VM for performance testing
./bin/virtual-machine \
  --name large-secureboot-test \
  --memory 8192 \
  --vcpus 4 \
  --disk-size 50 \
  --start

# Custom ISO path
./bin/virtual-machine \
  --name custom-iso-test \
  --iso /path/to/custom.iso \
  --start
```

## Expected Timeline

**VM Creation**: 15-30 seconds
- Firmware detection: ~2 seconds
- NVRAM copy: <1 second
- VM definition: ~5 seconds
- VM start: ~10 seconds

**First Boot**: 20-40 seconds
- UEFI firmware init: ~5 seconds
- Boot from ISO: ~15-30 seconds

**Total Time to Verification**: ~1-2 minutes from command to `bootctl status` output

## Success Criteria Checklist

After following this guide, you should be able to:

- ✅ Create a VM with one command
- ✅ VM boots in Secure Boot setup mode (verified with `bootctl status`)
- ✅ NVRAM file created at correct location (vms/<name>/OVMF_VARS.fd)
- ✅ NVRAM file has correct size (540,672 bytes)
- ✅ VM accessible via serial console and graphical display
- ✅ Ready to test Keystone installer's Secure Boot integration

## Next Steps

After verifying setup mode:

1. **Test Key Enrollment**: Run Keystone installer and verify it enrolls custom keys
2. **Test Boot with Keys**: Verify system boots with custom keys after installation
3. **Test Rejected Boot**: Try booting unsigned code and verify firmware rejects it
4. **Test Key Rotation**: Test re-enrolling different keys

## Reference

**Full Documentation**:
- [Feature Specification](./spec.md)
- [Implementation Plan](./plan.md)
- [Research Notes](./research.md)
- [Data Model](./data-model.md)

**Related Scripts**:
- `bin/virtual-machine` - VM creation and management
- `bin/build-iso` - Build Keystone installer ISO

**UEFI/Secure Boot Resources**:
- `bootctl(1)` man page
- UEFI Specification 2.10
- OVMF Documentation: https://github.com/tianocore/tianocore.github.io/wiki/OVMF
