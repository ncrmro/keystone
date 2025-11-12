# Implementation Plan: GitHub Actions VM CI for Copilot Agent Iteration

**Branch**: `011-github-actions-vm-ci` | **Date**: 2025-11-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/011-github-actions-vm-ci/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Enable GitHub Copilot agents to iteratively develop and test NixOS system configurations by providing automated VM provisioning in GitHub Actions with structured feedback. The system creates isolated virtual machine environments, builds configurations from flake definitions, executes full lifecycle testing (build → install → boot → service validation), and returns JSON-formatted results that agents can parse to refine configurations.

Primary approach: Leverage `nixos-rebuild build-vm` for fast VM creation without full encryption/secure boot overhead, combined with GitHub Actions workflows specifically designed for agent interaction with structured input/output interfaces.

## Technical Context

**Language/Version**: Nix 2.x (NixOS 25.05 channel)
**Primary Dependencies**: nixpkgs, nixos-rebuild, QEMU/KVM, GitHub Actions, qemu-kvm-action
**Storage**: QCOW2 disk images for VM persistence, GitHub Actions artifact storage
**Testing**: nixos-rebuild build-vm for VM validation, nix flake check for syntax validation
**Target Platform**: GitHub Actions runners (Linux, x86_64, hardware acceleration required)
**Project Type**: Infrastructure/CI pipeline (GitHub Actions workflows + NixOS configurations)
**Performance Goals**: Test completion within 15 minutes per iteration, 3+ iterations within 30 minutes
**Constraints**: GitHub Actions timeout (360 minutes max), runner resource limits (7GB RAM, 14GB disk), hardware acceleration required
**Scale/Scope**: Single VM per workflow run, queued execution per branch, 10-20 iterations expected per feature development cycle

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Alignment

**I. Declarative Infrastructure** ✅
- Workflow definitions stored as YAML in `.github/workflows/`
- VM configurations defined in flake.nix using NixOS modules
- All infrastructure changes version controlled
- Reproducible across different CI environments

**II. Security by Default** ⚠️ PARTIAL COMPLIANCE - JUSTIFIED
- **Violation**: CI testing VMs skip full disk encryption, TPM2, and secure boot
- **Justification**: Testing environments prioritize speed over security. Production deployments still enforce all security measures. CI VMs are ephemeral (destroyed after each run) and never hold sensitive data.
- **Mitigation**: Clearly document that bin/build-vm and CI workflows are for testing only

**III. Modular Composability** ✅
- Workflow can test both server and client configurations independently
- VM configurations compose existing Keystone modules (server, client, home-manager)
- Testing infrastructure reusable for different configuration types

**IV. Hardware Agnostic** ✅
- Workflow tests configurations that deploy to diverse hardware
- QEMU provides virtualized environment abstracting physical hardware
- Same configurations validated in CI can deploy to bare-metal or cloud

**V. Cryptographic Sovereignty** ✅
- CI workflow does not generate or manage user encryption keys
- Testing focuses on configuration correctness, not key management
- Production deployments maintain full cryptographic sovereignty

### NixOS-Specific Constraints

**Module Development Standards** ✅
- Workflow tests modules following Keystone standards
- Build validation ensures proper option types and assertions
- No new NixOS modules introduced (workflow-only change)

**Development Tooling** ⚠️ DEVIATION - JUSTIFIED
- **Standard**: Constitution prescribes `bin/virtual-machine` as primary VM driver
- **Deviation**: CI workflow uses `nixos-rebuild build-vm` and GitHub Actions-native tooling
- **Justification**:
  - `bin/virtual-machine` requires libvirt and complex UEFI firmware setup unavailable in GitHub Actions
  - `nixos-rebuild build-vm` is built into NixOS, requires no external dependencies
  - CI environment is ephemeral and disposable (different from local development)
  - `bin/build-vm` script already uses this approach successfully for fast iteration
- **Impact**: Local development continues using `bin/virtual-machine` for full-stack testing; CI uses lighter-weight approach

**Testing Requirements** ✅
- Workflow includes `nix build` validation
- VM boot testing on virtualized hardware
- Configurations validated before merge

