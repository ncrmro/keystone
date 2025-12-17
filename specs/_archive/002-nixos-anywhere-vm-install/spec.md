# Feature Specification: NixOS-Anywhere VM Installation

**Feature Branch**: `002-nixos-anywhere-vm-install`
**Created**: 2025-10-22
**Status**: Draft
**Input**: User description: "Now that we have the ability to ssh into a VM booted from our built iso, We need to run nixos-anywhere to install it. We should do the most bare minimum straight forward server install to get started using the current flake. It should again allow us to ssh into it and verify that it has installed."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Basic Server Deployment to VM (Priority: P1)

A developer wants to test the Keystone server installation in a VM environment to validate that the deployment process works correctly before deploying to physical hardware.

**Why this priority**: This is the foundation of the deployment workflow. Without a working VM installation process, the entire deployment system cannot be validated or tested safely.

**Independent Test**: Can be fully tested by running nixos-anywhere against a VM booted from the Keystone ISO, then SSH-ing into the resulting system to confirm the server is running with expected configuration.

**Acceptance Scenarios**:

1. **Given** a VM is running and booted from the Keystone ISO with SSH access, **When** nixos-anywhere is executed with minimal server configuration, **Then** the deployment completes successfully without errors
2. **Given** nixos-anywhere has completed successfully, **When** the VM reboots, **Then** the system boots into the installed NixOS server without manual intervention
3. **Given** the server has completed its first boot, **When** attempting to SSH into the server, **Then** SSH connection is established using the configured authentication method
4. **Given** SSH access to the installed server, **When** checking system services, **Then** all essential server services are running (SSH, mDNS, systemd-resolved)
5. **Given** SSH access to the installed server, **When** verifying disk configuration, **Then** the ZFS pool is mounted and encrypted storage is accessible

---

### User Story 2 - Installation Verification and Validation (Priority: P2)

A developer needs to verify that the installed server matches the expected configuration and all security features are properly configured.

**Why this priority**: Verification ensures the deployment actually worked and the system is in a secure, usable state. This builds confidence in the deployment process before moving to production.

**Independent Test**: Can be tested independently by connecting to any deployed server and running a series of validation checks against expected configuration baselines.

**Acceptance Scenarios**:

1. **Given** SSH access to the installed server, **When** checking firewall rules, **Then** only SSH port 22 is open and firewall is enabled
2. **Given** SSH access to the installed server, **When** verifying user configuration, **Then** root login is restricted to public key authentication only
3. **Given** SSH access to the installed server, **When** checking disk encryption, **Then** the root filesystem is encrypted and properly unlocked
4. **Given** SSH access to the installed server, **When** verifying system identity, **Then** hostname matches the configured value and mDNS is advertising the system

---

### User Story 3 - Reproducible Deployment Process (Priority: P3)

A developer wants to be able to repeatedly deploy fresh server installations to test configuration changes and deployment improvements.

**Why this priority**: Reproducibility is essential for development workflow but depends on having a working basic deployment first. This enables rapid iteration.

**Independent Test**: Can be tested by destroying a VM and re-deploying multiple times in succession, verifying each deployment produces identical results.

**Acceptance Scenarios**:

1. **Given** a VM that has been previously deployed, **When** the VM is destroyed and redeployed with the same configuration, **Then** the new deployment completes successfully with identical results
2. **Given** multiple deployment attempts, **When** comparing system configurations, **Then** all deployments produce consistent system state
3. **Given** a configuration change in the flake, **When** redeploying to a fresh VM, **Then** the new configuration is applied correctly in the deployed system

---

### Edge Cases

- What happens when the VM loses network connectivity during nixos-anywhere deployment?
- How does the system handle SSH authentication failure after installation?
- What happens if the target disk is too small for the default partition layout?
- How does the system behave if the VM reboots during installation?
- What happens when trying to deploy to a VM that already has a system installed?
- How does the installation handle systems without TPM2 support (VM environment)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a flake configuration that defines a minimal server deployment target
- **FR-002**: Deployment MUST use the existing Keystone server module with disko-single-disk-root for storage configuration
- **FR-003**: Deployment MUST support execution via nixos-anywhere from a development machine to a target VM
- **FR-004**: Installed server MUST enable SSH access with public key authentication
- **FR-005**: Installed server MUST configure disk encryption with automatic unlock capability (TPM2 or fallback mechanism)
- **FR-006**: Deployment process MUST configure a unique hostname for the server
- **FR-007**: Server MUST enable mDNS for network discovery on first boot
- **FR-008**: System MUST configure firewall to allow only essential services (SSH)
- **FR-009**: Deployment MUST be idempotent when targeting a fresh VM
- **FR-010**: Server MUST automatically boot into the installed system after successful deployment
- **FR-011**: System MUST provide a way to specify SSH public keys during deployment configuration
- **FR-012**: Deployment configuration MUST specify the target disk device path
- **FR-013**: System MUST handle VM environments that lack hardware TPM2 support gracefully
- **FR-014**: Server MUST enable basic system administration tools (vim, git, htop, etc.)

### Key Entities

- **Server Configuration**: Represents a complete NixOS system configuration combining the server module, disko configuration, and deployment-specific settings (hostname, SSH keys, disk device)
- **Deployment Target**: Represents a VM or physical machine accessible via SSH running the Keystone installer ISO
- **Installed System**: Represents the final deployed NixOS server with all configured services, encryption, and network access

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Developer can deploy a minimal server to a VM in under 10 minutes from issuing the nixos-anywhere command
- **SC-002**: Deployed server boots successfully on first attempt without manual intervention
- **SC-003**: SSH access to deployed server is available within 2 minutes of system boot completion
- **SC-004**: Deployment process completes without errors in 100% of attempts when targeting a fresh VM with network connectivity
- **SC-005**: Developer can verify server installation status by running standard system commands via SSH
- **SC-006**: Disk encryption is properly configured and functional on 100% of deployments
- **SC-007**: Deployment is reproducible - destroying and redeploying produces functionally identical systems
