# Implementation Plan: TUI Local Installer

**Branch**: `011-tui-local-installer` | **Date**: 2025-12-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/011-tui-local-installer/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Add local installation capability to the Keystone TUI installer, enabling users to complete NixOS installation directly from the ISO without requiring a second machine. The installer will detect disks, offer encrypted or unencrypted installation, create a NixOS flake configuration, and deploy NixOS—all through an interactive terminal interface.

## Technical Context

**Language/Version**: TypeScript 5.x (transpiled to JavaScript, Node.js runtime)
**Primary Dependencies**: React 18.3.1, Ink 5.0.1, ink-text-input 6.0.0, ink-select-input 6.0.0, ink-spinner 5.0.0
**Storage**: ZFS with LUKS credstore (encrypted path) or plain ext4 (unencrypted path)
**Testing**: Manual VM testing via `bin/virtual-machine`, ISO boot testing
**Target Platform**: x86_64-linux (NixOS live ISO environment)
**Project Type**: Single TUI application integrated into NixOS ISO
**Performance Goals**: Full installation < 15 minutes (excluding downloads), responsive TUI (< 100ms input feedback)
**Constraints**: Must run in live ISO RAM environment, limited to tools available in minimal ISO, must support offline installation for local mode
**Scale/Scope**: Single user interactive installer, ~10 screens in TUI flow

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Declarative Infrastructure** | ✅ PASS | Creates NixOS flake configuration at `~/nixos-config/hosts/{hostname}/` |
| **II. Security by Default** | ✅ PASS | Offers ZFS+LUKS+TPM2 as primary option, warns when TPM2 unavailable |
| **III. Modular Composability** | ✅ PASS | Extends existing installer module, user chooses server/client module |
| **IV. Hardware Agnostic** | ✅ PASS | Detects arbitrary disks, generates hardware-configuration.nix |
| **V. Cryptographic Sovereignty** | ✅ PASS | User controls encryption choice, no external key escrow |
| **Development Tooling** | ✅ PASS | Uses bin/virtual-machine for testing, bin/build-iso for ISO creation |
| **Testing Requirements** | ✅ PASS | VM testing documented, boot testing required |
| **Documentation Standards** | ✅ PASS | Will update docs/installer-tui.md with new capabilities |

**Pre-Design Gate**: PASS - No violations detected.

## Project Structure

### Documentation (this feature)

```text
specs/011-tui-local-installer/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# Existing TUI application (will be extended)
packages/keystone-installer-ui/
├── src/
│   ├── index.tsx              # Entry point (unchanged)
│   ├── App.tsx                # Main component (extend with new screens)
│   ├── network.ts             # Network utilities (unchanged)
│   ├── disk.ts                # NEW: Disk detection and operations
│   ├── installation.ts        # NEW: NixOS installation orchestration
│   ├── config-generator.ts    # NEW: Flake/config file generation
│   └── types.ts               # NEW: Shared TypeScript types
├── package.json               # Add new dependencies if needed
├── package-lock.json          # Lock file
├── tsconfig.json              # TypeScript config (unchanged)
└── default.nix                # Nix package definition

# NixOS modules (may need updates)
modules/
├── iso-installer.nix          # May need additional packages for local install
└── disko-single-disk-root/    # Reference for encrypted installation
    ├── default.nix            # Disko configuration module
    └── example.nix            # Usage example

# Build scripts
bin/
├── build-iso                  # ISO builder (may need updates for offline support)
└── virtual-machine            # VM testing (unchanged)

# Documentation updates
docs/
├── installer-tui.md           # Update with local installation workflow
└── testing-installer-tui.md   # Update with local installation test cases
```

**Structure Decision**: Extend existing `packages/keystone-installer-ui/` with new TypeScript modules for disk operations, installation orchestration, and configuration generation. Keep single TUI application structure—no new packages needed.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations detected. The implementation stays within existing patterns:
- Single TUI application (no additional packages)
- Uses established disko module for encrypted installations
- Follows existing NixOS module patterns for configuration generation

---

## Post-Design Constitution Re-Check

*Re-evaluated after Phase 1 design completion.*

| Principle | Status | Design Evidence |
|-----------|--------|-----------------|
| **I. Declarative Infrastructure** | ✅ PASS | `config-generator.ts` produces complete NixOS flake with `flake.nix`, `hosts/{hostname}/default.nix`, `disk-config.nix`, `hardware-configuration.nix`. Configuration is version-controlled via `initGitRepository()`. |
| **II. Security by Default** | ✅ PASS | `disk-operations.ts:hasTPM2()` detects TPM2 availability. Encrypted path uses existing `disko-single-disk-root` module with ZFS+LUKS+TPM2. Unencrypted path requires explicit user selection. Warning displayed when TPM2 unavailable. |
| **III. Modular Composability** | ✅ PASS | Design adds 3 new TypeScript modules (`disk.ts`, `config-generator.ts`, `installation.ts`) that compose with existing `network.ts`. Generated configs import Keystone modules (`diskoSingleDiskRoot`, `server`/`client`). |
| **IV. Hardware Agnostic** | ✅ PASS | `detectDisks()` uses `lsblk -J` to enumerate any block device. `nixos-generate-config` handles hardware detection. By-id paths used for stable device addressing. |
| **V. Cryptographic Sovereignty** | ✅ PASS | User explicitly chooses encryption. No external key escrow. TPM2 keys stay on device. Password fallback keeps user in control when TPM unavailable. |
| **Development Tooling** | ✅ PASS | `quickstart.md` documents use of `bin/virtual-machine`, `bin/build-iso`, `bin/build-vm`. Testing workflow follows constitution guidelines. |
| **Testing Requirements** | ✅ PASS | Design includes VM testing via `bin/virtual-machine`, ISO boot testing, and integration testing in `quickstart.md`. |
| **Documentation Standards** | ✅ PASS | `quickstart.md` provides development guide. Contracts include JSDoc. Updates to `docs/installer-tui.md` specified. |

**Post-Design Gate**: PASS - All principles satisfied with concrete design evidence.

---

## Generated Artifacts

| Artifact | Path | Status |
|----------|------|--------|
| Implementation Plan | `specs/011-tui-local-installer/plan.md` | ✅ Complete |
| Research Document | `specs/011-tui-local-installer/research.md` | ✅ Complete |
| Data Model | `specs/011-tui-local-installer/data-model.md` | ✅ Complete |
| API Contracts | `specs/011-tui-local-installer/contracts/` | ✅ Complete |
| Quickstart Guide | `specs/011-tui-local-installer/quickstart.md` | ✅ Complete |
| Agent Context | `CLAUDE.md` (auto-updated) | ✅ Complete |

**Next Step**: Run `/speckit.tasks` to generate actionable task breakdown for implementation.