**Documentation Standards** ✅
- Workflow files include inline documentation
- Usage examples provided in quickstart.md
- Rationale documented in plan.md

### Gate Result

**PASS WITH JUSTIFIED VIOLATIONS**

Two intentional deviations documented:
1. Security by Default: CI VMs skip encryption/TPM/secure boot for speed (production unaffected)
2. Development Tooling: CI uses `nixos-rebuild build-vm` instead of `bin/virtual-machine` (local development unaffected)

Both deviations serve valid purposes (CI speed and compatibility) and do not compromise the core mission of secure, reproducible infrastructure.

### Post-Phase 1 Re-Evaluation

**Date**: 2025-11-12

After completing Phase 1 design (data model, contracts, quickstart), re-evaluating constitution compliance:

**Core Principles**: ✅ No changes. Design adheres to all principles with documented justifications.

**NixOS-Specific Constraints**:
- ✅ **Module Development Standards**: No new modules introduced. Testing infrastructure only.
- ✅ **Development Tooling**: Design confirms `bin/build-vm` pattern is appropriate for CI (lighter than `bin/virtual-machine`).
- ✅ **Testing Requirements**: Workflow includes build validation, boot testing, and service validation.
- ✅ **Documentation Standards**: quickstart.md provides usage examples, contracts define schemas, data-model.md documents entities.

**New Observations**:
1. **Structured Output Schema** (contracts/test-result-schema.json): Ensures consistent, parseable feedback for Copilot agents. Aligns with declarative infrastructure principle.
2. **GitHub Actions Concurrency**: Native feature meets FR-008 requirements exactly. No custom queueing logic needed.
3. **Artifact Storage**: 90-day retention provides sufficient history for debugging and analysis.

**Final Gate Result**: **PASS** - Design fully complies with constitution. Justified deviations remain valid after Phase 1.

## Project Structure

### Documentation (this feature)

```text
specs/011-github-actions-vm-ci/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── workflow-schema.yml         # GitHub Actions workflow definition
│   ├── test-result-schema.json     # Structured test output format
│   └── vm-config-schema.json       # VM configuration parameters
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
.github/
└── workflows/
    ├── copilot-vm-test.yml         # Main workflow for Copilot agent testing
    └── verify-build.yml             # Existing PR validation workflow

bin/
├── build-vm                         # Existing: Fast VM testing script
├── build-iso                        # Existing: ISO builder
├── virtual-machine                  # Existing: Libvirt VM driver
└── test-vm-ssh                      # Existing: SSH helper for test VMs

vms/
├── build-vm-terminal/
│   └── configuration.nix            # Existing: Terminal test config
├── build-vm-desktop/
│   └── configuration.nix            # Existing: Desktop test config
└── ci-test/                         # NEW: CI-specific test configuration
    └── configuration.nix            # Minimal config for CI testing

modules/
├── server/                          # Existing: Server modules under test
├── client/                          # Existing: Client modules under test
└── ...                              # Other existing modules

tests/
└── ci/                              # NEW: CI testing helpers
    ├── check-boot-status.sh         # Verify VM booted successfully
    ├── validate-services.sh         # Check critical services running
    └── format-results.sh            # Convert logs to JSON schema
```

**Structure Decision**: Hybrid approach using existing `bin/build-vm` patterns with new GitHub Actions workflows. The repository already has strong VM testing foundations (build-vm-terminal, build-vm-desktop configurations). We extend this pattern with a CI-specific workflow and minimal helper scripts for structured output formatting.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Security by Default: CI VMs skip encryption/TPM/secure boot | Fast iteration for Copilot agents requires <15min test cycles; full security stack adds 10-20min overhead | Running full security stack in CI would exceed time budgets (30min for 3 iterations), making the agent workflow impractical. Production deployments are unaffected. |
| Development Tooling: Use nixos-rebuild build-vm instead of bin/virtual-machine | GitHub Actions has no libvirt support; nixos-rebuild build-vm is built into NixOS with no external dependencies | bin/virtual-machine requires libvirt daemon, OVMF firmware files, and complex XML generation unavailable in ephemeral CI containers. The existing bin/build-vm script already demonstrates this lightweight approach works. |
