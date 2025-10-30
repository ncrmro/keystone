# Data Model: Secure Boot Automation

**Feature**: 003-secureboot-automation
**Date**: 2025-10-29

## Overview

This feature extends the test-deployment script to automate Secure Boot enrollment. The "data" in this context consists primarily of state information, configuration settings, and verification results rather than traditional persistent data structures.

## State Entities

### 1. Secure Boot Status

**Description**: Represents the current Secure Boot configuration state of the VM

**Attributes**:
- **uefi_mode**: Boolean - Whether system is booted in UEFI mode
- **setup_mode**: Boolean - Whether firmware is in Setup Mode (true) or User Mode (false)
- **secure_boot_enabled**: Boolean - Whether Secure Boot is currently enforcing
- **keys_enrolled**: Boolean - Whether custom keys have been enrolled in firmware
- **capability_supported**: Boolean - Whether VM firmware supports Secure Boot

**State Transitions**:
```
Initial State (Fresh VM)
  ├─ uefi_mode: true
  ├─ setup_mode: true
  ├─ secure_boot_enabled: false
  ├─ keys_enrolled: false
  └─ capability_supported: true/false (detected)

After Key Enrollment
  ├─ uefi_mode: true
  ├─ setup_mode: false  # Transition from Setup → User Mode
  ├─ secure_boot_enabled: false  # Not yet enabled in firmware
  ├─ keys_enrolled: true  # Keys now in NVRAM
  └─ capability_supported: true

After Secure Boot Enable (in firmware)
  ├─ uefi_mode: true
  ├─ setup_mode: false
  ├─ secure_boot_enabled: true  # Now enforcing
  ├─ keys_enrolled: true
  └─ capability_supported: true
```

**Validation Rules**:
- `uefi_mode` must be true for Secure Boot operations
- `setup_mode` must be true before enrollment, false after
- `secure_boot_enabled` can only be true if `keys_enrolled` is true
- `capability_supported` false → skip Secure Boot phases gracefully

**Access Method**: Read via sysfs (`/sys/firmware/efi/efivars/`) and `bootctl status`

---

### 2. Enrollment Keys

**Description**: Cryptographic key pairs used for Secure Boot verification

**Attributes**:
- **pk** (Platform Key): Root of trust, one key only
- **kek** (Key Exchange Key): Intermediate keys for updating db/dbx
- **db** (Signature Database): Authorized signatures for bootloaders/kernels
- **dbx** (Forbidden Signature Database): Revoked signatures

**Location**: `/var/lib/sbctl/` (default PKI bundle)

**Files Generated**:
```
/var/lib/sbctl/
├── keys/
│   ├── db/
│   │   ├── db.key      # Private key for signing
│   │   └── db.pem      # Public key certificate
│   ├── KEK/
│   │   ├── KEK.key
│   │   └── KEK.pem
│   └── PK/
│       ├── PK.key
│       └── PK.pem
└── files.db            # sbctl database of signed files
```

**Lifecycle**:
1. Created: During `sbctl create-keys`
2. Enrolled: During `sbctl enroll-keys` (written to firmware NVRAM)
3. Used: Every boot to verify bootloader/kernel signatures

**Validation Rules**:
- Keys must exist before enrollment
- Private keys must be protected (read-only to root)
- Keys should be backed up for disaster recovery

---

### 3. Boot Component Signatures

**Description**: Verification status of boot chain components

**Attributes**:
- **component_path**: String - Path to boot file (e.g., `/boot/EFI/nixos/kernel-6.1.0.efi`)
- **signed**: Boolean - Whether file has valid signature
- **verified**: Boolean - Whether signature matches enrolled keys

**Tracked Components**:
- Bootloader: `systemd-bootx64.efi` (lanzaboote-signed)
- Kernel: `nixos-generation-*.efi` (signed by sbctl)
- Initrd: Bundled in kernel EFI stub

**Validation Rules**:
- All critical boot components must be signed
- Signatures must be verifiable with enrolled db keys
- Unsigned components will be rejected when Secure Boot is enforcing

**Access Method**: Read via `sbctl verify`

---

### 4. Test Execution State

**Description**: Tracks progress through test script phases

**Attributes**:
- **current_phase**: Enum - Current execution phase
- **phase_status**: Dict - Status of each completed phase
- **error_log**: List - Any errors encountered
- **start_time**: Timestamp - Test start time
- **duration**: Integer - Elapsed time in seconds

**Phase Enum Values**:
```python
class TestPhase(Enum):
    VM_STOP = "stopping_vm"
    VM_CLEAN = "cleaning_artifacts"
    ISO_BUILD = "building_iso"
    VM_START = "starting_vm"
    SSH_WAIT = "waiting_ssh"
    DEPLOYMENT = "nixos_deployment"
    REBOOT_TO_DISK = "rebooting_to_disk"
    LUKS_UNLOCK = "unlocking_luks"
    SB_CAPABILITY_CHECK = "checking_secureboot_capability"  # NEW
    SB_ENROLLMENT = "enrolling_secureboot_keys"              # NEW
    SB_REBOOT = "rebooting_after_enrollment"                 # NEW
    SB_VERIFICATION = "verifying_secureboot"                 # NEW
    FINAL_VERIFICATION = "final_checks"
```

**State Transitions**:
Each phase transitions: `pending` → `in_progress` → `completed` or `failed`

