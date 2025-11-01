# Script Interface Contracts: Secure Boot Key Management

**Feature**: Secure Boot Custom Key Enrollment
**Date**: 2025-11-01
**Type**: Shell Script Interfaces (CLI contracts)

## Overview

This document defines the interface contracts for Secure Boot key management scripts. While not traditional REST/GraphQL APIs, these scripts form a well-defined interface that test automation and deployment scripts depend on.

---

## Contract 1: secureboot-generate-keys.sh

### Purpose
Generate custom Secure Boot keys (PK, KEK, db) using sbctl.

### Interface

**Command**:
```bash
scripts/secureboot-generate-keys.sh [--output-dir PATH] [--force]
```

**Parameters**:
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `--output-dir` | Path | No | `/var/lib/sbctl` | Directory to store generated keys |
| `--force` | Flag | No | false | Overwrite existing keys if present |

**Exit Codes**:
| Code | Meaning | When |
|------|---------|------|
| 0 | Success | All keys generated successfully |
| 1 | Pre-condition failed | sbctl not installed or not running as root |
| 2 | Keys already exist | Keys found in output directory and --force not specified |
| 3 | Generation failed | sbctl create-keys command failed |
| 4 | Permission error | Cannot write to output directory |

**Standard Output** (JSON format):
```json
{
  "status": "success",
  "ownerGUID": "8ec4b2c3-dc7f-4362-b9a3-0cc17e5a34cd",
  "keysGenerated": {
    "PK": {
      "privateKey": "/var/lib/sbctl/keys/PK/PK.key",
      "publicKey": "/var/lib/sbctl/keys/PK/PK.pem",
      "authFile": "/var/lib/sbctl/keys/PK/PK.auth",
      "eslFile": "/var/lib/sbctl/keys/PK/PK.esl"
    },
    "KEK": {
      "privateKey": "/var/lib/sbctl/keys/KEK/KEK.key",
      "publicKey": "/var/lib/sbctl/keys/KEK/KEK.pem",
      "authFile": "/var/lib/sbctl/keys/KEK/KEK.auth",
      "eslFile": "/var/lib/sbctl/keys/KEK/KEK.esl"
    },
    "db": {
      "privateKey": "/var/lib/sbctl/keys/db/db.key",
      "publicKey": "/var/lib/sbctl/keys/db/db.pem",
      "authFile": "/var/lib/sbctl/keys/db/db.auth",
      "eslFile": "/var/lib/sbctl/keys/db/db.esl"
    }
  },
  "durationSeconds": 3
}
```

**Standard Error** (when exit code != 0):
```json
{
  "status": "error",
  "code": 2,
  "message": "Keys already exist at /var/lib/sbctl/keys/. Use --force to overwrite.",
  "existingKeys": ["/var/lib/sbctl/keys/PK/PK.key", "/var/lib/sbctl/keys/KEK/KEK.key", "/var/lib/sbctl/keys/db/db.key"]
}
```

**Side Effects**:
- Creates directories: `/var/lib/sbctl/keys/{PK,KEK,db}/`
- Creates files with permissions: `*.key` (600), `*.pem` (644), `*.auth` (644), `*.esl` (644)
- Generates `/var/lib/sbctl/GUID` with random UUID

**Pre-conditions**:
- `sbctl` command available in PATH
- Running as root (UID 0)
- Output directory parent exists and is writable
- Firmware not required (key generation works offline)

**Post-conditions**:
- 12 files created (4 files × 3 key types)
- GUID file created with valid UUID
- All private keys have 600 permissions
- Success Criteria SC-001: Completes in <30 seconds

**Example Usage**:
```bash
# Default location
sudo scripts/secureboot-generate-keys.sh

# Custom location (for VM-specific keys)
sudo scripts/secureboot-generate-keys.sh --output-dir /vms/test-vm/secureboot

# Force regeneration
sudo scripts/secureboot-generate-keys.sh --force
```

---

## Contract 2: secureboot-enroll-keys.sh

### Purpose
Enroll generated Secure Boot keys into UEFI firmware, transitioning from Setup Mode to User Mode.

### Interface

**Command**:
```bash
scripts/secureboot-enroll-keys.sh [--key-dir PATH] [--microsoft] [--verify-only]
```

**Parameters**:
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `--key-dir` | Path | No | `/var/lib/sbctl` | Directory containing keys to enroll |
| `--microsoft` | Flag | No | false | Include Microsoft OEM certificates (for physical hardware) |
| `--verify-only` | Flag | No | false | Check Setup Mode without enrolling (dry-run) |

**Exit Codes**:
| Code | Meaning | When |
|------|---------|------|
| 0 | Success | Keys enrolled successfully, now in User Mode |
| 1 | Pre-condition failed | sbctl not installed, not root, or keys not found |
| 2 | Not in Setup Mode | Firmware already in User Mode (PK enrolled) |
| 3 | Enrollment failed | sbctl enroll-keys command failed |
| 4 | Verification failed | Enrollment appeared successful but firmware still in Setup Mode |

