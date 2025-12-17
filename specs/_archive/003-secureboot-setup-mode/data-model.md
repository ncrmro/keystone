# Data Model: Secure Boot Setup Mode for VM Testing

**Feature**: 003-secureboot-setup-mode
**Created**: 2025-10-31

## Overview

This feature enhances the bin/virtual-machine script to manage Secure Boot state for test VMs. The data model describes the entities and their relationships involved in creating and maintaining VMs in Secure Boot setup mode.

## Entities

### VM Configuration

Represents the persistent libvirt domain configuration (XML) for a virtual machine.

**Attributes**:
- `name` (string): Unique VM identifier (e.g., "keystone-test-vm")
- `ovmf_code_path` (string): Absolute path to OVMF firmware CODE file (read-only)
- `ovmf_vars_template` (string): Absolute path to OVMF VARS template file
- `nvram_path` (string): Absolute path to VM-specific NVRAM file
- `disk_path` (string): Absolute path to VM disk image
- `secure_boot_enabled` (boolean): Whether Secure Boot is enabled in firmware
- `smm_enabled` (boolean): Whether System Management Mode is enabled (required for Secure Boot)
- `machine_type` (string): QEMU machine type (must be "q35" for UEFI)

**Relationships**:
- Has one NVRAM State (stored in nvram_path)
- References one OVMF Firmware (via ovmf_code_path and ovmf_vars_template)

**Validation Rules**:
- `machine_type` MUST be "q35" when `secure_boot_enabled` is true
- `smm_enabled` MUST be true when `secure_boot_enabled` is true
- `nvram_path` MUST exist and be writable
- `ovmf_code_path` MUST exist and contain "secure" in filename for Secure Boot support

**State Transitions**:
1. **Undefined** → **Defined**: VM created via bin/virtual-machine script
2. **Defined** → **Running**: VM started (domain.create())
3. **Running** → **Shut Off**: VM stopped (domain.shutdown())
4. **Defined** → **Deleted**: VM removed via --reset flag

---

### NVRAM State

Represents the firmware variables stored in the VM's NVRAM file (OVMF_VARS.fd copy).

**Attributes**:
- `file_path` (string): Absolute path to NVRAM file
- `file_size` (integer): Size in bytes (540,672 = empty template)
- `setup_mode` (boolean): Whether firmware is in Setup Mode (no PK enrolled)
- `secure_boot_active` (boolean): Whether Secure Boot verification is active
- `platform_key_enrolled` (boolean): Whether Platform Key (PK) is present
- `key_exchange_keys_count` (integer): Number of KEK entries
- `signature_db_count` (integer): Number of authorized signatures (db)
- `template_source` (string): Path to original OVMF_VARS template

**Relationships**:
- Belongs to one VM Configuration
- Initialized from one OVMF Firmware template

**Validation Rules**:
- `file_path` MUST exist before VM can boot
- `file_size` MUST be > 0 and match expected NVRAM size
- For setup mode: `setup_mode` = true, `platform_key_enrolled` = false
- If `file_size` != 540,672 bytes, may contain pre-enrolled keys

**State Transitions**:
1. **Uninitialized** → **Setup Mode**: Fresh copy from empty OVMF_VARS template
2. **Setup Mode** → **User Mode**: Platform Key enrolled (via OS installer or firmware UI)
3. **User Mode** → **Setup Mode**: PK deleted or NVRAM reset (via --reset-setup-mode)

**Invariants**:
- `setup_mode = true` ⟺ `platform_key_enrolled = false`
- `secure_boot_active = true` ⟺ `platform_key_enrolled = true AND setup_mode = false`

---

### OVMF Firmware

Represents the UEFI firmware files provided by NixOS/QEMU.

**Attributes**:
- `code_path` (string): Path to firmware CODE file (e.g., edk2-x86_64-secure-code.fd)
- `vars_template_path` (string): Path to VARS template (e.g., edk2-i386-vars.fd)
- `supports_secure_boot` (boolean): Whether CODE file includes Secure Boot support
- `vars_has_enrolled_keys` (boolean): Whether VARS template has pre-enrolled keys
- `detection_method` (string): How firmware was located ("qemu-share", "nix-store", "traditional")

**Relationships**:
- Referenced by multiple VM Configurations
- Provides initial template for NVRAM State

**Validation Rules**:
- `code_path` MUST contain "secure" in filename if `supports_secure_boot` is true
- `vars_template_path` MUST exist and be readable
- Both files MUST be in same directory or discoverable via find_ovmf_firmware()

