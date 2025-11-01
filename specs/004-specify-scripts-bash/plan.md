# Implementation Plan: Secure Boot Custom Key Enrollment

**Branch**: `004-specify-scripts-bash` | **Date**: 2025-11-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/004-specify-scripts-bash/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

This feature implements custom Secure Boot key generation and enrollment for the Keystone test VM environment. The system will generate Platform Key (PK), Key Exchange Key (KEK), and signature database (db) keys, enroll them in UEFI firmware to transition from Setup Mode to User Mode, and provide automated verification integrated into the bin/test-deployment script. This establishes the cryptographic foundation for Secure Boot without installing lanzaboote.

## Technical Context

**Language/Version**: Python 3.x (test scripts), Bash (enrollment scripts), NixOS configuration language
**Primary Dependencies**: sbctl (Secure Boot key management), efivar/bootctl (EFI variable inspection), OVMF (UEFI firmware for VMs)
**Storage**: Filesystem (key files stored in /var/lib/sbctl or similar with root-only permissions), UEFI NVRAM (enrolled keys)
**Testing**: Python-based bin/test-deployment script with SSH-based verification, virsh for VM management
**Target Platform**: NixOS x86_64 in libvirt VM with UEFI Secure Boot (OVMF firmware), Setup Mode required
**Project Type**: Infrastructure tooling (shell scripts + Python test orchestration)
**Performance Goals**: Key generation <30s, enrollment <60s, verification immediate
**Constraints**: Must run in NixOS installer environment, requires Setup Mode firmware, no lanzaboote installation
**Scale/Scope**: Single VM test environment, 3 key types (PK/KEK/db), ~3-5 shell scripts + test integration

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. Declarative Infrastructure ✅ PASS

- **Gate**: All infrastructure configuration must be defined as code
- **Status**: PASS
- **Evidence**: Secure Boot key enrollment will be implemented as NixOS-compatible scripts callable from configuration, with test integration in bin/test-deployment (existing Python infrastructure)
- **Compliance**: Keys generated and enrolled during deployment can be managed declaratively through NixOS modules in future features

### II. Security by Default ✅ PASS

- **Gate**: Must implement encryption, TPM2, and secure boot where applicable
- **Status**: PASS
- **Evidence**: This feature directly implements Secure Boot custom key enrollment, establishing firmware-level trust chain. Keys stored with root-only permissions (FR-002). Integrates with existing TPM2 and LUKS encryption infrastructure.
- **Compliance**: Advances the "Security by Default" principle by enabling custom Secure Boot keys for the boot attestation chain

### III. Modular Composability ✅ PASS

- **Gate**: Features must be self-contained, composable modules
- **Status**: PASS
- **Evidence**:
  - P1 (key generation) is independently testable and usable
  - P2 (enrollment) can be tested with pre-generated keys
  - P3 (verification) works as standalone diagnostic
  - Scripts can be invoked independently or composed in test workflow
- **Compliance**: Each phase (generate/enroll/verify) is a discrete, reusable component

### IV. Hardware Agnostic ✅ PASS

- **Gate**: Must run on diverse hardware and support virtualized environments
- **Status**: PASS
- **Evidence**:
  - Targets UEFI firmware (standard across x86_64 platforms)
  - Tested in libvirt VMs with OVMF (industry-standard UEFI implementation)
  - Secure Boot enrollment process is firmware-agnostic (UEFI spec compliant)
- **Compliance**: Works in VMs and will work on bare-metal UEFI systems

### V. Cryptographic Sovereignty ✅ PASS

- **Gate**: Users must control all encryption keys
- **Status**: PASS
- **Evidence**:
  - Custom key generation (user-owned PK/KEK/db keys)
  - No vendor key enrollment (Microsoft keys optional via flag)
  - Private keys stored locally with restricted permissions
  - No external key escrow or third-party trust dependencies
- **Compliance**: Users maintain full control over Secure Boot trust chain

### NixOS-Specific Constraints ✅ PASS

**Module Development Standards**:
- Not applicable (shell scripts, not NixOS modules yet)
- Future: Can be wrapped in NixOS module with `enable` option

**Development Tooling** ✅ PASS:
- Uses bin/virtual-machine for VM creation (per Constitution v1.0.1)
- Integrates with bin/test-deployment for automated testing
- Uses bin/build-iso for installer preparation
- Follows standardized workflow patterns

**Testing Requirements** ✅ PASS:
- Build-time validation: scripts must execute without errors
- Boot testing: automated verification in bin/test-deployment
- Regression tests: Secure Boot status verification (FR-009, FR-010)

**Documentation Standards**:
- Deferred to implementation phase (quickstart.md will be generated in Phase 1)

### Summary

**Overall Status**: ✅ ALL GATES PASS

No constitutional violations. Feature aligns with all five core principles and NixOS-specific constraints. Advances security posture by enabling custom Secure Boot key enrollment while maintaining user sovereignty over cryptographic trust chain.

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
├── test-deployment              # Existing: Python orchestration script (modify for verification)
└── virtual-machine              # Existing: VM creation and management

