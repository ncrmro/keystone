# Implementation Plan: ZFS User Module

**Branch**: `007-zfs-user-module` | **Date**: 2025-11-04 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/home/ncrmro/code/ncrmro/keystone/specs/007-zfs-user-module/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Create a NixOS module that automatically provisions ZFS datasets for user home directories with delegated ZFS permissions. The module will integrate with the existing `rpool` ZFS pool from disko-single-disk-root, create datasets at `rpool/crypt/home/<username>`, grant users full permissions to manage their own dataset tree (create/destroy child datasets, snapshots, send/receive operations), and include automated verification in the deployment testing pipeline.

## Technical Context

**Language/Version**: Nix 2.18+ (NixOS 25.05)
**Primary Dependencies**:
- ZFS filesystem (already present via disko-single-disk-root)
- systemd activation scripts
- NixOS module system
**Storage**: ZFS pool `rpool` with encrypted `rpool/crypt` dataset (from disko module)
**Testing**: Integration tests in `bin/test-deployment` Python script
**Target Platform**: Linux server/client with ZFS support (x86_64)
**Project Type**: Single NixOS module
**Performance Goals**:
- Dataset creation < 5 seconds per user during system activation
- No impact on boot time (async activation where possible)
**Constraints**:
- Must not interfere with existing disko ZFS configuration
- Must be idempotent (safe to re-apply)
- Must validate ZFS pool exists before operations
**Scale/Scope**:
- Support 1-50 users per system initially
- Each user gets dedicated ZFS dataset with full delegation permissions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Alignment

**I. Declarative Infrastructure** ✅
- Module configuration will be fully declarative via NixOS options
- User definitions and ZFS properties specified as code
- Reproducible across different systems

**II. Security by Default** ✅
- ZFS delegation ensures users cannot access other users' datasets
- Permissions scoped strictly to each user's dataset tree
- Integrates with existing encrypted ZFS pool (rpool/crypt)

**III. Modular Composability** ✅
- Self-contained module at `modules/users/default.nix`
- Clear option interface (`keystone.zfsUsers`)
- Can be enabled/disabled independently
- Composes with server and client modules

**IV. Hardware Agnostic** ✅
- Works on any system with ZFS support
- No hardware-specific dependencies
- Integrates with existing pool regardless of underlying storage

**V. Cryptographic Sovereignty** ✅
- Uses pool-level encryption from disko module
- No additional key management required
- Users maintain control over their data within their datasets

### NixOS-Specific Standards

**Module Development Standards** ✅
- Will use `types.attrsOf` for user definitions
- Includes `enable` option for the feature
- Will add assertions for ZFS availability and pool existence
- Options will be documented with descriptions and examples

**Development Tooling** ✅
- Testing via `bin/virtual-machine` for VM-based testing
- Integration with `bin/test-deployment` for automated verification
- Compatible with `nixos-anywhere` deployment workflow

**Testing Requirements** ✅
- Build-time validation via `nix build`
- Runtime testing in VM via test-deployment script
- Verification of ZFS delegation permissions

**Documentation Standards** ✅
- Will provide option documentation in module
- Usage examples in spec.md and quickstart.md
- Comments explaining ZFS delegation decisions

### Gate Result: ✅ PASS

No violations detected. All core principles and NixOS standards are satisfied.

## Project Structure

### Documentation (this feature)

```
specs/007-zfs-user-module/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: ZFS delegation research
├── data-model.md        # Phase 1: Module options schema
├── quickstart.md        # Phase 1: Usage guide
└── tasks.md             # Phase 2: Implementation tasks (via /speckit.tasks)
```

### Source Code (repository root)

```
modules/
├── zfs-users/
│   └── default.nix      # Main module implementation

vms/
└── test-server/
    └── configuration.nix # Test configuration with zfs-users enabled

bin/
└── test-deployment      # Enhanced with ZFS user tests

flake.nix                # Add zfs-users module export
```

