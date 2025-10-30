# Implementation Plan: Secure Boot Automation with Lanzaboote

**Branch**: `003-secureboot-automation` | **Date**: 2025-10-29 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-secureboot-automation/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Extend the existing test-deployment Python script to automate Secure Boot enrollment using lanzaboote after successful ZFS encrypted deployment. The script will detect UEFI Secure Boot capability, generate and enroll custom keys, verify the boot chain, and provide clear feedback on the security posture. This enables full end-to-end testing of Keystone's complete security stack (ZFS encryption + TPM2 + Secure Boot) without manual intervention.

## Technical Context

**Language/Version**: Python 3.11+ (existing test-deployment script), Nix (NixOS configuration)
**Primary Dependencies**:
- Python standard library (subprocess, time, pathlib, signal)
- SSH client for remote command execution
- socat for serial console communication
- lanzaboote (NixOS module for Secure Boot)
- NEEDS CLARIFICATION: Specific lanzaboote enrollment commands/API
- NEEDS CLARIFICATION: UEFI variable access methods in NixOS environment

**Storage**: N/A (script orchestration, state in VM firmware UEFI variables)
**Testing**: Manual test script execution, VM-based integration testing
**Target Platform**: Linux development machine controlling QEMU/KVM VMs with UEFI firmware (OVMF)
**Project Type**: Single project (test automation script extension)
**Performance Goals**: Complete full deployment with Secure Boot enrollment in <15 minutes
**Constraints**:
- Must work with existing VM configuration (vms/server.conf)
- Must preserve backward compatibility with current test workflow
- Must handle VMs without Secure Boot support gracefully
- NEEDS CLARIFICATION: VM firmware requirements (OVMF version, Secure Boot variable support)

**Scale/Scope**: Single test automation script (~600 LOC), adding ~200-300 LOC for Secure Boot phases

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. Declarative Infrastructure
**Status**: ✅ PASS
- Test script orchestrates NixOS configuration deployment
- Lanzaboote Secure Boot configuration will be declarative NixOS modules
- All configuration changes version controlled in the flake

### II. Security by Default
**Status**: ✅ PASS
- Feature explicitly enhances security posture by automating Secure Boot
- Completes the security stack: LUKS + ZFS encryption + TPM2 + Secure Boot
- Implements PCR-based boot attestation (requirement from constitution)
- Maintains zero-trust architecture principles

### III. Modular Composability
**Status**: ✅ PASS
- Lanzaboote is a self-contained NixOS module
- Can be enabled/disabled via configuration options
- Test script phases are independent (ZFS, unlock, SSH, Secure Boot)
- Graceful fallback when Secure Boot unsupported (optional feature)

### IV. Hardware Agnostic
**Status**: ✅ PASS
- Detection logic handles both Secure Boot capable and incapable platforms
- Works with QEMU/KVM VMs (development) and bare metal (production)
- Abstracts Secure Boot specifics through lanzaboote module options
- Same test workflow portable across different VM hypervisors

### V. Cryptographic Sovereignty
**Status**: ✅ PASS
- Generates custom Secure Boot keys (no vendor keys)
- Keys enrolled in user-controlled firmware
- User maintains complete control over trust anchors
- No external dependencies for key generation or enrollment

**Overall Assessment**: All constitutional principles satisfied. No violations requiring justification.

## Project Structure

### Documentation (this feature)

```
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
bin/
└── test-deployment              # Existing Python test script (will be extended)

vms/
├── server.conf                  # VM configuration
├── server.conf.example          # Example VM configuration
└── server/                      # Runtime VM artifacts
    ├── server.sh                # Generated QEMU startup script
    ├── disk.qcow2               # VM disk
    ├── OVMF_VARS.fd             # UEFI variables (Secure Boot state)
    └── server-serial.socket     # Serial console socket

examples/
└── test-server.nix              # Example NixOS configuration (will add lanzaboote config)

modules/
└── server/                      # Server module (potential lanzaboote integration point)

flake.nix                        # NixOS flake (lanzaboote input may be needed)
```

**Structure Decision**: Single project structure. The feature extends the existing `bin/test-deployment` Python script with new functions for Secure Boot enrollment phases. No new source directories needed - all changes are additions to the existing test automation script and NixOS configuration examples.

## Complexity Tracking

*No violations - section not applicable for this feature.*

