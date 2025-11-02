# Research: Secure Boot Key Management for Keystone

**Date**: 2025-11-01
**Feature**: Secure Boot Custom Key Enrollment
**Status**: Complete

## Executive Summary

This research evaluates tools and approaches for implementing custom Secure Boot key generation, enrollment, and verification in Keystone's NixOS VM test environment.

**Primary Recommendation**: Use `sbctl` for all key management operations. It provides a streamlined workflow optimized for NixOS/lanzaboote integration.

**Key Decision**: Enroll custom keys only (no Microsoft certificates) in VM test environment, as VMs have no physical hardware option ROMs that require vendor signatures.

## Technology Decisions

### Decision 1: Key Management Tool

**Decision**: Use `sbctl` as the primary tool for Secure Boot key generation and enrollment.

**Rationale**:
- **NixOS Integration**: Available in nixpkgs, designed to work with lanzaboote
- **User-Friendly**: Clear command syntax with visual feedback (✔/✘ indicators)
- **Safety**: Explicit warning flag for custom-only enrollment (`--yes-this-might-brick-my-machine`)
- **Status Reporting**: Built-in `sbctl status` command for verification
- **Single-Command Operations**: Key generation and enrollment in one command each

**Alternatives Considered**:
1. **efitools (KeyTool, sign-efi-sig-list)**: Rejected due to complex multi-step workflow requiring manual file format conversions, UEFI shell access, and cryptic error messages
2. **Direct UEFI variable manipulation (efivar)**: Rejected as too dangerous (easy to brick firmware) and lacking key generation/signing capabilities

**Implementation**:
```bash
# Generate keys
sudo sbctl create-keys

# Enroll keys (custom only for VMs)
sudo sbctl enroll-keys --yes-this-might-brick-my-machine
```

---

### Decision 2: Key Storage Location

**Decision**: Store generated keys in `/var/lib/sbctl/` (sbctl default location).

**Rationale**:
- **Standard Location**: sbctl's default since v0.6+
- **Proper Permissions**: Private keys automatically created with 600 (root-only)
- **lanzaboote Compatibility**: Configure `boot.lanzaboote.pkiBundle = "/var/lib/sbctl"`
- **Separate from System Config**: Keys in /var (mutable state) not /etc (configuration)

**Alternatives Considered**:
1. **`/etc/secureboot`**: Rejected (legacy sbctl location, pre-v0.6)
2. **`vms/keystone-test-vm/secureboot`**: Rejected for production keys, but viable for VM-specific test keys

**Key File Structure**:
```
/var/lib/sbctl/
├── GUID                  # Owner UUID
├── keys/
│   ├── PK/              # Platform Key (PK.key, PK.pem, PK.auth, PK.esl)
│   ├── KEK/             # Key Exchange Key (KEK.key, KEK.pem, KEK.auth, KEK.esl)
│   └── db/              # Signature Database (db.key, db.pem, db.auth, db.esl)
└── files.db             # Signed file tracking database (JSON)
```

---

### Decision 3: Microsoft Certificate Policy

**Decision**: DO NOT include Microsoft certificates in VM test environment (custom keys only).

**Rationale**:
- **Cryptographic Sovereignty**: Aligns with Keystone Constitution Principle V (users control all keys)
- **No Hardware Dependencies**: VMs use emulated hardware with no physical option ROMs
- **Minimal Attack Surface**: Only code signed with user's keys can execute
- **Safe for Testing**: `--yes-this-might-brick-my-machine` flag safe in VMs (no physical firmware to brick)

**Exception for Physical Hardware**:
- Use `sbctl enroll-keys --microsoft` for bare-metal deployments
- Required for discrete GPUs, network cards, and Windows dual-boot
- Document as optional flag in production deployment guide

**Security Implications**:
- **Custom Only**: Maximum sovereignty, minimal trust dependencies
- **With Microsoft**: Hardware compatibility, extended trust to Microsoft CA
- **Keystone Philosophy**: Prioritize sovereignty in default configuration

---

### Decision 4: Verification Method

**Decision**: Use `bootctl status` as primary verification, with EFI variable fallback for troubleshooting.

**Rationale**:
- **Clear Output**: Human-readable "Secure Boot: enabled (user)" vs "disabled (setup)"
- **Always Available**: systemd-boot included in NixOS by default
- **Reliable**: Directly reads `/sys/firmware/efi/efivars/`
- **Comprehensive**: Also shows firmware version, TPM support

**Primary Verification**:
```bash
bootctl status
# Expected after enrollment:
#   Secure Boot: enabled (user)
#   Setup Mode: user
```

**Fallback Verification** (for troubleshooting):
```bash
# Check SetupMode variable directly
od --address-radix=n --format=u1 \
  /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c
# Last byte: 0 = user mode, 1 = setup mode
```

