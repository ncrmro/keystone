# Implementation Plan: NixOS-Anywhere VM Installation

**Branch**: `002-nixos-anywhere-vm-install` | **Date**: 2025-10-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-nixos-anywhere-vm-install/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Add nixos-anywhere deployment capability to install a minimal Keystone server configuration to VMs for testing and validation. This enables automated deployment from a development machine to a VM booted from the Keystone ISO, creating a reproducible installation workflow that leverages existing server and disko modules with proper encryption and security configuration.

## Technical Context

**Language/Version**: Nix (unstable), NixOS 25.05
**Primary Dependencies**:
- nixos-anywhere (deployment tool)
- disko (disk partitioning/formatting)
- ZFS (filesystem with native encryption)
- systemd (boot orchestration)
- QEMU/libvirt (VM testing infrastructure)

**Storage**: ZFS with native encryption, LUKS-encrypted credstore, optional encrypted swap
**Testing**: NixOS VM integration tests, manual SSH verification, deployment reproducibility tests
**Target Platform**: x86_64-linux (VMs and bare metal servers)
**Project Type**: NixOS infrastructure configuration (declarative modules)
**Performance Goals**:
- Complete deployment in under 10 minutes
- System boot in under 2 minutes
- SSH access available within 2 minutes of boot

**Constraints**:
- Must work in VM environments without hardware TPM2
- Must handle graceful degradation from TPM2 to password-based unlock
- Must use existing Keystone modules without modification
- Must support deployment over SSH to installer ISO

**Scale/Scope**:
- Single server deployment configuration
- Approximately 3-5 new files (flake configuration, example config, testing scripts)
- Integration with existing 4 NixOS modules (server, disko, iso-installer)
- Support for both VM testing and production deployment workflows

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. Declarative Infrastructure ✅

**Status**: PASS

- Configuration defined as NixOS flake with declarative nixosConfiguration
- All settings version controlled in Git
- Fully reproducible via nixos-anywhere deployment
- Clear change history through Git commits

**Compliance**: This feature extends the existing declarative model by adding a deployment target configuration.

### II. Security by Default ✅

**Status**: PASS

- Leverages existing disko-single-disk-root module with LUKS + ZFS encryption
- TPM2 integration with graceful fallback for VMs
- Secure boot compatibility (using existing lanzaboote configuration)
- SSH-only access with public key authentication

**Compliance**: Reuses existing security infrastructure without reducing security posture.

### III. Modular Composability ✅

**Status**: PASS

- Uses existing server and disko modules without modification
- New deployment configuration is a composition of existing modules
- Clear module boundaries maintained
- No new module dependencies introduced

**Compliance**: Pure composition of existing modules - exemplifies modular design.

### IV. Hardware Agnostic ✅

**Status**: PASS

- Works in both VM and bare-metal environments
- Disk device specified via configuration option
- Handles TPM2 absence gracefully (VM scenario)
- Same configuration deploys to any x86_64 target

**Compliance**: Explicit goal to support VM testing before production deployment.

### V. Cryptographic Sovereignty ✅

**Status**: PASS

- User controls all SSH keys and encryption keys
- Keys managed through credstore pattern (existing)
- No external key management dependencies
- TPM2 is optional, password fallback available

**Compliance**: Maintains user control of all cryptographic material.

## Gates Summary

**Overall Status**: ✅ ALL GATES PASS

All constitutional principles are satisfied. This feature is a pure composition of existing modules into a new deployment configuration. No new security risks or architectural complexity introduced.

---

## Post-Design Re-evaluation

**Date**: 2025-10-22 (After Phase 1 completion)

All constitutional gates **remain PASS** after design phase:

✅ **I. Declarative Infrastructure**: Design confirms flake-based deployment, version controlled configuration
✅ **II. Security by Default**: Design reuses existing encryption, no security compromises introduced
✅ **III. Modular Composability**: Design confirms pure module composition, no new modules created
✅ **IV. Hardware Agnostic**: Design handles both VM and bare-metal via disk device configuration
✅ **V. Cryptographic Sovereignty**: Design maintains user control of all keys and credentials

**Design artifacts confirm**: No violations, no complexity justification needed.

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
keystone/
├── flake.nix                          # Add new nixosConfiguration for test-server
├── modules/
│   ├── server/                        # Existing - no changes
│   ├── client/                        # Existing - no changes
│   ├── disko-single-disk-root/        # Existing - no changes
│   └── iso-installer.nix              # Existing - no changes
├── examples/
│   └── test-server.nix                # NEW: Example minimal server config
├── scripts/
│   ├── deploy-vm.sh                   # NEW: Helper script for VM deployment
│   └── verify-deployment.sh           # NEW: Post-deployment verification
└── vms/                               # Existing VM infrastructure
    └── test-server/                   # NEW: VM-specific configs
        └── configuration.nix          # NEW: Test server NixOS config
```

**Structure Decision**:

This is a **NixOS infrastructure project** (not application code). The structure follows NixOS conventions:

- **flake.nix**: Add `nixosConfigurations.test-server` output for deployment target
- **examples/**: Reference configurations showing how to use Keystone modules
- **scripts/**: Automation for common deployment and verification tasks
- **vms/**: VM-specific configurations for testing deployments

No new modules are created - this feature purely composes existing modules into a new deployment configuration.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

**No violations**: All constitutional gates pass. This section is not applicable.

