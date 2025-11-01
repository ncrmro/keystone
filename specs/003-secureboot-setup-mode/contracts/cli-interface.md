# CLI Interface Contract: bin/virtual-machine

**Feature**: 003-secureboot-setup-mode
**Created**: 2025-10-31

## Overview

This document specifies the command-line interface contract for the enhanced bin/virtual-machine script. The existing interface remains unchanged; this enhancement ensures VMs are created in Secure Boot setup mode by default.

## Current Interface (Unchanged)

### VM Creation

```bash
bin/virtual-machine [OPTIONS]
```

**Options**:
- `--name NAME` - VM name (default: "keystone-test-vm")
- `--memory MB` - RAM in MB (default: 4096)
- `--vcpus NUM` - Number of vCPUs (default: 2)
- `--disk-size GB` - Disk size in GB (default: 30)
- `--iso PATH` - Path to installation ISO (default: vms/keystone-installer.iso if exists)
- `--ssh-port PORT` - SSH port forwarding (default: 22220)
- `--start` - Start VM immediately after creation
- `--post-install-reboot VM_NAME` - Post-install workflow (snapshot, remove ISO, reboot)
- `--reset VM_NAME` - Delete VM and all files

**Exit Codes**:
- `0` - Success
- `1` - Error (firmware not found, VM creation failed, etc.)

**Examples**:

```bash
# Create VM with default settings
./bin/virtual-machine --name test-vm --start

# Create with custom resources
./bin/virtual-machine --name large-vm --memory 8192 --vcpus 4 --disk-size 50

# Post-installation cleanup
./bin/virtual-machine --post-install-reboot test-vm

# Delete VM
./bin/virtual-machine --reset test-vm
```

## Enhanced Behavior (New)

### Secure Boot Setup Mode Guarantee

When creating a new VM:

**Preconditions**:
- OVMF Secure Boot firmware available (edk2-x86_64-secure-code.fd)
- Empty OVMF_VARS template available (edk2-i386-vars.fd)
- libvirt daemon running

**Postconditions**:
- VM created with fresh NVRAM file (no pre-enrolled keys)
- Firmware configuration: Secure Boot enabled, Setup Mode active
- Running `bootctl status` in VM shows "Secure Boot: disabled (setup)"

**Implementation**:
1. Copy empty OVMF_VARS template to `vms/{vm_name}/OVMF_VARS.fd`
2. Configure libvirt XML with:
   - `<loader secure='yes'>` (Secure Boot enabled)
   - `<nvram template='{ovmf_vars}'>{nvram_path}</nvram>` (template reference)
   - `<smm state='on'>` (System Management Mode required)
3. No key enrollment performed by script

### Verification Contract

**User Action**:
```bash
# 1. Create and start VM
./bin/virtual-machine --name test-vm --start

# 2. Connect to VM serial console
virsh console test-vm

# 3. Boot from Keystone installer ISO

# 4. Inside VM, verify setup mode
bootctl status
```

**Expected Output**:
```
System:
     Firmware: UEFI 2.70 (EDK II 1.00)
  Secure Boot: disabled (setup)
   Setup Mode: setup
```

**Key Indicators**:
- `Secure Boot: disabled (setup)` - Secure Boot enabled in firmware but not enforcing (no keys)
- `Setup Mode: setup` - Firmware allows key enrollment

**Alternative Verification** (from host):
```bash
# Check NVRAM file size (empty template indicator)
stat -f%z vms/test-vm/OVMF_VARS.fd
# Expected: 540672 bytes
```

## Error Handling

### Firmware Not Available

**Condition**: OVMF Secure Boot firmware not found in NixOS

**Output**:
```
ERROR: OVMF firmware not found!
On NixOS, ensure you have OVMF available:
  Add to configuration.nix: virtualisation.libvirtd.enable = true;
  Or install manually: nix-env -iA nixos.OVMF
```

**Exit Code**: 1

### Pre-Enrolled Keys Detected

**Condition**: OVMF_VARS template file size != 540,672 bytes (future enhancement)

