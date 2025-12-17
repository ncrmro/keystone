# Implementation Plan: Secure Boot Setup Mode for VM Testing

**Branch**: `003-secureboot-setup-mode` | **Date**: 2025-10-31 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-secureboot-setup-mode/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enable bin/virtual-machine to create VMs that boot into Secure Boot setup mode (UEFI firmware with Secure Boot enabled but no keys enrolled). Developers verify setup mode using `bootctl status` which shows "Secure Boot: setup". This enables reproducible Secure Boot testing for Keystone's installer and lanzaboote integration.

## Technical Context

**Language/Version**: Python 3.9+ (uv script shebang in bin/virtual-machine)
**Primary Dependencies**: libvirt-python (>=9.0.0), libvirt, QEMU with OVMF firmware
**Storage**: Filesystem (NVRAM files, disk images in vms/ directory)
**Testing**: Manual testing via `bootctl status` in VM, regression tests via boot validation
**Target Platform**: NixOS development workstations with libvirt enabled
**Project Type**: Single script enhancement (bin/virtual-machine)
**Performance Goals**: VM creation under 30 seconds, setup mode verification under 2 minutes
**Constraints**: Requires OVMF Secure Boot firmware available in Nix store, libvirt daemon running
**Scale/Scope**: Single developer tool enhancement, affects VM creation workflow only

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Alignment

- ✅ **I. Declarative Infrastructure**: VM configuration remains declarative via bin/virtual-machine script parameters. NVRAM state is automatically managed but reproducible.
- ✅ **II. Security by Default**: This feature directly supports Secure Boot testing, which is a core security requirement. Ensures VMs start in setup mode for proper key enrollment testing.
- ✅ **III. Modular Composability**: Enhancement is contained within bin/virtual-machine script. Does not affect other modules or components.
- ✅ **IV. Hardware Agnostic**: Uses OVMF firmware which runs on any x86_64 system with KVM support. NixOS provides consistent OVMF paths.
- ✅ **V. Cryptographic Sovereignty**: Enables testing of custom Secure Boot key enrollment, supporting users' control over their trust anchors.

### NixOS-Specific Constraints Alignment

- ✅ **Module Development Standards**: N/A - This is a script enhancement, not a NixOS module
- ✅ **Development Tooling**: Enhances the existing bin/virtual-machine primary VM driver per constitution
- ✅ **Testing Requirements**: Feature includes manual verification via `bootctl status` and can be validated with boot tests
- ✅ **Documentation Standards**: Will update bin/virtual-machine help text and create example usage documentation

### Gate Status: ✅ PASS (Initial)

All core principles align. No violations to justify. This feature strengthens Security by Default (Principle II) by enabling proper Secure Boot testing workflows.

---

## Post-Design Constitution Re-Check

*Re-evaluated after Phase 1 design completion*

### Design Artifacts Review

- ✅ **research.md**: Comprehensive technical research on OVMF firmware, NVRAM state, and Secure Boot modes
- ✅ **data-model.md**: Clear entity model with VM Configuration, NVRAM State, and OVMF Firmware
- ✅ **contracts/cli-interface.md**: CLI contract maintaining backward compatibility
- ✅ **quickstart.md**: Developer-focused guide with verification steps

### Constitution Alignment (Post-Design)

- ✅ **I. Declarative Infrastructure**: Design maintains declarative approach via libvirt XML configuration
- ✅ **II. Security by Default**: Implementation strengthens Secure Boot testing capabilities
- ✅ **III. Modular Composability**: Changes isolated to bin/virtual-machine, no cross-module dependencies
- ✅ **IV. Hardware Agnostic**: Uses NixOS OVMF firmware paths, portable across x86_64 systems
- ✅ **V. Cryptographic Sovereignty**: Enables custom key enrollment testing, no vendor lock-in

### NixOS Standards Compliance

- ✅ **Development Tooling**: Enhances primary VM driver (bin/virtual-machine) per constitution
- ✅ **Testing Requirements**: Includes verification method (`bootctl status`) and validation approach
- ✅ **Documentation Standards**: Provides quickstart guide, CLI contract, and technical references

### Final Gate Status: ✅ PASS

Design artifacts fully align with constitution. Ready for task generation phase (`/speckit.tasks`).

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
└── virtual-machine          # Python script to enhance (existing file)

vms/
└── <vm-name>/
    ├── disk.qcow2          # VM disk image (existing pattern)
    └── OVMF_VARS.fd        # NVRAM file (existing, needs setup mode initialization)

docs/
└── examples/
    └── vm-secureboot-testing.md  # New: Usage examples for setup mode testing
```

**Structure Decision**: This is an enhancement to the existing bin/virtual-machine script. No new directories or major structural changes needed. The script already manages VM creation and NVRAM files; this feature ensures NVRAM is initialized to setup mode (no pre-enrolled keys). Documentation will be added to docs/examples/ to show the new workflow.

## Complexity Tracking

*No violations - section not applicable.*

