# Implementation Plan: Multi-VM Headscale Connectivity Testing

**Branch**: `010-multi-vm-headscale` | **Date**: 2025-11-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/010-multi-vm-headscale/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Establish a test environment for verifying mesh network connectivity between three VMs using Headscale (self-hosted Tailscale control server). The test validates encrypted WireGuard tunnel establishment, cross-network communication, service binding to mesh interfaces, and distributed DNS resolution. This enables validation of secure peer-to-peer infrastructure before production deployment.

## Technical Context

**Language/Version**: Nix (NixOS 25.05), Bash scripting
**Primary Dependencies**:
- Headscale (control server) - NixOS service module
- Tailscale client (compatible with Headscale) - NixOS package
- Libvirt/QEMU - VM infrastructure (existing Keystone tooling)
- nginx - Web server for service binding tests
- NEEDS CLARIFICATION: Headscale configuration options for DNS/mesh networking
- NEEDS CLARIFICATION: Tailscale client systemd service configuration for Headscale compatibility
- NEEDS CLARIFICATION: Best practices for libvirt network topology simulation (multiple subnets)

**Storage**:
- SQLite (Headscale embedded database for node registry)
- VM disk images (qcow2 format via libvirt)
- NEEDS CLARIFICATION: Headscale state persistence requirements

**Testing**:
- Manual validation via ping, curl, systemd journalctl
- Headscale CLI commands for node status verification
- NEEDS CLARIFICATION: Automated test framework options (NixOS test framework vs bash scripts)

**Target Platform**: NixOS VMs (x86_64-linux) on local libvirt/QEMU host

**Project Type**: Infrastructure testing (NixOS modules + bash test orchestration)

**Performance Goals**:
- Connection establishment: <2 minutes after VM registration
- Ping latency: <50ms between mesh nodes
- DNS resolution: <1 second for hostname lookups
- Mesh uptime: 99% during 1-hour test period
- Reconnection after interruption: <30 seconds

**Constraints**:
- Local-only testing (no cloud resources)
- Host system resource limits (memory/CPU for 4 VMs: 1 Headscale server + 3 clients)
- Test execution: <1 hour total duration
- Must integrate with existing Keystone VM tooling (bin/virtual-machine, bin/build-vm)
- Halt on first test failure (strict validation)

**Scale/Scope**:
- 4 VMs total (1 Headscale server, 3 client nodes)
- 3 simultaneous mesh connections (full mesh topology)
- 2 simulated network topologies (different subnets)
- 4 priority levels of test scenarios (P1-P4)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. Declarative Infrastructure ✅ PASS

**Requirement**: All infrastructure configuration MUST be defined as code using NixOS modules, version controlled, reproducible, and auditable.

**Evaluation**: This feature creates NixOS module configurations for Headscale server and Tailscale clients. VM definitions will be declarative (libvirt XML or Nix expressions). Test orchestration scripts will be version-controlled in the repository.

**Status**: ✅ Compliant - All VM configurations and service definitions will be declarative NixOS modules.

---

### II. Security by Default ⚠️ RELAXED FOR TESTING

**Requirement**: Every configuration MUST implement full disk encryption (LUKS + ZFS), TPM2 key storage, Secure Boot attestation, and zero-trust architecture.

**Evaluation**: Test VMs are ephemeral and intended for connectivity validation, not production security. Implementing full encryption/TPM/Secure Boot would add significant complexity and overhead for testing mesh networking functionality. However, the Headscale mesh itself provides encrypted WireGuard tunnels (zero-trust for data in transit).

**Status**: ⚠️ **EXCEPTION GRANTED** - Test VMs will NOT use full disk encryption, TPM2, or Secure Boot. Justification:
- VMs are ephemeral test infrastructure (destroyed after testing)
- No sensitive data stored on test VMs
- Focus is validating mesh networking, not boot security
- WireGuard encryption provides zero-trust for network traffic
- Production deployments would layer Headscale on top of existing secure Keystone configurations

