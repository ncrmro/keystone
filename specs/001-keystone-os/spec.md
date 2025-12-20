# Keystone OS Specification

## Overview

- **Goal**: Provide a reproducible, secure operating system distribution that can be deployed to any hardware with full disk encryption, automatic hardware-based unlock, and mesh network integration.
- **Scope**: First-class support for servers and workstations; deployment via bootable installer or remote installation to SSH-accessible systems.
- **Automation**: All features must be testable via `nix flake check` for CI/CD integration.

## Functional Requirements

### FR-001 Declarative Configuration

The system configuration MUST be fully declarative and reproducible.

- All system state defined in version-controllable expressions
- Same configuration produces identical systems across deployments
- Single output per target system configuration
- Configuration changes applied atomically with rollback capability

### FR-002 Full Disk Encryption

All user data MUST be encrypted at rest.

- Storage volumes encrypted before any user data is written
- Encryption keys never stored in plaintext on disk
- Key material protected by hardware security module when available
- Fallback authentication method when hardware security unavailable
- Swap space encrypted with ephemeral keys

### FR-003 Automatic Unlock

Systems MUST unlock automatically when boot integrity is verified.

- No manual password entry required under normal boot conditions
- Unlock bound to verified boot state measurements
- Automatic unlock fails safely if boot integrity is compromised
- Clear notification when manual unlock is required
- First-boot enrollment workflow for hardware security binding

### FR-004 Verified Boot Chain

The boot process MUST be cryptographically verified from firmware to userspace.

- Custom signing keys enrolled for platform ownership
- Boot artifacts signed and verified at each stage
- Tampering with boot components prevents automatic unlock
- Support for firmware in "setup mode" during initial deployment
- Transition from setup mode to user mode after key enrollment

### FR-005 Copy-on-Write Storage

The filesystem MUST support efficient snapshots and data integrity.

- Point-in-time snapshots without performance penalty
- Automatic data compression
- Data integrity verification (checksums)
- Remote replication capability for backups
- Per-dataset configuration (quotas, compression, snapshots)

### FR-006 Remote Installation

Systems MUST be deployable to any SSH-accessible target.

- Deploy over network to running system (kexec-based)
- Bootable installer media generation with SSH key injection
- Disk partitioning defined declaratively and applied automatically
- Support for injecting additional files during deployment
- Installation progress observable via SSH

### FR-007 Mesh Network Client

Systems MUST be able to join private mesh networks.

- Automatic connection to coordination server on first boot
- Node discovery without manual IP configuration
- Secure remote access without port forwarding or NAT traversal
- DNS-based node resolution within mesh
- Exit node capability for routing traffic through specific nodes

### FR-008 Mesh Network Server

Systems MUST be able to host mesh network coordination services.

- Self-hosted coordination server for mesh network
- Node authentication and authorization management
- Access control list (ACL) configuration
- DNS integration for automatic node name resolution
- Web-based administration interface

### FR-009 Server Role

The system MUST support always-on server configurations.

- Headless operation without display manager
- SSH access enabled by default
- Service discovery via multicast DNS (mDNS)
- Firewall with secure defaults
- Support for network gateway, DNS, and storage services

### FR-010 Workstation Role

The system MUST support interactive desktop workstation configurations.

- Graphical desktop environment with compositor
- Display manager with auto-login capability
- Audio system with application mixing
- Network management with graphical interface
- Bluetooth connectivity
- Terminal development environment (editor, shell, multiplexer)

### FR-011 Testing via Flake Checks

All system features MUST be testable via standard flake check mechanism.

- Tests runnable with `nix flake check`
- Virtual machine-based testing for system configurations
- Hardware security emulation for TPM-dependent features
- Secure Boot verification in emulated environment
- Headless execution for CI/CD pipelines

## Non-Functional Requirements

### NFR-001 Reproducibility

- Identical inputs produce identical outputs
- All dependencies pinned to specific versions
- No reliance on external state during build
- Offline builds possible with cached dependencies

### NFR-002 Security Posture

- Defense in depth with multiple security layers
- Minimal attack surface with only required services enabled
- Secure defaults requiring explicit opt-out
- No default passwords in production configurations
- Secrets never committed to version control

### NFR-003 Observability

- Installation progress visible with detailed logging
- Boot process debuggable via serial console
- System logs aggregated and queryable
- Health metrics exportable for monitoring
- Clear error messages with remediation guidance

## Testing Requirements

### TR-001 Fast Iteration Testing

Tests for rapid configuration development without full security stack.

**Flake check output**: `checks.x86_64-linux.vm-terminal`, `checks.x86_64-linux.vm-desktop`

- Quick virtual machine builds (< 2 minutes)
- No disk encryption or verified boot overhead
- SSH access for interactive debugging
- Persistent disk state between runs (optional)
- Both headless (terminal) and graphical (desktop) modes

### TR-002 Full Stack Testing

Tests for complete deployment including all security features.

**Flake check output**: `checks.x86_64-linux.integration-deployment`

- Hardware security module emulation
- Verified boot in emulated UEFI environment
- Full disk encryption with automatic unlock verification
- End-to-end deployment via remote installation
- Post-deployment security state validation

### TR-003 Module Testing

Tests for individual module functionality.

**Flake check output**: `checks.x86_64-linux.nixos-*`

- Service startup verification
- Configuration option validation
- Module interaction testing
- Regression testing for module changes

## Success Criteria

### SC-001 Deployment Success

- Fresh system deployable from ISO in under 30 minutes
- Remote deployment to SSH target in under 15 minutes
- First boot completes without manual intervention (after hardware enrollment)

### SC-002 Security Verification

- Disk contents unreadable without proper authentication
- Boot tampering detected and automatic unlock prevented
- Hardware security enrollment completes in under 5 minutes

### SC-003 Network Integration

- Mesh network connection established within 60 seconds of boot
- Node discoverable by hostname within mesh network
- Remote access functional without port forwarding

### SC-004 Test Coverage

- All functional requirements have corresponding flake checks
- Tests complete in under 30 minutes total
- Test failures produce actionable diagnostics

## Out of Scope

The following features are explicitly out of scope for this specification and planned for future versions:

- **Automated backups**: ZFS snapshot scheduling and remote replication automation
- **Monitoring stack**: Prometheus, Grafana, alerting infrastructure
- **Multi-host deployment**: Orchestrated deployment across multiple systems
- **Container orchestration**: Kubernetes/k3s integration
- **Distributed storage**: Ceph, GlusterFS, or similar
- **Enterprise features**: LDAP/AD integration, compliance automation, audit logging
- **Laptop-specific features**: Suspend/hibernate, battery management, lid switch handling
- **Multi-GPU configurations**: Complex graphics setups, GPU passthrough