**Alternatives Considered**:
1. **`sbctl status`**: Viable alternative, shows same information
2. **Direct EFI variable reading**: Too cryptic for primary method, useful for debugging
3. **`dmesg | grep 'secure boot'`**: Insufficient (doesn't distinguish setup from disabled)

---

### Decision 5: Test Integration Point

**Decision**: Add verification steps to `bin/test-deployment` script after deployment completes.

**Rationale**:
- **Existing Infrastructure**: bin/test-deployment already orchestrates VM deployment
- **Python Framework**: Existing SSH-based verification pattern can be extended
- **Automated Testing**: Ensures Secure Boot status checked on every deployment
- **Fail Fast**: Test fails immediately if enrollment unsuccessful

**Integration Approach**:
```python
# Add to bin/test-deployment after deployment completes
def verify_secureboot_enabled():
    """Verify Secure Boot is enabled with custom keys (not Setup Mode)"""
    bootctl_output = ssh_vm("bootctl status", capture=True)

    if "Secure Boot: enabled (user)" in bootctl_output:
        print_success("Secure Boot enabled with custom keys")
        return True
    elif "Secure Boot: disabled (setup)" in bootctl_output:
        print_error("Still in Setup Mode - key enrollment failed")
        return False
    else:
        print_error("Unexpected Secure Boot status")
        return False
```

**Alternatives Considered**:
1. **Separate verification script**: Rejected (adds complexity, duplicate SSH logic)
2. **Manual verification**: Rejected (doesn't align with automated testing principle)

---

### Decision 6: Key Generation Timing

**Decision**: Generate keys during deployment in the NixOS installer environment, before enrollment.

**Rationale**:
- **Fresh Keys Per Deployment**: Each test run gets unique keys
- **Installer Availability**: sbctl available in Keystone installer ISO
- **Isolation**: Keys specific to test VM, not shared across deployments

**Workflow**:
1. VM boots from Keystone ISO (Setup Mode)
2. Deployment script SSHs to VM
3. Generate keys: `ssh root@vm 'sbctl create-keys'`
4. Deploy NixOS: `nixos-anywhere --flake .#test-server root@vm`
5. Enroll keys: `ssh root@vm 'sbctl enroll-keys --yes-this-might-brick-my-machine'`
6. Verify: `ssh root@vm 'bootctl status'`

**Alternatives Considered**:
1. **Pre-generated keys**: Rejected (reduces sovereignty, keys should be unique)
2. **Post-deployment generation**: Rejected (requires reboot, complicates workflow)

---

## Implementation Strategy

### Phase 1: Key Generation Script

Create `scripts/secureboot-generate-keys.sh`:
- Wrapper around `sbctl create-keys`
- Validates sbctl availability
- Confirms Setup Mode before generation
- Returns key location path

### Phase 2: Key Enrollment Script

Create `scripts/secureboot-enroll-keys.sh`:
- Wrapper around `sbctl enroll-keys --yes-this-might-brick-my-machine`
- Pre-enrollment verification (Setup Mode check)
- Post-enrollment verification (User Mode check)
- Error handling for enrollment failures

### Phase 3: Verification Script

Create `scripts/secureboot-verify.sh`:
- Checks `bootctl status` output
- Fallback to EFI variable reading
- Returns exit code: 0 (enabled), 1 (setup mode), 2 (disabled), 3 (unknown)
- Structured output for parsing by test scripts

### Phase 4: Test Integration

Update `bin/test-deployment`:
- Add new test step after deployment: "Verify Secure Boot Enabled"
- Call verification script via SSH
- Fail test if not in User Mode
- Log Secure Boot status to test output

---

## Performance Expectations

Based on research and typical sbctl behavior:

- **Key Generation**: 2-5 seconds (RSA4096 key pair generation)
- **Key Enrollment**: 5-10 seconds (firmware variable writes)
- **Verification**: <1 second (read EFI variables)
- **Total Overhead**: ~15-20 seconds added to deployment workflow

All within success criteria:
- SC-001: Key generation <30 seconds ✅
- SC-002: Enrollment <60 seconds ✅
- SC-003: Verification immediate ✅

---

## Risk Mitigation

### Risk 1: sbctl Not Available in Installer

**Mitigation**: Add sbctl to Keystone ISO module configuration
**Verification**: Test ISO build includes sbctl package
**Fallback**: Document efitools as backup (not recommended)

### Risk 2: Firmware Incompatibility

**Mitigation**: OVMF firmware is well-tested with sbctl
**Verification**: VM testing validates OVMF compatibility
**Impact**: Low (OVMF is standard UEFI implementation)

### Risk 3: Enrollment Failure (Partial)

**Mitigation**: Verification script checks all three conditions (PK, KEK, db enrolled)
**Recovery**: Reset to Setup Mode via `bin/virtual-machine --reset-setup-mode`
**Detection**: Post-enrollment verification catches partial enrollments

### Risk 4: Microsoft Key Confusion

**Mitigation**: Clear documentation of --microsoft flag and when to use it
**Testing**: VM tests use custom-only, production docs include Microsoft option
**Education**: Document security tradeoffs in quickstart.md

---

## Documentation Requirements

1. **Quickstart Guide** (Phase 1 deliverable): Developer guide for VM testing workflow
2. **Production Deployment Guide** (future): Include --microsoft flag for physical hardware
3. **Troubleshooting Guide** (future): Reset to Setup Mode, manual verification steps
4. **Architecture Decision Record** (this document): Rationale for sbctl choice

---

## References

- **sbctl Documentation**: https://github.com/Foxboron/sbctl
- **lanzaboote Quick Start**: https://github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md
- **NixOS Wiki - Secure Boot**: https://nixos.wiki/wiki/Secure_Boot
- **UEFI Spec 2.10 - Secure Boot**: https://uefi.org/specs/UEFI/2.10/32_Secure_Boot_and_Driver_Signing.html
- **Keystone Constitution v1.0.1**: `.specify/memory/constitution.md`
- **Previous Research**: `specs/003-secureboot-setup-mode/research.md` (OVMF Setup Mode)

---

**Research Status**: ✅ Complete - Ready for Phase 1 Design
