# Implementation Plan: Secure Boot Integration with Disko

**Branch**: `005-secureboot-disko-integration` | **Date**: 2025-11-02 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-secureboot-disko-integration/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Integrate Secure Boot key generation and enrollment directly into the disko deployment process using preCreateHook and postCreateHook, enabling lanzaboote to sign the bootloader during initial nixos-anywhere deployment. This eliminates the need for post-installation provisioning and ensures Secure Boot is fully functional from the first boot.

## Technical Context

**Language/Version**: Nix (NixOS 25.05)
**Primary Dependencies**:
  - nixpkgs.sbctl (Secure Boot key management)
  - lanzaboote (NixOS Secure Boot implementation) - NEEDS CLARIFICATION: flake input setup
  - disko (declarative disk partitioning)
**Storage**: /var/lib/sbctl/keys (Secure Boot keys on target system)
**Testing**: bin/test-deployment (VM-based integration testing)
**Target Platform**: UEFI x86_64 systems (VMs and physical hardware)
**Project Type**: NixOS module (infrastructure configuration)
**Performance Goals**: Key generation < 30 seconds during deployment
**Constraints**:
  - Must work in nixos-anywhere deployment context
  - UEFI firmware must be in Setup Mode initially
  - Keys must be generated before NixOS configuration build
**Scale/Scope**: Single NixOS module affecting ~3 existing modules

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Alignment

✅ **I. Declarative Infrastructure**: Secure Boot configuration defined as NixOS module
✅ **II. Security by Default**: Implements Secure Boot attestation with signed bootloader
✅ **III. Modular Composability**: New secure-boot module composes with existing disko module
✅ **IV. Hardware Agnostic**: Works on VMs and physical UEFI systems
✅ **V. Cryptographic Sovereignty**: User generates and controls their own Secure Boot keys

### NixOS-Specific Constraints

✅ **Module Development Standards**: Will follow standard NixOS module patterns
✅ **Development Tooling**: Uses bin/virtual-machine for testing
✅ **Testing Requirements**: Integration with bin/test-deployment
✅ **Documentation Standards**: Will include examples and migration guides

**Gate Status**: PASS - All principles satisfied

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
modules/
├── secure-boot/           # New Secure Boot module
│   └── default.nix       # Module with lanzaboote integration
├── disko-single-disk-root/
│   └── default.nix       # Updated with Secure Boot hooks
└── server/
    └── default.nix       # Updated to include secure-boot module

flake.nix                 # Add lanzaboote input
vms/test-server/
└── configuration.nix     # Enable secure-boot module

bin/
├── test-deployment       # Remove post-install-provisioner call
└── post-install-provisioner  # (deprecated after this change)
```

**Structure Decision**: NixOS module structure - adding a new `modules/secure-boot` module that integrates with the existing disko module through hooks. The module will be automatically included in server configurations.

## Complexity Tracking

*No constitution violations - section not applicable*