**Structure Decision**: Single module implementation following existing Keystone patterns. Module will be located at `modules/users/default.nix` and exported via flake outputs. Test integration adds checks to existing `bin/test-deployment` script.

## Complexity Tracking

*No violations requiring justification.*

## Phase 0: Research & Planning

### Research Topics

1. **ZFS Delegation Permissions**
   - Research: Complete list of ZFS permissions needed for full dataset management
   - Question: Which specific permissions are required for create, destroy, send, receive, mount?
   - Output: Documented permission set in research.md

2. **NixOS systemd Activation Scripts**
   - Research: Best practices for dataset creation during system activation
   - Question: Should dataset creation be in activation scripts or systemd services?
   - Output: Activation strategy decision in research.md

3. **Idempotent Dataset Creation**
   - Research: How to safely check if datasets exist and create only if missing
   - Question: Best ZFS commands for idempotent operations
   - Output: Implementation pattern in research.md

4. **NixOS Module Integration Patterns**
   - Research: How existing Keystone modules (client, server) structure user management
   - Question: Should this extend users.users or be separate?
   - Output: Module interface design in research.md

5. **Test Integration Patterns**
   - Research: How bin/test-deployment currently structures verification checks
   - Question: Best way to add user-context ZFS operations to test script
   - Output: Test strategy in research.md

### Research Agents

Dispatching 5 parallel research agents:
1. ZFS delegation permission matrix (create, destroy, send, receive, mount, snapshot)
2. NixOS activation script patterns for filesystem operations
3. Idempotent ZFS operations patterns
4. Keystone module user management patterns
5. Test deployment verification patterns

## Phase 1: Design & Contracts

**Prerequisites**: research.md complete with all NEEDS CLARIFICATION resolved

### Deliverables

1. **data-model.md**: Module options schema
   - User definition structure
   - ZFS property options
   - Delegation permission configuration
   - Module enable/disable options

2. **quickstart.md**: Usage guide
   - Basic configuration example
   - Advanced scenarios (quotas, compression)
   - User workflow examples (creating datasets, snapshots, backups)
   - Troubleshooting common issues

3. **Agent context update**
   - Run `.specify/scripts/bash/update-agent-context.sh claude`
   - Add ZFS delegation information
   - Add module structure details

### No API Contracts Required

This is a system-level NixOS module, not an API service. The "contract" is the NixOS module options interface, which will be documented in data-model.md.

## Post-Phase 1 Constitution Re-check

Will re-validate after design artifacts are complete:
- Verify module options follow NixOS conventions
- Confirm security isolation in delegation design
- Validate test coverage is sufficient

## Implementation Notes

### Key Design Decisions (Pending Research)

1. **Activation vs Service**: Determine whether dataset creation should happen in systemd activation scripts (synchronous) or dedicated systemd services (async)

2. **Permission Set**: Finalize exact `zfs allow` permission string based on research

3. **Error Handling**: Define behavior when ZFS pool doesn't exist or is unavailable

4. **Migration Path**: Clarify behavior when users already exist but don't have ZFS datasets

### Integration Points

1. **disko-single-disk-root**: Must ensure `rpool/crypt` dataset exists
2. **client/server modules**: Optional integration with user definitions
3. **bin/test-deployment**: Add verification steps after deployment success

### Risk Mitigation

1. **Pool Not Found**: Add assertions in module to check ZFS pool exists
2. **Permission Conflicts**: Research ZFS delegation inheritance to avoid conflicts
3. **Dataset Conflicts**: Check for existing datasets before attempting creation
4. **Test User Creation**: Ensure test VM configuration includes test users for verification

## Next Steps

1. ✅ Feature specification created (spec.md)
2. ✅ Implementation plan created (this file)
3. ⏳ Run Phase 0 research (generate research.md)
4. ⏳ Run Phase 1 design (generate data-model.md, quickstart.md)
5. ⏳ Update agent context
6. ⏳ Run Phase 2 task generation (`/speckit.tasks`)

---

**Status**: Planning complete, ready for Phase 0 research
