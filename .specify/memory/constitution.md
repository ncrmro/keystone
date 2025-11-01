<!--
SYNC IMPACT REPORT
===================
Version: 1.0.0 → 1.0.1
Change Type: PATCH (Clarification of development tooling)

Principles Modified:
- None (core principles unchanged)

Sections Added:
- Development Tooling subsection under NixOS-Specific Constraints

Sections Removed:
- None

Templates Status:
- ✅ plan-template.md: No updates required (constitution check remains compatible)
- ✅ spec-template.md: No updates required (requirements section unaffected)
- ✅ tasks-template.md: No updates required (task structure unaffected)

Follow-up Actions:
- None - clarification only, no dependent artifact changes needed

Rationale for Version 1.0.1:
- Added Development Tooling subsection documenting bin/virtual-machine as primary VM driver
- PATCH bump: Clarifying guidance for development workflow, no semantic changes
- Does not affect core principles, module standards, or testing requirements
-->

# Keystone Constitution

## Core Principles

### I. Declarative Infrastructure

All infrastructure configuration MUST be:
- Defined as code using NixOS modules
- Version controlled (typically in Git)
- Reproducible across different hardware and environments
- Auditable with clear change history

**Rationale**: Declarative configuration enables infrastructure portability, disaster recovery, and eliminates configuration drift. Users can migrate between bare-metal and cloud seamlessly by applying the same configuration.

### II. Security by Default

Every configuration MUST implement:
- Full disk encryption (LUKS + ZFS native encryption)
- TPM2 hardware key storage where available
- Secure boot attestation with PCR measurements
- Zero-trust architecture (all data encrypted at rest and in transit)

**Rationale**: Security cannot be optional or added later. Hardware-backed encryption and attestation ensure cryptographic verification of the entire boot chain and protect user data even if hardware is physically compromised.

### III. Modular Composability

Features MUST be implemented as:
- Self-contained NixOS modules with clear boundaries
- Composable units that can be enabled/disabled independently
- Modules with explicit dependencies and options
- Reusable across server, client, and installer configurations

**Rationale**: Modular architecture allows users to build custom configurations by composing only the features they need. Each module should solve one problem well and integrate cleanly with others.

### IV. Hardware Agnostic

Infrastructure definitions MUST:
- Run on diverse hardware (Raspberry Pi to enterprise servers)
- Abstract hardware specifics through NixOS module options
- Support both bare-metal and virtualized environments
- Enable live migration between different deployment targets

**Rationale**: Users should not be locked into specific hardware vendors or cloud providers. The same configuration should deploy to any compatible x86_64 or ARM64 system.

### V. Cryptographic Sovereignty

Users MUST maintain control over:
- All encryption keys (no vendor escrow)
- Authentication credentials and identity
- Data storage locations and backup targets
- Trust anchors and certificate authorities

**Rationale**: Self-sovereign infrastructure means users own their data and security posture. Keys must never leave user control, and external dependencies should be minimized or eliminated.

## NixOS-Specific Constraints

### Module Development Standards

All NixOS modules MUST:
- Use `types.attrsOf` for extensible option sets
- Provide `enable` options for all optional features
- Include assertions for configuration validation
- Document options with clear descriptions and examples

### Development Tooling

Development and testing workflows MUST use standardized tooling:
- **VM Testing**: `bin/virtual-machine` is the primary driver for creating and managing libvirt VMs
  - Supports UEFI Secure Boot with OVMF firmware
  - Integrates with keystone-net network for static IP assignment
  - Provides post-installation snapshot and ISO detachment workflows
  - See bin/virtual-machine:1 for complete implementation
- **ISO Building**: `bin/build-iso` for creating bootable installers with optional SSH key injection
- **Deployment**: `nixos-anywhere` for remote installations to VMs or bare-metal

**Rationale**: Standardized tooling ensures consistent development workflows, reduces manual setup complexity, and enables reproducible testing environments. The bin/virtual-machine script encapsulates complex libvirt XML generation and OVMF firmware discovery specific to NixOS.

### Testing Requirements

Configuration changes MUST include:
- Build-time validation (`nix build` succeeds)
- Boot testing on target hardware or VM when possible
- Regression tests for critical security features (TPM, encryption)

### Documentation Standards

Every module MUST provide:
- Option documentation in NixOS manual format
- Usage examples in `examples/` directory
- Rationale for architectural decisions in comments
- Migration guides for breaking changes

## Governance

### Amendment Process

Constitution amendments require:
1. Proposal documented with rationale and impact analysis
2. Review of affected modules and templates
3. Migration plan for existing deployments
4. Version bump following semantic versioning

### Versioning Policy

- **MAJOR**: Breaking changes to core principles or module interfaces
- **MINOR**: New principles or significant expansions to guidance
- **PATCH**: Clarifications, examples, or editorial improvements

### Compliance Review

All contributions MUST:
- Align with core principles (I-V)
- Follow NixOS module standards
- Pass security validation gates
- Include documentation updates

Violations require explicit justification in design documents and approval from maintainers.

**Version**: 1.0.1 | **Ratified**: 2025-10-16 | **Last Amended**: 2025-10-31