**Static Properties** (for NixOS QEMU):
- CODE path: `/nix/store/{hash}-qemu-{version}/share/qemu/edk2-x86_64-secure-code.fd`
- VARS template: `/nix/store/{hash}-qemu-{version}/share/qemu/edk2-i386-vars.fd`
- Expected VARS size: 540,672 bytes (empty, no pre-enrolled keys)

---

## Entity Relationships Diagram

```
┌─────────────────────┐
│  OVMF Firmware      │
│  (Read-Only)        │
│ ─────────────────── │
│ code_path           │
│ vars_template_path  │
│ supports_secure_boot│
└──────────┬──────────┘
           │ provides template
           │
           ▼
┌─────────────────────┐        ┌─────────────────────┐
│  VM Configuration   │◄───────│   NVRAM State       │
│  (libvirt XML)      │ has    │   (Runtime)         │
│ ─────────────────── │        │ ─────────────────── │
│ name                │        │ file_path           │
│ nvram_path          │        │ setup_mode          │
│ secure_boot_enabled │        │ platform_key_enrolled│
│ machine_type        │        │ file_size           │
└─────────────────────┘        └─────────────────────┘
```

## Data Flows

### VM Creation Flow

```
1. find_ovmf_firmware() → Locate OVMF Firmware
   ├─ Search QEMU share directory
   ├─ Search Nix store
   └─ Return (code_path, vars_template_path)

2. create_uefi_secureboot_vm() → Create VM Configuration
   ├─ Generate nvram_path: vms/{vm_name}/OVMF_VARS.fd
   ├─ Copy vars_template_path → nvram_path
   ├─ Build libvirt XML with secure_boot_enabled=true
   └─ Define VM domain

3. VM First Boot → Initialize NVRAM State
   ├─ libvirt loads nvram_path into VM memory
   ├─ OVMF firmware initializes UEFI variables
   └─ SetupMode=1 (no PK enrolled)
```

### Setup Mode Verification Flow

```
1. Developer boots VM from Keystone installer ISO

2. Inside VM, run: bootctl status
   ├─ bootctl reads /sys/firmware/efi/efivars/SetupMode-*
   ├─ bootctl reads /sys/firmware/efi/efivars/SecureBoot-*
   └─ Output: "Secure Boot: disabled (setup)"

3. Verification confirms:
   ├─ NVRAM State: setup_mode = true
   ├─ NVRAM State: platform_key_enrolled = false
   └─ Ready for Keystone installer to enroll custom keys
```

## File System Representation

```
vms/keystone-test-vm/
├── disk.qcow2              # VM disk image
└── OVMF_VARS.fd            # NVRAM State (540,672 bytes if fresh)
                            # Contains UEFI variables:
                            #   SetupMode = 0x01
                            #   SecureBoot = 0x00
                            #   PK = (empty)
```

## Implementation Notes

### NVRAM Initialization

The current bin/virtual-machine script already performs correct initialization:

```python
# Copy OVMF vars template to VM-specific NVRAM
if not os.path.exists(nvram_path):
    os.makedirs(os.path.dirname(nvram_path), exist_ok=True)
    os.system(f"cp {ovmf_vars} {nvram_path}")
```

This creates a fresh NVRAM file from the empty template, ensuring setup mode.

### Enhancement: Add Template Attribute

To make setup mode explicit in libvirt configuration:

```xml
<os>
  <nvram template='{ovmf_vars}'>{nvram_path}</nvram>
</os>
```

This ensures libvirt knows to reset NVRAM from template if it becomes corrupted.

### Validation Function (Optional Enhancement)

```python
def validate_nvram_setup_mode(nvram_path):
    """Check if NVRAM file is in setup mode (no pre-enrolled keys)"""
    if not os.path.exists(nvram_path):
        return False, "NVRAM file does not exist"

    size = os.path.getsize(nvram_path)
    expected_size = 540672  # Empty edk2-i386-vars.fd

    if size != expected_size:
        return False, f"NVRAM size {size} != {expected_size} (may have pre-enrolled keys)"

    return True, "NVRAM appears to be in setup mode"
```

## Assumptions

1. **NixOS OVMF Firmware**: Both edk2-x86_64-secure-code.fd and edk2-i386-vars.fd are available via QEMU package
2. **Empty VARS Template**: NixOS QEMU provides VARS templates without Microsoft keys pre-enrolled
3. **File Size Heuristic**: 540,672 bytes indicates empty VARS template (may need adjustment for different OVMF versions)
4. **libvirt Compatibility**: libvirt supports `template` attribute on `<nvram>` element (verify version)
5. **Kernel Support**: Host kernel exposes efivars to allow `bootctl status` to read UEFI variables