**Standard Output** (JSON format):
```json
{
  "status": "success",
  "preEnrollment": {
    "setupMode": true,
    "secureBoot": false,
    "pkEnrolled": false
  },
  "postEnrollment": {
    "setupMode": false,
    "secureBoot": true,
    "pkEnrolled": true,
    "kekEnrolled": true,
    "dbEnrolled": true
  },
  "microsoftKeysIncluded": false,
  "durationSeconds": 7
}
```

**Standard Error** (when exit code != 0):
```json
{
  "status": "error",
  "code": 2,
  "message": "Firmware not in Setup Mode. SetupMode variable is 0 (already enrolled).",
  "currentState": {
    "setupMode": false,
    "secureBoot": true,
    "pkEnrolled": true
  },
  "suggestion": "Reset to Setup Mode using: bin/virtual-machine --reset-setup-mode <vm-name>"
}
```

**Side Effects**:
- Writes to UEFI firmware variables: `PK`, `KEK`, `db`, and optionally Microsoft keys
- Automatically transitions `SetupMode` from 1 to 0
- Automatically enables `SecureBoot` (1)
- Permanent change to firmware NVRAM

**Pre-conditions**:
- `sbctl` command available in PATH
- Running as root (UID 0)
- Keys exist in key-dir (generated by secureboot-generate-keys.sh)
- Firmware in Setup Mode (`SetupMode` variable == 1)
- `/sys/firmware/efi/efivars/` mounted

**Post-conditions**:
- `SetupMode` variable == 0
- `SecureBoot` variable == 1
- `PK`, `KEK`, `db` variables populated with enrolled keys
- Firmware enforces signature verification on boot
- Success Criteria SC-002: Completes in <60 seconds

**Example Usage**:
```bash
# Enroll custom keys only (VM recommended)
sudo scripts/secureboot-enroll-keys.sh

# Enroll with Microsoft certificates (physical hardware)
sudo scripts/secureboot-enroll-keys.sh --microsoft

# Verify Setup Mode without enrolling
sudo scripts/secureboot-enroll-keys.sh --verify-only

# Use custom key location
sudo scripts/secureboot-enroll-keys.sh --key-dir /vms/test-vm/secureboot
```

---

## Contract 3: secureboot-verify.sh

### Purpose
Verify Secure Boot status and return structured output for test automation.

### Interface

**Command**:
```bash
scripts/secureboot-verify.sh [--format json|text] [--expected-mode setup|user|disabled]
```

**Parameters**:
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `--format` | Enum | No | `text` | Output format: `json` (structured) or `text` (human-readable) |
| `--expected-mode` | Enum | No | none | Fail if mode doesn't match expected value |

**Exit Codes**:
| Code | Meaning | When |
|------|---------|------|
| 0 | Success / Match | Verification succeeded, matches expected mode (if specified) |
| 1 | Unknown state | Cannot determine Secure Boot status |
| 2 | Setup Mode | Firmware in Setup Mode (no PK enrolled) |
| 3 | Disabled | Secure Boot disabled in firmware settings |
| 10 | Expected mismatch | Mode doesn't match --expected-mode parameter |

**Standard Output** (text format):
```
Secure Boot Status: enabled (user)
Setup Mode: user
Firmware: UEFI 2.70 (EDK II 1.00)
TPM2 Support: yes
Keys Enrolled: PK, KEK, db
```

**Standard Output** (JSON format):
```json
{
  "status": "user",
  "enforcing": true,
  "firmware": {
    "type": "EDK II 1.00",
    "version": "2.70",
    "arch": "x64"
  },
  "variables": {
    "setupMode": 0,
    "secureBoot": 1,
    "pkEnrolled": true,
    "kekEnrolled": true,
    "dbEnrolled": true
  },
  "tpmAvailable": true,
  "verifiedAt": "2025-11-01T10:35:22Z",
  "verificationMethod": "bootctl"
}
```

**Standard Output** (Setup Mode):
```json
{
  "status": "setup",
  "enforcing": false,
  "firmware": {
    "type": "EDK II 1.00",
    "version": "2.70",
    "arch": "x64"
  },
  "variables": {
    "setupMode": 1,
    "secureBoot": 0,
    "pkEnrolled": false,
    "kekEnrolled": false,
    "dbEnrolled": false
  },
  "tpmAvailable": true,
  "verifiedAt": "2025-11-01T10:25:15Z",
  "verificationMethod": "bootctl"
}
```

**Side Effects**:
- None (read-only operation)

**Pre-conditions**:
- `bootctl` command available in PATH (systemd-boot)
- `/sys/firmware/efi/efivars/` mounted
- Running on UEFI system (not BIOS)

