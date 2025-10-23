# Research: NixOS-Anywhere VM Installation

**Feature**: 002-nixos-anywhere-vm-install
**Date**: 2025-10-22
**Phase**: 0 - Research & Discovery

## Overview

This document captures research findings for implementing nixos-anywhere deployment to Keystone VMs. The goal is to understand best practices, integration patterns, and potential challenges for deploying NixOS systems remotely.

## Research Areas

### 1. nixos-anywhere Integration

**Decision**: Use nixos-anywhere as the primary deployment tool

**Rationale**:
- Official NixOS community tool designed for remote installation
- Supports deploying to systems booted from installer ISO via SSH
- Integrates seamlessly with disko for disk partitioning
- Handles initial system installation and configuration application
- Well-maintained with active community support

**Alternatives Considered**:
- Manual `nixos-install` over SSH: More error-prone, requires manual disk setup
- Custom deployment scripts: Reinventing the wheel, harder to maintain
- Colmena/NixOps: Designed for fleet management, overkill for single system deployment

**Implementation Notes**:
- nixos-anywhere requires SSH access to target system
- Target must be booted from installer ISO (already supported)
- Deployment initiated from development machine with flake reference
- Command format: `nixos-anywhere --flake .#test-server root@<target-ip>`

### 2. Flake Configuration Structure

**Decision**: Add `nixosConfigurations.test-server` to flake.nix outputs

**Rationale**:
- Standard NixOS pattern for defining deployment targets
- Allows versioning of specific system configurations
- Supports both local building and remote deployment
- Enables easy configuration variations (test vs production)

**Configuration Pattern**:
```nix
nixosConfigurations.test-server = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    disko.nixosModules.disko
    ./modules/server
    ./modules/disko-single-disk-root
    {
      keystone.disko = {
        enable = true;
        device = "/dev/vda";  # Common VM disk
      };
      keystone.server.enable = true;
      networking.hostName = "test-server";
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAA..." # SSH public key
      ];
    }
  ];
};
```

**Best Practices**:
- Keep example configs in `examples/` directory
- Use `/dev/vda` for QEMU/KVM VMs (most common)
- Use `/dev/sda` or by-id paths for physical hardware
- Document disk device selection in comments

### 3. TPM2 Handling in VM Environments

**Decision**: Document TPM2 graceful degradation behavior; no code changes needed

**Rationale**:
- Existing disko module already handles TPM2 absence via LUKS fallback
- VMs typically don't have virtual TPM2 by default
- Password prompt appears automatically when TPM2 unlock fails
- QEMU supports vTPM but adds complexity for testing

**Behavior Analysis**:
- **With TPM2**: Automatic unlock using hardware-stored keys, PCR measurements
- **Without TPM2 (VMs)**: Password prompt on boot, manual unlock required
- **Credstore**: Always uses LUKS encryption regardless of TPM2 availability
- **ZFS encryption**: Key stored in credstore, loaded after unlock

**Testing Strategy**:
- Test deployment to VM without vTPM (default case)
- Verify password prompt appears on first boot
- Confirm system boots successfully after password entry
- Document expected behavior in quickstart guide

### 4. Disk Device Specification

**Decision**: Use `/dev/vda` as default for VMs, document alternatives

**Rationale**:
- `/dev/vda` is the standard virtio disk device in QEMU/KVM VMs
- `/dev/sda` used by older VM configurations and some physical hardware
- `/dev/disk/by-id/...` preferred for physical deployments (stability)
- Configuration must specify device explicitly to prevent wrong disk formatting

**Device Selection Guidelines**:
- **QEMU/KVM VMs**: `/dev/vda` (virtio)
- **VirtualBox VMs**: `/dev/sda` (SATA)
- **Physical hardware**: `/dev/disk/by-id/nvme-...` or `/dev/disk/by-id/ata-...`
- **Never** use `/dev/nvme0n1` or `/dev/sda` directly on production systems

**Safety Measures**:
- nixos-anywhere prompts for confirmation before formatting
- Include verification step in deployment script
- Document how to identify target disk device

### 5. SSH Key Management

**Decision**: Require explicit SSH public key in configuration

**Rationale**:
- Server must be accessible after installation
- Root SSH access with public key authentication is secure default
- Keys should be version controlled (public keys only)
- Enables automated deployments and testing

**Implementation Pattern**:
```nix
users.users.root.openssh.authorizedKeys.keys = [
  # Developer workstation key
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@workstation"
];
```

**Best Practices**:
- Use `ssh-ed25519` keys (modern, secure)
- Include comment with key identifier
- Support multiple keys for team deployments
- Never commit private keys to repository

### 6. Deployment Verification

**Decision**: Create post-deployment verification script

**Rationale**:
- Automated verification reduces human error
- Confirms essential services are running
- Validates security configuration
- Provides confidence in deployment success

**Verification Checks**:
1. SSH connectivity test
2. Hostname verification
3. Firewall rules check (only SSH port 22 open)
4. ZFS pool status and encryption verification
5. Essential services status (sshd, systemd-resolved, avahi)
6. Disk usage and mount points
7. mDNS advertisement verification

**Script Output**:
- Clear PASS/FAIL for each check
- Detailed error messages on failure
- Summary report at end
- Exit code 0 on success, non-zero on failure

### 7. Integration with Existing VM Infrastructure

**Decision**: Extend existing `vms/` directory with test-server configuration

**Rationale**:
- Project already has VM infrastructure (from feature 001)
- Consistent organization pattern
- Separates VM-specific configs from reusable examples
- Enables multiple VM configurations for different test scenarios

**Directory Structure**:
```
vms/
├── test-server/
│   └── configuration.nix    # VM-specific overrides
└── [future VMs]/
```

**Integration Points**:
- Use existing `bin/build-iso` for ISO creation
- Leverage existing SSH key injection in ISO
- Coordinate with VM startup scripts
- Share common patterns across VM configurations

## Key Findings Summary

1. **nixos-anywhere** is the right tool - well-supported, integrates with disko
2. **No module changes needed** - pure composition of existing modules
3. **TPM2 fallback works** - existing code handles VM scenario correctly
4. **Disk device specification** is critical - must be explicit in config
5. **SSH keys** must be configured upfront for post-installation access
6. **Verification automation** adds confidence and speeds up testing
7. **VM infrastructure** can be extended cleanly with new configurations

## Open Questions Resolved

- **Q**: Does nixos-anywhere work with encrypted disks?
  - **A**: Yes, disko handles all encryption setup during installation

- **Q**: How does TPM2 fallback work in VMs?
  - **A**: LUKS password prompt appears automatically; no code changes needed

- **Q**: Can we test deployments locally without affecting production?
  - **A**: Yes, using VM infrastructure and separate flake configurations

- **Q**: What happens if deployment fails midway?
  - **A**: nixos-anywhere is idempotent; can retry on fresh target

## Next Steps (Phase 1)

1. Create data model documentation (minimal - mostly configuration structure)
2. Define configuration contracts (NixOS module options schema)
3. Generate quickstart guide for developers
4. Update agent context with nixos-anywhere patterns
