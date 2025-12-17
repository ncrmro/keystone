# Research: TPM-Based Disk Encryption Enrollment

**Feature**: TPM Enrollment for Keystone credstore
**Date**: 2025-11-03
**Branch**: 006-tpm-enrollment

## Overview

This document consolidates research findings for implementing TPM2-based disk encryption enrollment in Keystone. Research covers three critical areas:

1. systemd-cryptenroll integration and PCR selection
2. First-boot notification mechanisms
3. Password validation standards

---

## 1. systemd-cryptenroll Integration

### Decision: PCR 7 Only (Secure Boot State)

**Command Syntax**:
```bash
systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=7 \
  --wipe-slot=empty \
  /dev/zvol/rpool/credstore
```

### Rationale

**PCR 7 Selection**: After analyzing systemd documentation and TPM security best practices, PCR 7 (Secure Boot certificates) provides the optimal balance:

- **Update Resilient**: Only changes when Secure Boot keys are modified, not on routine system updates
- **Security Adequate**: Prevents booting with Secure Boot disabled or tampered keys
- **Validated Pattern**: Current disko module already uses `tpm2-measure-pcr=yes` expecting this approach

**Why NOT PCR 1** (originally in spec):
- PCR 1 (firmware configuration) changes on BIOS setting modifications
- Causes automatic unlock failures after legitimate hardware tuning
- Contradicts systemd best practices: "It is typically not advisable to use PCRs such as 0 and 2, since the program code they cover should already be covered indirectly through the certificates measured into PCR 7"

**Why NOT PCR 11** (kernel image):
- Changes on every kernel update → re-enrollment required after each `nixos-rebuild`
- Requires signed PCR policies infrastructure (deferred to future enhancement)
- Incompatible with automatic system updates

### PCR Comparison Matrix

| PCR | Content | Change Frequency | Impact on Auto-Unlock |
|-----|---------|------------------|----------------------|
| 0 | Firmware code | Firmware updates | ❌ Breaks on updates |
| 1 | Firmware config | BIOS changes | ❌ Breaks on tuning |
| 7 | Secure Boot certs | Key re-enrollment | ✅ Stable during updates |
| 11 | Kernel image (UKI) | Every kernel update | ❌ Requires re-enrollment |

### Integration with Existing Disko Module

**Current Configuration** (modules/disko-single-disk-root/default.nix:111-114):
```nix
luks.devices.credstore = {
  device = "/dev/zvol/rpool/credstore";
  crypttabExtraOpts = [
    "tpm2-measure-pcr=yes"  # Extends PCR 15 after unlock
    "tpm2-device=auto"      # Enables TPM unlock attempt
  ];
};
```

**No changes required** - existing crypttab options already support TPM unlock when keyslot exists.

### Enrollment Status Detection

```bash
# Method 1: systemd-cryptenroll (recommended)
systemd-cryptenroll /dev/zvol/rpool/credstore | grep -q "tpm2"

# Method 2: cryptsetup luksDump (detailed)
cryptsetup luksDump /dev/zvol/rpool/credstore | grep -q "systemd-tpm2"
```

### Error Handling Patterns

**No TPM Device**:
```bash
if ! systemd-cryptenroll --tpm2-device=list &>/dev/null; then
  echo "ERROR: No TPM2 device found"
  echo "This system does not have TPM2 hardware or emulation enabled"
  exit 1
fi
```

**Secure Boot Not Enabled**:
```bash
if ! bootctl status | grep -q "Secure Boot: enabled"; then
  echo "ERROR: Secure Boot is not enabled"
  echo "TPM enrollment requires Secure Boot to be active in User Mode"
  exit 1
fi
```

**Enrollment Failure**:
```bash
if ! systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/zvol/rpool/credstore; then
  echo "ERROR: TPM enrollment failed"
  # Check for keyslot exhaustion, TPM lockout, PCR incompatibility
fi
```

### Recovery Scenarios

**PCR 7 Mismatch** (Secure Boot keys changed):
1. Boot prompts for password (automatic unlock fails)
2. User enters recovery key or custom password
3. System boots successfully
4. User re-enrolls TPM with new PCR 7 values:
   ```bash
   systemd-cryptenroll --wipe-slot=tpm2 /dev/zvol/rpool/credstore
   systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/zvol/rpool/credstore
   ```

**TPM Hardware Failure**:
- Automatic unlock fails (no TPM device)
- Recovery key/custom password provides fallback
- System continues working (TPM optional)

### Alternatives Considered

**PCR 1+7** (Firmware Config + Secure Boot): Rejected due to PCR 1 brittleness with BIOS settings

**PCR 7+11** (Secure Boot + Kernel): Deferred to future with signed PCR policies

**Comprehensive Binding (0+2+4+7)**: Rejected - breaks on all updates, contradicts systemd best practices

---

## 2. First-Boot Notification Mechanism

### Decision: Shell Profile Integration

**Implementation**: System-wide shell profile script with persistent state tracking

**Components**:
1. Script: `/etc/profile.d/tpm-enrollment-warning.sh`
2. State marker: `/var/lib/keystone/tpm-enrollment-complete`