**Output**:
```
WARNING: OVMF_VARS template may contain pre-enrolled keys
Template: /nix/store/.../edk2-i386-vars.fd
Size: 1234567 bytes (expected 540672)
VM may not boot in Setup Mode
```

**Behavior**: Continue with warning (non-fatal)

### libvirt Connection Failed

**Condition**: Cannot connect to qemu:///system

**Output**:
```
ERROR: Failed to open connection to qemu:///system
On NixOS, ensure libvirtd is enabled:
  Add to configuration.nix:
    virtualisation.libvirtd.enable = true;
    users.users.<youruser>.extraGroups = [ "libvirtd" ];
```

**Exit Code**: 1

## Help Text Enhancement

### Updated Help Output

```bash
./bin/virtual-machine --help
```

**New Section**:
```
SECURE BOOT SETUP MODE:
  VMs are created with Secure Boot enabled in Setup Mode (no keys enrolled).
  This allows testing custom key enrollment and Keystone installer integration.

  To verify Setup Mode inside the VM:
    bootctl status

  Expected output:
    Secure Boot: disabled (setup)
    Setup Mode: setup

  Setup Mode means:
    - Secure Boot is enabled in firmware
    - No Platform Key (PK) is enrolled
    - Firmware allows key enrollment
    - OS installer can enroll custom keys
```

## Python Function Signatures

### Enhanced create_uefi_secureboot_vm()

```python
def create_uefi_secureboot_vm(
    conn,
    vm_name="keystone-test-vm",
    memory_mb=4096,
    vcpus=2,
    disk_path=None,
    disk_size_gb=20,
    iso_path=None,
    ssh_port=22222,
):
    """
    Create a VM with UEFI Secure Boot enabled in Setup Mode

    Args:
        conn: libvirt connection object
        vm_name: Name of the VM
        memory_mb: RAM in MB
        vcpus: Number of virtual CPUs
        disk_path: Path to disk image (created if doesn't exist)
        disk_size_gb: Size of disk if creating new
        iso_path: Path to installation ISO (optional)
        ssh_port: Host port for SSH forwarding (unused with keystone-net)

    Returns:
        libvirt.virDomain: Domain object for created VM

    Raises:
        SystemExit(1): If OVMF firmware not found or VM creation fails

    Postconditions:
        - VM defined in libvirt with Secure Boot enabled
        - NVRAM file created from empty OVMF_VARS template
        - VM in Setup Mode (no keys enrolled, SetupMode=1)
        - bootctl status will show "Secure Boot: disabled (setup)"
    """
```

### New Validation Function (Optional)

```python
def validate_setup_mode(nvram_path):
    """
    Validate that NVRAM file is in Setup Mode

    Args:
        nvram_path: Path to NVRAM file (OVMF_VARS.fd copy)

    Returns:
        tuple: (is_valid, message)
            is_valid (bool): True if NVRAM appears to be in setup mode
            message (str): Human-readable validation result

    Validation Criteria:
        - File exists
        - File size matches empty template (540,672 bytes)

    Example:
        >>> validate_setup_mode("vms/test-vm/OVMF_VARS.fd")
        (True, "NVRAM appears to be in setup mode")
    """
```

## Backward Compatibility

### Existing VMs

VMs created before this enhancement:
- Continue to work unchanged
- May or may not be in Setup Mode depending on OVMF_VARS template used
- Can be verified with `bootctl status` if needed
- Can be reset to Setup Mode with `--reset` and recreate

### No Breaking Changes

- All existing command-line flags work identically
- No new required arguments
- Default behavior enhanced but compatible
- Exit codes unchanged

## Non-Functional Requirements

### Performance

- VM creation time: < 30 seconds (unchanged from current)
- NVRAM copy operation: < 1 second
- Firmware detection: < 2 seconds

### Reliability

- 100% of VMs start in Setup Mode when using empty OVMF_VARS template
- Graceful degradation if template attribute not supported by libvirt version
- Clear error messages for all failure scenarios

### Usability

- Zero configuration required from user (automatic firmware detection)
- Clear verification instructions in help text
- Helpful error messages with remediation steps