---

### III. Modular Composability ✅ PASS

**Requirement**: Features MUST be implemented as self-contained NixOS modules with clear boundaries, composable units, explicit dependencies, and reusable across server/client/installer configurations.

**Evaluation**: Headscale server and Tailscale client configurations will be separate, composable NixOS modules. Test orchestration will be modular (VM creation, network setup, validation scripts as independent components).

**Status**: ✅ Compliant - Headscale server module and client configurations are independently composable.

---

### IV. Hardware Agnostic ✅ PASS

**Requirement**: Infrastructure definitions MUST run on diverse hardware, abstract hardware specifics through module options, support bare-metal and virtualized environments, enable live migration.

**Evaluation**: Headscale/Tailscale configurations are purely software-based and hardware-agnostic. Libvirt VMs provide abstraction layer. Same configurations could deploy to bare-metal, cloud VMs, or containers.

**Status**: ✅ Compliant - Mesh networking is inherently hardware-agnostic.

---

### V. Cryptographic Sovereignty ✅ PASS

**Requirement**: Users MUST maintain control over all encryption keys, authentication credentials, data storage locations, and trust anchors.

**Evaluation**: Headscale is self-hosted (users control the coordination server). WireGuard keys are generated locally on each node. Pre-authentication keys are user-managed. No external identity providers required.

**Status**: ✅ Compliant - Full control over Headscale server, node keys, and authentication.

---

### Module Development Standards ✅ PASS

**Requirements**: Use `types.attrsOf` for extensible options, provide `enable` options, include assertions, document options.

**Evaluation**: NixOS modules for Headscale/Tailscale will follow standard module patterns with enable flags and documented options.

**Status**: ✅ Compliant - Standard NixOS module structure will be used.

---

### Development Tooling ✅ PASS

**Requirements**: Use `bin/virtual-machine` for libvirt VM creation, `bin/build-iso` for installers, `nixos-anywhere` for deployment.

**Evaluation**: Test infrastructure will use `bin/virtual-machine` for VM creation and management. This is the primary driver for Keystone VM testing.

**Status**: ✅ Compliant - Using standardized Keystone VM tooling.

---

### Testing Requirements ✅ PASS

**Requirements**: Include build-time validation, boot testing on target hardware/VM, regression tests for critical security features.

**Evaluation**: Test suite explicitly validates connectivity, DNS, service binding. Build-time validation via `nix build`. Boot testing inherent in VM deployment workflow.

**Status**: ✅ Compliant - Comprehensive test scenarios defined in spec.

---

### Overall Gate Status: ✅ PASS WITH JUSTIFIED EXCEPTION

**Summary**: One exception granted (Principle II - Security by Default) for test VM infrastructure. Justification documented in Complexity Tracking section below. All other principles compliant.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# NixOS Module Configurations
modules/
├── headscale-server/
│   └── default.nix          # Headscale control server module
└── tailscale-client/
    └── default.nix          # Tailscale client configured for Headscale

# Test Infrastructure
test/
└── multi-vm-headscale/
    ├── vms/
    │   ├── headscale-server.nix    # Headscale server VM configuration
    │   ├── client-node-1.nix        # Client VM 1 (subnet A)
    │   ├── client-node-2.nix        # Client VM 2 (subnet B)
    │   └── client-node-3.nix        # Client VM 3 (subnet B)
    ├── networks/
    │   ├── subnet-a.xml             # Libvirt network definition (192.168.1.0/24)
    │   └── subnet-b.xml             # Libvirt network definition (10.0.0.0/24)
    ├── orchestration/
    │   ├── setup-test-env.sh        # Create VMs and networks
    │   ├── run-connectivity-tests.sh # Execute P1-P4 test scenarios
    │   ├── cleanup-test-env.sh      # Tear down test infrastructure
    │   └── lib/
    │       ├── vm-utils.sh          # VM lifecycle helper functions
    │       └── validation-utils.sh  # Test assertion helpers
    └── README.md                    # Test suite documentation