---

## Configuration Entities

### 5. VM Configuration

**Description**: QEMU/quickemu VM settings

**Attributes**:
- **uefi_firmware**: String - Path to OVMF_CODE.fd
- **uefi_vars**: String - Path to OVMF_VARS.fd (per-VM)
- **secure_boot_capable**: Boolean - Whether firmware supports Secure Boot
- **iso_path**: String - Path to installer ISO
- **disk_path**: String - Path to VM disk image
- **ssh_port**: Integer - SSH forwarding port (22220)
- **serial_socket**: String - Path to serial console socket

**Source**: `vms/server.conf`

**Validation Rules**:
- `uefi_firmware` must point to OVMF with Secure Boot support
- `uefi_vars` must be writable and persistent across reboots
- `ssh_port` must be available on host

---

### 6. NixOS Module Configuration

**Description**: Lanzaboote and related boot configuration

**Attributes**:
- **lanzaboote_enabled**: Boolean - Whether lanzaboote module is active
- **pki_bundle**: String - Path to key storage (/var/lib/sbctl)
- **enroll_keys**: Boolean - Auto-enrollment flag (testing only)
- **systemd_boot_disabled**: Boolean - Must be true when lanzaboote enabled

**Source**: `examples/test-server.nix` or deployment flake config

**Validation Rules**:
- `systemd_boot_disabled` must be true if `lanzaboote_enabled` is true
- `pki_bundle` directory must exist and contain keys
- `enroll_keys` should only be true in test environments

---

## Relationships

```
┌─────────────────────┐
│  VM Configuration   │
│  (vms/server.conf)  │
└──────────┬──────────┘
           │ configures
           ├─────────────────────┐
           │                     │
           ▼                     ▼
┌────────────────────┐  ┌─────────────────────┐
│   OVMF Firmware    │  │  Test Execution     │
│  (UEFI/SecureBoot) │  │      State          │
└─────────┬──────────┘  └──────────┬──────────┘
          │                        │
          │ stores                 │ tracks
          ▼                        ▼
┌────────────────────┐  ┌─────────────────────┐
│ Secure Boot Status │  │   Phase Progress    │
│  (UEFI variables)  │  │   (script state)    │
└─────────┬──────────┘  └─────────────────────┘
          │
          │ uses
          ▼
┌────────────────────┐
│ Enrollment Keys    │
│ (/var/lib/sbctl)   │
└─────────┬──────────┘
          │
          │ signs
          ▼
┌────────────────────┐
│ Boot Components    │
│  (bootloader/      │
│   kernel EFI)      │
└────────────────────┘
```

---

## Data Flow

### 1. Capability Detection Flow
```
test-deployment script
  ↓ SSH command
VM: /sys/firmware/efi/efivars/SecureBoot-*
  ↓ file exists check
Secure Boot Capability → true/false
  ↓ decision
Continue to enrollment OR skip gracefully
```

### 2. Enrollment Flow
```
test-deployment script
  ↓ SSH command: sbctl enroll-keys
VM: sbctl
  ↓ reads keys from
/var/lib/sbctl/keys/*
  ↓ writes to
OVMF_VARS.fd (firmware NVRAM)
  ↓ updates
Secure Boot Status: setup_mode = false, keys_enrolled = true
```

### 3. Verification Flow
```
test-deployment script
  ↓ SSH command: multiple checks
VM: sysfs, bootctl, sbctl
  ↓ read status
Secure Boot Status attributes
  ↓ aggregate
Test Execution State: phase_status["SB_VERIFICATION"] = passed/failed
```

---

## Persistence

### Temporary (per test run)
- Test Execution State (in-memory Python data structure)
- SSH connection state
- Serial console buffers

### Persistent (across reboots)
- OVMF_VARS.fd: Stores enrolled keys and Secure Boot settings
- /var/lib/sbctl/: Key material generated during deployment
- VM disk.qcow2: NixOS system with lanzaboote configuration

### Disposable (cleaned on hard reset)
- OVMF_VARS.fd: Recreated from template
- VM disk: Deleted and recreated
- Runtime logs and sockets

---

## Error States

### Enrollment Failures
- **Cause**: Firmware not in Setup Mode
- **Detection**: `sbctl enroll-keys` returns non-zero exit code
- **Recovery**: Reset firmware to Setup Mode, retry enrollment

### Verification Failures
- **Cause**: Keys enrolled but Secure Boot not enabled in firmware
- **Detection**: `setup_mode = false` but `secure_boot_enabled = false`
- **Recovery**: Reboot and enable Secure Boot in UEFI settings (manual)

### Capability Not Supported
- **Cause**: VM firmware doesn't support Secure Boot (e.g., wrong OVMF build)
- **Detection**: `/sys/firmware/efi/efivars/SecureBoot-*` doesn't exist
- **Recovery**: Graceful skip, log warning, continue other tests

---

## Implementation Notes

This feature doesn't create new persistent data structures beyond configuration files and script state. The primary "data" is:

1. **State information** in UEFI firmware variables (OVMF_VARS.fd)
2. **Cryptographic keys** in filesystem (/var/lib/sbctl)
3. **Runtime state** in test script (Python objects)
4. **Configuration** in NixOS modules and VM configs

No database, no API contracts (covered in contracts/), no complex data schemas required.