**Post-conditions**:
- None (stateless)
- Success Criteria SC-003: 100% accuracy in status reporting

**Fallback Behavior**:
If `bootctl` unavailable, script falls back to direct EFI variable reading:
```json
{
  "status": "user",
  "enforcing": true,
  "verificationMethod": "efi-variables",
  "variables": {
    "setupMode": 0,
    "secureBoot": 1
  },
  "note": "Limited verification - bootctl not available"
}
```

**Example Usage**:
```bash
# Human-readable output
scripts/secureboot-verify.sh

# JSON for parsing
scripts/secureboot-verify.sh --format json

# Verify expected state (exit 0 if match, 10 if mismatch)
scripts/secureboot-verify.sh --expected-mode user

# In test scripts
if scripts/secureboot-verify.sh --format json --expected-mode user; then
    echo "✓ Secure Boot enabled with custom keys"
else
    echo "✗ Secure Boot verification failed"
    exit 1
fi
```

---

## Contract 4: Python Test Integration (bin/test-deployment)

### Purpose
Integrate Secure Boot verification into automated VM deployment testing.

### Interface

**New Function**: `verify_secureboot_enabled()`

**Function Signature** (Python):
```python
def verify_secureboot_enabled() -> bool:
    """
    Verify Secure Boot is enabled with custom keys (not Setup Mode).

    Returns:
        True if Secure Boot enabled in User Mode, False otherwise

    Raises:
        SSHError: If cannot connect to VM
        TimeoutError: If verification takes >30 seconds
    """
```

**Implementation**:
```python
def verify_secureboot_enabled():
    """Verify Secure Boot is enabled with custom keys (not Setup Mode)"""
    print_info("Verifying Secure Boot status...")

    # Call verification script via SSH
    result = ssh_vm(
        "scripts/secureboot-verify.sh --format json --expected-mode user",
        check=False,
        capture=True,
        timeout=10
    )

    if result.returncode == 0:
        print_success("Secure Boot enabled with custom keys")

        # Parse JSON output
        status = json.loads(result.stdout)
        print_info(f"  Mode: {status['status']}")
        print_info(f"  Enforcing: {status['enforcing']}")
        print_info(f"  Keys: PK={status['variables']['pkEnrolled']}, "
                   f"KEK={status['variables']['kekEnrolled']}, "
                   f"db={status['variables']['dbEnrolled']}")
        return True
    elif result.returncode == 2:
        print_error("Secure Boot still in Setup Mode - enrollment failed")
        return False
    elif result.returncode == 3:
        print_error("Secure Boot disabled in firmware settings")
        return False
    else:
        print_error(f"Secure Boot verification failed with code {result.returncode}")
        return False
```

**Integration Point** in main() workflow:
```python
# After step: Deploy with nixos-anywhere
# Before step: Verify deployment

# Step: Verify Secure Boot Enabled
current_step += 1
print_step(current_step, total_steps, "Verifying Secure Boot enabled")

if not verify_secureboot_enabled():
    print_error("Secure Boot verification failed")
    print_info("Check VM console: virsh console keystone-test-vm")
    return 1
```

---

## Contract Dependencies

```
secureboot-generate-keys.sh
        ↓ (generates keys)
secureboot-enroll-keys.sh
        ↓ (enrolls keys)
secureboot-verify.sh
        ↓ (verifies enrollment)
bin/test-deployment (Python integration)
```

**Dependency Rules**:
1. Enrollment depends on generation (requires key files)
2. Verification is independent (can check any state)
3. Test integration depends on verification (calls verify script)

---

## Error Handling Patterns

All scripts follow consistent error handling:

**Success Path**:
```
[Pre-conditions checked] → [Operation executed] → [Post-conditions verified] → [Exit 0]
```

**Error Path**:
```
[Pre-conditions checked] → [Pre-condition failed] → [Error JSON to stderr] → [Exit 1-4]
                               ↓
                        [Operation executed] → [Operation failed] → [Error JSON] → [Exit 3]
                                                       ↓
                                                [Post-conditions verified] → [Verification failed] → [Error JSON] → [Exit 4]
```

**Error JSON Schema**:
```json
{
  "status": "error",
  "code": <exit-code>,
  "message": "<human-readable-description>",
  "context": {<additional-debugging-info>},
  "suggestion": "<how-to-fix>"
}
```

---

## Success Criteria Compliance

| Success Criterion | Contract Compliance |
|-------------------|---------------------|
| SC-001: Key generation <30s | Contract 1: durationSeconds field tracking |
| SC-002: Enrollment <60s | Contract 2: durationSeconds field tracking |
| SC-003: 100% verification accuracy | Contract 3: Reads authoritative firmware variables |
| SC-004: Test integration passes/fails | Contract 4: Python function returns boolean |
| SC-005: Clear error messages | All contracts: Structured error JSON with suggestions |

---

**Contract Status**: ✅ Complete - Ready for implementation