### Rationale

**Why Shell Profile**:
- **Universal Coverage**: Works for both server (SSH) and client (desktop terminal)
- **Native Integration**: Standard Linux login notification mechanism
- **Immediate Visibility**: Banner appears on first interactive shell after login
- **Non-Blocking**: Never prevents login or requires interaction
- **NixOS Friendly**: Declarative configuration via `environment.etc`

**Why NOT Alternatives**:
- **PAM Module (pam_exec)**: Could block login on script errors, too complex
- **greetd Banner**: Only works for client configs, cannot be conditionally suppressed
- **/etc/motd**: Static content, not conditional
- **systemd User Service**: Timing issues, reliability concerns
- **systemd-firstboot**: Misaligned with NixOS patterns, over-engineered

### State Management Strategy

**Marker File Creation**: Enrollment scripts create `/var/lib/keystone/tpm-enrollment-complete` after successful TPM enrollment

**Validation Logic**:
```bash
# Check for marker file
if [[ -f /var/lib/keystone/tpm-enrollment-complete ]]; then
  # Marker exists - validate against LUKS header
  if cryptsetup luksDump /dev/zvol/rpool/credstore | grep -q "systemd-tpm2"; then
    # TPM enrolled, marker valid - suppress banner
    exit 0
  else
    # Marker invalid (manual removal) - show banner, recreate marker
    rm -f /var/lib/keystone/tpm-enrollment-complete
  fi
fi

# No marker or validation failed - check if TPM actually enrolled
if cryptsetup luksDump /dev/zvol/rpool/credstore | grep -q "systemd-tpm2"; then
  # Self-healing: TPM enrolled but marker missing
  mkdir -p /var/lib/keystone
  echo "auto-detected $(date -Iseconds)" > /var/lib/keystone/tpm-enrollment-complete
  exit 0
fi

# TPM not enrolled - show banner
show_enrollment_warning_banner
```

### Banner Design

```
┌──────────────────────────────────────────────────────────────┐
│ ⚠️  TPM ENROLLMENT NOT CONFIGURED                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│ Your system is using the default LUKS password "keystone"   │
│ which is publicly known and provides NO security.           │
│                                                              │
│ To secure your encrypted disk:                              │
│   1. Generate recovery key:                                 │
│      $ sudo keystone-enroll-recovery                        │
│                                                              │
│   2. OR set custom password:                                │
│      $ sudo keystone-enroll-password                        │
│                                                              │
│ Documentation: /usr/share/doc/keystone/tpm-enrollment.md    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Edge Cases

**Non-Interactive Shells**: Suppress banner when `$PS1` is unset (prevents breaking `ssh host 'command'`)

**Manual TPM Enrollment**: Self-healing detection creates marker file if TPM enrolled externally

**Missing Credstore Device**: Graceful failure (no banner if cannot verify)

**Multi-User Systems**: Banner shows for all users (system-level security concern)

### Implementation

**NixOS Module Configuration**:
```nix
environment.etc."profile.d/tpm-enrollment-warning.sh" = {
  text = ''
    # Only run for interactive shells
    [[ -z "$PS1" ]] && return

    # Check enrollment status and show banner if needed
    ${./enrollment-check.sh}
  '';
  mode = "0555";
};
```

**Marker File Management**:
```nix
systemd.tmpfiles.rules = [
  "d /var/lib/keystone 0755 root root -"
];
```

---

## 3. Password Validation Standards

### Decision: Length-Focused Validation

**Rules Enforced**:
1. Minimum 12 characters (FR-008 requirement)
2. Maximum 64 characters (NIST 2025 guideline)
3. No character class complexity requirements
4. Cannot be "keystone" or other prohibited values
5. Password confirmation must match

### Rationale: Security vs Usability

**Why 12 Characters Minimum**:
- **Entropy**: 12 mixed alphanumeric = ~71 bits entropy
- **LUKS Key Stretching**: PBKDF2/Argon2id makes offline attacks expensive (2M+ iterations)
- **Research Finding**: "Passwords with complexity requirements become near-impossible to crack via brute-force techniques when over 15 characters in length"

**Why NO Complexity Requirements**:
- **NIST 2025 Guidance**: Modern standards moved away from mandatory character classes
- **Predictable Patterns**: Forced complexity leads to "Password1!" type patterns
- **Memorability**: This is a recovery password - users may not use it for months/years
- **Length > Complexity**: "coffeemorninglaptop" (19 chars) > "P@ssw0rd" (8 chars)

**Recovery Context Considerations**:
- Password used infrequently (only when TPM unlock fails)
- Must be memorable after long periods without use
- Too complex = forgotten = permanent data loss
- Users should write down and store securely (offline storage acceptable for disk encryption)

### Validation Implementation

```bash
validate_password() {
    local password="$1"
    local length="${#password}"

    # Check empty/whitespace
    if [[ -z "${password// /}" ]]; then
        echo "ERROR: Password cannot be empty"
        return 1
    fi

    # Check minimum length
    if (( length < 12 )); then
        echo "ERROR: Password must be at least 12 characters"
        echo "       Current: ${length} characters"
        echo "       Example: 'coffee-laptop-morning' (21 characters)"
        return 1
    fi

    # Check maximum length
    if (( length > 64 )); then
        echo "ERROR: Password exceeds maximum of 64 characters"
        return 1
    fi

    # Check prohibited
    if [[ "${password,,}" == "keystone" ]]; then
        echo "ERROR: Password 'keystone' is not allowed (publicly known)"
        return 1
    fi

    return 0
}
```

### Error Messages: User-Friendly Approach

**Too Short**:
```
ERROR: Password must be at least 12 characters

