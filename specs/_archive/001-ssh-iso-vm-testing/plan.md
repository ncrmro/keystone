# Implementation Plan: SSH-Enabled ISO with VM Testing

**Branch**: `001-ssh-iso-vm-testing` | **Date**: 2025-10-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/home/ncrmro/code/ncrmro/keystone/specs/001-ssh-iso-vm-testing/spec.md`

**Note**: This plan builds upon existing implementation in `feat/quickemu-server` branch.

## Summary

This feature provides an integrated VM testing workflow for Keystone ISOs with SSH access. Core ISO building and VM configuration already exist; this implementation adds lifecycle management commands, SSH connection helpers, and workflow automation to enable developers to test Keystone deployments efficiently in quickemu VMs.

## Technical Context

**Language/Version**: Bash 5.x (shell scripting), Nix 2.18+ (configuration)
**Primary Dependencies**: quickemu, qemu, openssh-client, coreutils
**Storage**: Filesystem-based (VM artifacts in `vms/`, ISOs in build output)
**Testing**: Manual integration testing, VM boot validation
**Target Platform**: Linux x86_64 (NixOS development environment)
**Project Type**: Single project (shell scripts + Nix integration)
**Performance Goals**: VM boot in <2 minutes, SSH connection in <30 seconds
**Constraints**: Must preserve existing quickemu config compatibility, minimal external dependencies
**Scale/Scope**: Developer tooling for single-user VM testing workflows

**Existing Implementation**:
- `bin/build-iso`: Bash script with SSH key embedding support
- `modules/iso-installer.nix`: NixOS module for SSH-enabled ISOs
- `vms/server.conf`: quickemu VM configuration
- `Makefile`: Basic VM launch targets

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. Declarative Infrastructure ✅
**Status**: PASS
**Compliance**: VM configuration uses declarative quickemu config files (`vms/server.conf`). ISO building references NixOS modules for declarative SSH configuration. All configuration is version-controlled and reproducible.

### II. Security by Default ✅
**Status**: PASS
**Compliance**:
- SSH key-based authentication (no passwords)
- Builds upon existing ISO installer with SSH hardening
- VM testing does not modify security defaults
- SSH keys embedded at build time, not runtime

### III. Modular Composability ✅
**Status**: PASS
**Compliance**:
- ISO building (`bin/build-iso`) is independent module
- VM management will be separate scripts in `bin/` or `scripts/`
- Each component can be used independently (build ISO, launch VM, manage lifecycle)
- Existing `modules/iso-installer.nix` follows modular architecture

### IV. Hardware Agnostic ✅
**Status**: PASS
**Compliance**: quickemu provides hardware abstraction for VM testing. Testing workflow is independent of deployment target hardware. ISOs generated work on any x86_64 system (VM or bare metal).

### V. Cryptographic Sovereignty ✅
**Status**: PASS
**Compliance**: User provides their own SSH keys. No key generation or escrow. Keys remain under user control throughout workflow.

### NixOS Module Standards ✅
**Status**: PASS
**Compliance**: Existing `modules/iso-installer.nix` follows NixOS module standards with proper options, assertions, and documentation. New work is shell scripting (tooling), not module development.

### Testing Requirements ⚠️
**Status**: PARTIAL
**Compliance**: Manual integration testing workflow. Automated boot validation not yet implemented.
**Mitigation**: Testing requirement applies to production modules, not developer tooling scripts.

**Overall Gate Status**: ✅ PASS - Feature aligns with all core principles. Testing gap acceptable for development tooling.

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
├── build-iso              # ✅ Existing: Build ISO with SSH keys
└── vm-manage              # 🆕 New: VM lifecycle management script

scripts/
└── vm/                    # 🆕 New: VM helper scripts (if needed)
    ├── wait-for-ssh.sh
    └── get-connection-info.sh

vms/
├── keystone-installer.iso # Build artifact (symlink or copy)
├── server.conf            # ✅ Existing: quickemu configuration
└── server/                # ✅ Existing: VM runtime artifacts
    ├── disk.qcow2
    ├── OVMF_VARS.fd
    ├── server.log
    ├── server.ports
    └── server.sh

Makefile                   # ✅ Existing: Updated with new VM targets

modules/
└── iso-installer.nix      # ✅ Existing: SSH configuration for ISO
```

**Structure Decision**: Single project with shell scripts in `bin/` for user-facing commands. Existing structure preserved. New `bin/vm-manage` script provides unified interface for VM lifecycle (start, stop, status, clean, ssh-info). Helper functions may be extracted to `scripts/vm/` if complexity warrants.

## Complexity Tracking

*No violations identified - all constitution checks passed.*