# Flake Integration
flake.nix                    # Updated with new modules and test configurations
```

**Structure Decision**: Infrastructure-focused layout. NixOS modules in standard `modules/` directory for potential reuse in production. Test infrastructure isolated in `test/multi-vm-headscale/` with VM definitions, network configs, and orchestration scripts. This separates reusable components (modules) from ephemeral test infrastructure.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Principle II - Security by Default (no disk encryption/TPM/Secure Boot on test VMs) | Test VMs are ephemeral infrastructure for validating mesh networking functionality. Focus is connectivity/DNS/service binding, not boot security. Full encryption adds minutes to VM boot time and complicates test debugging. | Using full Keystone secure configurations would: (1) Significantly increase test setup time (2) Obscure test failures with encryption/TPM issues unrelated to mesh networking (3) Require manual TPM/LUKS password entry for each of 4 VMs. Test validation requires rapid iteration, which full security stack prevents. Production deployments will use secure Keystone base + Headscale module on top. |

---

## Post-Design Constitution Re-Evaluation

**Date**: 2025-11-10 (after Phase 1 completion)

After completing research, data model, and contract design, the Constitution Check evaluation remains unchanged:

### Updated Assessment

**Principle I (Declarative Infrastructure)**: ✅ PASS
- Design confirms all configurations will be NixOS modules
- VM definitions declarative (libvirt XML + NixOS expressions)
- Test orchestration scripts version-controlled

**Principle II (Security by Default)**: ⚠️ EXCEPTION REMAINS JUSTIFIED
- Design reinforces that test VMs are for connectivity validation only
- WireGuard encryption provides data-in-transit security (zero-trust for network layer)
- Production deployments will layer Headscale modules on top of existing secure Keystone configurations
- No change to exception justification

**Principle III (Modular Composability)**: ✅ PASS
- Headscale server module and Tailscale client configurations are independently composable
- Test infrastructure clearly separated from reusable modules
- Bash orchestration scripts are modular (setup/test/cleanup as separate components)

**Principle IV (Hardware Agnostic)**: ✅ PASS
- Mesh networking is purely software-based
- Same configurations deployable to bare-metal, VMs, or containers
- No hardware-specific dependencies introduced

**Principle V (Cryptographic Sovereignty)**: ✅ PASS
- Headscale self-hosted (users control coordination server)
- WireGuard keys generated locally on each node
- Pre-authentication keys user-managed
- No external identity providers required

**Module Development Standards**: ✅ PASS
- Configuration schemas follow NixOS module patterns
- Contracts define clear interfaces for services
- Assertions planned for configuration validation

**Development Tooling**: ✅ PASS
- Using `bin/virtual-machine` for VM creation (standardized Keystone tooling)
- Bash orchestration integrates with existing infrastructure

**Testing Requirements**: ✅ PASS
- Comprehensive test scenarios documented (P1-P4)
- Build-time validation via `nix build`
- Boot testing inherent in VM deployment workflow

### Design Impact Analysis

The Phase 1 design introduced:
- **New Technologies**: Headscale (coordination server), Tailscale (mesh client), bash orchestration
- **New Patterns**: Pre-authentication key workflow, libvirt multi-subnet simulation
- **New Contracts**: CLI interfaces for Headscale/Tailscale, NixOS configuration schemas

**None of these additions violate existing constitution principles.**

### Final Gate Status: ✅ PASS WITH JUSTIFIED EXCEPTION

The single exception (Principle II - Security by Default for test VMs) remains justified post-design. All other principles are fully compliant. The design reinforces that:
1. Test infrastructure is ephemeral and isolated from production
2. Mesh networking itself provides encrypted tunnels (WireGuard)
3. Production deployments will use full Keystone security + Headscale module

**Ready to proceed to Phase 2 (Implementation via /speckit.tasks)**
