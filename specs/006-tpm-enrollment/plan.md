# Implementation Plan: TPM-Based Disk Encryption Enrollment

**Branch**: `006-tpm-enrollment` | **Date**: 2025-11-03 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/006-tpm-enrollment/spec.md`

## Summary

Implement a TPM2-based disk encryption enrollment system for Keystone that automatically configures TPM unlock after users replace the default "keystone" LUKS password with either a recovery key or custom password. The system provides first-boot notification of TPM enrollment status and ensures Secure Boot is enabled before allowing TPM enrollment.

**Technical Approach**: Create a new NixOS module (`modules/tpm-enrollment`) that integrates with the existing secure-boot and disko-single-disk-root modules. The module will provide systemd service units for enrollment status detection, interactive enrollment scripts, and automatic TPM configuration using systemd-cryptenroll.

## Technical Context

**Language/Version**: Nix (NixOS 25.05) + Bash scripting
**Primary Dependencies**: systemd-cryptenroll, cryptsetup, sbctl (Secure Boot), systemd initrd
**Storage**: LUKS2-encrypted ZFS volume (/dev/zvol/rpool/credstore)
**Testing**: VM testing via bin/virtual-machine with TPM2 emulation, integration tests with nixos-anywhere deployment
**Target Platform**: x86_64-linux with UEFI firmware, TPM2 hardware or emulation
**Project Type**: Single NixOS module with activation scripts and systemd services
**Performance Goals**: Enrollment completion within 5 minutes, boot unlock under 30 seconds
**Constraints**: Must preserve existing boot process, zero data loss risk, graceful degradation without TPM hardware
**Scale/Scope**: Single-user systems, typical deployment: 1-10 systems per user

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Alignment

**I. Declarative Infrastructure** ✅
- Implementation uses NixOS module system (keystone.tpmEnrollment namespace)
- All configuration defined in module options
- Reproducible across hardware via module composition

**II. Security by Default** ✅
- Enforces Secure Boot as prerequisite for TPM enrollment
- Removes default "keystone" password after enrollment
- Validates PCR measurements (PCRs 1,7) for boot integrity
- No change to existing encryption architecture (LUKS + ZFS native encryption)

**III. Modular Composability** ✅
- Self-contained module with clear dependencies (secureBoot, disko)
- Optional enable flag: `keystone.tpmEnrollment.enable`
- Integrates with existing modules without modification
- Can be used independently in server or client configurations

**IV. Hardware Agnostic** ✅
- Graceful degradation when TPM2 unavailable (VMs, older hardware)
- Works with both bare-metal and virtualized environments
- No vendor-specific TPM implementation dependencies

**V. Cryptographic Sovereignty** ✅
- Users retain full control of recovery keys and custom passwords
- No key escrow or external dependencies
- TPM-sealed keys remain on local hardware
- Clear documentation on when backup credentials are needed

### NixOS-Specific Constraints

**Module Development Standards** ✅
- Will use `mkEnableOption` for keystone.tpmEnrollment.enable
- Will include assertions for Secure Boot and TPM prerequisites
- Will document all options with descriptions and examples
- Will use activation scripts for first-boot provisioning

**Development Tooling** ✅
- Testing with bin/virtual-machine (TPM2 emulation enabled)
- ISO building with bin/build-iso for deployment testing
- nixos-anywhere for VM installation validation

**Testing Requirements** ✅
- Build-time validation (nix build succeeds)
- VM boot testing with TPM emulation
- Manual enrollment workflow testing
- PCR mismatch recovery testing

**Documentation Standards** ✅
- Module options documented in NixOS manual format
- Usage examples in docs/ directory
- Recovery scenarios documented for users
- Migration guide (none needed - new feature)

### Complexity Assessment

**No violations detected** - all constitution requirements satisfied.

## Project Structure

### Documentation (this feature)

```
specs/006-tpm-enrollment/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
modules/
└── tpm-enrollment/
    ├── default.nix           # Main module definition with options and config
    ├── enrollment-check.sh   # Script to detect TPM enrollment status
    ├── enroll-recovery.sh    # Interactive recovery key generation
    ├── enroll-password.sh    # Interactive custom password setup
    └── enroll-tpm.sh         # Automatic TPM enrollment after credential setup

bin/
└── (existing scripts - no changes)

docs/
└── tpm-enrollment.md         # User-facing documentation (enrollment guide)

examples/
└── tpm-enrollment/
    └── configuration.nix     # Example configuration with TPM enrollment

tests/
└── tpm-enrollment/
    └── test.nix              # Integration test configuration
```

**Structure Decision**: Single NixOS module structure chosen because:
1. This is a system-level security feature, not a multi-component application
2. All functionality is cohesive (TPM enrollment workflow)
3. Follows existing Keystone module pattern (secure-boot, disko-single-disk-root)
4. Scripts co-located with module definition for maintainability

## Complexity Tracking

*No constitution violations - this section is empty*
