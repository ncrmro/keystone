# API Contracts: TPM Enrollment

**Feature**: 006-tpm-enrollment
**Date**: 2025-11-03

## No API Contracts

This feature does not define traditional API contracts (REST/GraphQL endpoints) because:

1. **System-Level Module**: TPM enrollment is a system security feature, not an application service
2. **CLI-Based Interface**: User interaction occurs via command-line tools, not HTTP APIs
3. **Local Operations**: All enrollment operations are local to the system (LUKS, TPM hardware)
4. **NixOS Integration**: Configuration is declarative via NixOS modules, not API calls

## User Interface Contracts

While there are no network API contracts, the feature does define user interface contracts:

### Command-Line Interface

**Recovery Key Enrollment**:
```bash
keystone-enroll-recovery
```
- **Input**: User confirmation via ENTER key
- **Output**: Recovery key (8 groups of 4 characters), enrollment status messages
- **Exit Codes**: 0 (success), 1 (failure - Secure Boot not enabled), 2 (failure - no TPM), 3 (failure - enrollment error)

**Custom Password Enrollment**:
```bash
keystone-enroll-password
```
- **Input**: Password (stdin, silent), password confirmation (stdin, silent)
- **Output**: Validation messages, enrollment status
- **Exit Codes**: 0 (success), 1 (validation failure), 2 (prerequisite failure), 3 (enrollment error)

**Direct TPM Enrollment** (Advanced):
```bash
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/zvol/rpool/credstore
```
- **Input**: None (uses current Secure Boot PCR values)
- **Output**: systemd-cryptenroll status messages
- **Exit Codes**: Standard systemd-cryptenroll exit codes

### Login Banner Contract

**Display Conditions**:
- **When**: Every interactive shell login
- **If**: TPM not enrolled (no `/var/lib/keystone/tpm-enrollment-complete` marker OR no TPM token in LUKS header)
- **Format**: ASCII box-drawing with Unicode emoji
- **Content**: Security warning + actionable commands + documentation link

**Suppression Conditions**:
- **When**: TPM enrolled (marker file exists AND TPM token in LUKS header)
- **Behavior**: No banner displayed

### State File Contract

**Marker File**: `/var/lib/keystone/tpm-enrollment-complete`

**Format**:
```
Enrollment completed: <ISO 8601 timestamp>
Method: <recovery-key|custom-password|manual>
SecureBoot: <enabled|disabled>
KeySlot: <number>
```

**Semantics**:
- Presence: TPM enrollment complete
- Absence: TPM not enrolled or enrollment removed
- Content: Metadata for debugging (not parsed by system)

## LUKS Device Contract

**Target Device**: `/dev/zvol/rpool/credstore`

**Pre-conditions**:
- Device exists (created by disko module during installation)
- Device is LUKS2 encrypted
- Default password "keystone" is in keyslot 0

**Post-conditions** (after enrollment):
- Recovery key OR custom password in keyslot 1+
- TPM token in systemd-tpm2 token slot
- Default password removed from keyslot 0

**Invariants**:
- At least one keyslot must remain active (LUKS prevents removing last keyslot)
- Maximum 32 keyslots (LUKS2 specification)

## TPM Hardware Contract

**Required Capabilities**:
- TPM 2.0 specification compliant
- SHA-256 PCR bank available
- PCR 7 accessible for read/extend operations
- Sealing/unsealing operations supported

**PCR Binding**:
- **PCR 7**: Secure Boot certificates and policies
- **Measurement**: Taken at enrollment time, validated at unlock time
- **Mismatch Behavior**: TPM unlock fails, fallback to password/recovery key

## NixOS Module Contract

**Module Name**: `keystone.tpmEnrollment`

**Options**:
```nix
keystone.tpmEnrollment = {
  enable = lib.mkEnableOption "TPM enrollment module";
  # Future options TBD during implementation
};
```

**Provides**:
- Login banner via `/etc/profile.d/tpm-enrollment-warning.sh`
- Enrollment command scripts in system PATH
- State directory `/var/lib/keystone/` via systemd-tmpfiles

**Dependencies**:
- `keystone.secureBoot.enable = true` (Secure Boot must be configured)
- `keystone.disko.enable = true` (credstore volume must exist)

---

## Summary

This feature uses **local system interfaces** (filesystem, LUKS, TPM hardware) rather than network APIs. The "contracts" are command-line interfaces, file formats, and hardware expectations, not HTTP endpoints or GraphQL schemas.

For implementation details, see:
- [data-model.md](../data-model.md) - File and state structures
- [quickstart.md](../quickstart.md) - User-facing command workflows
- [research.md](../research.md) - Technical decisions and rationale

---

**Document Version**: 1.0
**Date**: 2025-11-03
**Status**: Phase 1 Complete