Your password is only 8 characters long. Disk encryption requires
longer passwords to protect against automated attacks.

Examples of strong passwords:
  - Memorable passphrase: "coffee-laptop-morning" (21 characters)
  - Random characters: "xK9mP2vL4nQ8wR" (14 characters)
  - Simple but long: "MyBlueServer2024" (16 characters)
```

**Passwords Don't Match**:
```
ERROR: Passwords do not match

The password and confirmation you entered are different.
Please try again carefully.
```

**Success**:
```
✓ Password validated successfully

IMPORTANT: Store this password securely. You will need it if:
  - Firmware or bootloader updates change boot measurements
  - TPM hardware fails or is reset
  - Emergency system recovery is required
```

### Optional Enhancement: Password Strength Scoring

If `libpwquality` (pwscore) is available, provide non-blocking warnings:

```bash
check_password_strength() {
    if command -v pwscore &>/dev/null; then
        local score=$(echo "$password" | pwscore 2>&1 || true)
        if [[ "$score" =~ ^[0-9]+$ ]] && (( score < 30 )); then
            echo "WARNING: Password strength is low (score: ${score}/100)"
            echo "         Consider using a longer passphrase"
        fi
    fi
}
```

**Note**: Strength warnings are informational only - never block password acceptance based on score.

### Alternatives Considered

**Strict Complexity Requirements**: Rejected - contradicts NIST 2025 guidelines, reduces memorability

**Very High Minimum (20+ chars)**: Rejected - overkill given LUKS key stretching, high cognitive burden for recovery

**Recovery Key Only (No Custom Password)**: Rejected - spec provides user choice (User Story 3)

---

## Summary: Implementation Decisions

| Component | Decision | Key Points |
|-----------|----------|-----------|
| **TPM PCRs** | PCR 7 only | Secure Boot state, update-resilient, spec update needed |
| **Enrollment Command** | `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --wipe-slot=empty` | Standard approach, safe credential handling |
| **Status Detection** | `systemd-cryptenroll` + `cryptsetup luksDump` | Dual validation, self-healing |
| **First-Boot Notification** | Shell profile script + state marker | Universal coverage, NixOS-friendly |
| **State Tracking** | `/var/lib/keystone/tpm-enrollment-complete` | Persistent, inspectable, self-validates |
| **Password Min Length** | 12 characters | FR-008 compliance, adequate entropy |
| **Password Max Length** | 64 characters | NIST 2025 guideline |
| **Password Complexity** | None required | Length prioritized, NIST 2025 alignment |
| **Password Validation** | Bash script loop | Simple, reliable, clear error messages |

## Spec Updates Required

**Original Assumption 7** (spec.md:141):
> PCR 1 (firmware configuration) and PCR 7 (Secure Boot state) are sufficient

**Recommended Update**:
> PCR 7 (Secure Boot state) is sufficient for most use cases while maintaining maximum resilience to firmware updates. PCR 1 (firmware configuration) is intentionally excluded due to brittleness with BIOS setting changes.

**Original FR-006**:
> System MUST enroll TPM unlock using PCRs 1 and 7

**Recommended Update**:
> System MUST enroll TPM unlock using PCR 7 (Secure Boot state)

## References

### systemd-cryptenroll
- [systemd-cryptenroll man page](https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html)
- [ArchWiki: systemd-cryptenroll](https://wiki.archlinux.org/title/Systemd-cryptenroll)
- [Lennart Poettering: Unlocking LUKS2 with TPM2](https://0pointer.net/blog/unlocking-luks2-volumes-with-tpm2-fido2-pkcs11-security-hardware-on-systemd-248.html)

### TPM and PCRs
- [ArchWiki: Trusted Platform Module](https://wiki.archlinux.org/title/Trusted_Platform_Module)
- [Linux TPM PCR Registry](https://uapi-group.org/specifications/specs/linux_tpm_pcr_registry/)

### Password Standards
- NIST SP 800-63B (Digital Identity Guidelines)
- OWASP Password Guidelines
- Mozilla Security Guidelines

### Keystone Codebase
- Disko module: modules/disko-single-disk-root/default.nix
- Secure Boot module: modules/secure-boot/default.nix
- Spec: specs/006-tpm-enrollment/spec.md

---

**Document Version**: 1.0
**Date**: 2025-11-03
**Status**: Phase 0 Complete - Ready for Phase 1 Design