scripts/
├── secureboot-generate-keys.sh  # New: Generate PK/KEK/db keys using sbctl
├── secureboot-enroll-keys.sh    # New: Enroll keys in UEFI firmware
└── secureboot-verify.sh         # New: Verify Secure Boot status (bootctl + EFI vars)

vms/
└── keystone-test-vm/            # Existing: VM artifacts directory
    └── secureboot/              # New: Store generated keys for test VM
        ├── keys/                # PK, KEK, db key pairs
        └── enrolled.flag        # Marker file indicating successful enrollment
```

**Structure Decision**: Infrastructure tooling pattern - shell scripts in `scripts/` directory for key operations, integration into existing `bin/test-deployment` Python script for orchestration. Key storage co-located with VM artifacts in `vms/keystone-test-vm/secureboot/` for test environment isolation.

## Complexity Tracking

*No constitutional violations - section not applicable.*

---

## Phase 0: Research - COMPLETE ✅

**Status**: Complete
**Artifacts**: `research.md`

### Research Outcomes

All technical unknowns resolved through web research and lanzaboote documentation review:

1. **Tool Selection**: sbctl chosen as primary tool (see research.md for rationale)
2. **Key Storage**: `/var/lib/sbctl/` confirmed as standard location
3. **Microsoft Certificates**: Custom-only enrollment recommended for VMs (--yes-this-might-brick-my-machine)
4. **Verification Method**: bootctl status as primary, EFI variables as fallback
5. **Test Integration**: Extend bin/test-deployment with SSH-based verification

**Key Decisions Documented**:
- Decision 1: Use sbctl (not efitools or direct UEFI manipulation)
- Decision 2: Store keys in /var/lib/sbctl
- Decision 3: NO Microsoft certificates in VM tests (sovereignty principle)
- Decision 4: bootctl for verification (fallback to od + EFI variables)
- Decision 5: Integration point in bin/test-deployment
- Decision 6: Generate keys during deployment (fresh keys per test)

**Performance Analysis**:
- Key generation: 2-5 seconds (within SC-001: <30s)
- Enrollment: 5-10 seconds (within SC-002: <60s)
- Verification: <1 second (within SC-003: immediate)

---

## Phase 1: Design & Contracts - COMPLETE ✅

**Status**: Complete
**Artifacts**: `data-model.md`, `contracts/script-interfaces.md`, `quickstart.md`

### Design Artifacts

**data-model.md**: Defines 4 key entities
1. **SecureBootKeyPair**: Cryptographic key files (PK/KEK/db)
2. **FirmwareVariable**: UEFI variables (SetupMode, SecureBoot, key databases)
3. **SecureBootStatus**: Aggregated firmware state (Setup/User/Disabled)
4. **KeyEnrollmentOperation**: Transaction representing enrollment workflow

**contracts/script-interfaces.md**: Defines 4 interface contracts
1. **secureboot-generate-keys.sh**: Generate PK/KEK/db using sbctl
2. **secureboot-enroll-keys.sh**: Enroll keys in firmware (Setup → User Mode)
3. **secureboot-verify.sh**: Verify status with JSON/text output
4. **bin/test-deployment integration**: Python function for automated testing

**quickstart.md**: Developer guide covering
- Prerequisites (NixOS, libvirtd, bin/virtual-machine)
- Step-by-step workflow (VM creation → key generation → enrollment → verification)
- Automated testing with bin/test-deployment
- Troubleshooting (Setup Mode reset, key conflicts, bootctl unavailable)
- Reference commands and architecture diagrams

### Agent Context Update

Updated `CLAUDE.md` with:
- Language: Python 3.x (test scripts), Bash (enrollment scripts), NixOS
- Dependencies: sbctl, efivar/bootctl, OVMF
- Storage: Filesystem (/var/lib/sbctl), UEFI NVRAM

---

## Phase 2: Task Generation - NOT IN SCOPE

**Note**: This plan document stops after Phase 1. Task generation is handled by the `/speckit.tasks` command (separate workflow).

**Next Steps for Implementation**:
1. Run `/speckit.tasks` to generate dependency-ordered tasks.md
2. Implement scripts per contracts/script-interfaces.md
3. Integrate verification into bin/test-deployment per Contract 4
4. Test workflow using quickstart.md guide

---

## Summary

**Planning Status**: ✅ COMPLETE (Phases 0-1)

**Deliverables**:
- ✅ Technical Context defined (NixOS, sbctl, Python, Bash)
- ✅ Constitution Check passed (all 5 principles + NixOS constraints)
- ✅ Project Structure documented (scripts/, bin/, vms/)
- ✅ Research completed (6 decisions, tool comparison, performance analysis)
- ✅ Data Model defined (4 entities, relationships, validation rules)
- ✅ Contracts defined (4 script interfaces with exit codes, JSON schemas)
- ✅ Quickstart Guide written (step-by-step workflow, troubleshooting)
- ✅ Agent Context updated (CLAUDE.md)

**Ready for**: Task generation (`/speckit.tasks`) and implementation

**Branch**: `004-specify-scripts-bash`
**Specification**: `specs/004-specify-scripts-bash/spec.md`

