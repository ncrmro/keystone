# Feature Specification: Secure Boot Setup Mode for VM Testing

**Feature Branch**: `003-secureboot-setup-mode`
**Created**: 2025-10-31
**Status**: Draft
**Input**: User description: "The test machine needs to be booted into the virtual machine with secureboot in setup mode."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Boot VM in Secure Boot Setup Mode (Priority: P1)

As a Keystone developer, I need to create test VMs that boot into Secure Boot setup mode so that I can verify the firmware configuration is correct for Keystone testing, using `bootctl status` to confirm the VM is in setup mode.

**Why this priority**: This is the core requirement that enables Secure Boot testing workflows. Developers need a reproducible way to create VMs in setup mode to validate Keystone's Secure Boot integration.

**Independent Test**: Can be fully tested by creating a VM with the bin/virtual-machine script, booting it with the Keystone installer, running `bootctl status` from the installer environment, and verifying the output shows "Secure Boot: setup".

**Acceptance Scenarios**:

1. **Given** a developer creates a new VM using bin/virtual-machine, **When** the VM boots from the Keystone installer ISO, **Then** running `bootctl status` shows "Secure Boot: setup"
2. **Given** a VM is in Secure Boot setup mode, **When** the developer inspects the firmware configuration, **Then** Secure Boot is enabled but no keys are enrolled
3. **Given** a VM has been created in setup mode, **When** the developer reboots the VM, **Then** `bootctl status` continues to show "Secure Boot: setup" until the installer modifies the key state

---

### Edge Cases

- What happens when a VM is created without OVMF Secure Boot firmware available on the system?
- What happens when NVRAM state becomes corrupted or the NVRAM file is deleted?
- What happens when `bootctl status` is run on a VM that was created before this feature was implemented?
- How does the system handle VMs that have already transitioned out of setup mode?
- What happens if the OVMF_VARS template already has keys enrolled?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The bin/virtual-machine script MUST create VMs with a fresh NVRAM file to ensure Secure Boot setup mode
- **FR-002**: The system MUST use OVMF firmware with Secure Boot support (edk2-x86_64-secure-code.fd or equivalent)
- **FR-003**: The NVRAM file MUST be initialized from a clean OVMF_VARS template with no pre-enrolled keys
- **FR-004**: The VM MUST boot with Secure Boot enabled in firmware but with no enrolled keys (Setup Mode)
- **FR-005**: Running `bootctl status` from within the VM MUST show "Secure Boot: setup"
- **FR-006**: The system MUST preserve NVRAM state across VM reboots to maintain Secure Boot mode status
- **FR-007**: The system MUST provide clear feedback when OVMF Secure Boot firmware is not available
- **FR-008**: The bin/virtual-machine script MUST document how to verify the VM is in setup mode using `bootctl status`
- **FR-009**: The NVRAM file MUST be stored in the VM directory alongside the disk image for easy cleanup
- **FR-010**: The system MUST fail gracefully if the OVMF_VARS template contains pre-enrolled keys

### Key Entities

- **VM Configuration**: Represents the libvirt domain XML with UEFI firmware settings, Secure Boot enabled, and NVRAM path
- **NVRAM State**: Stores firmware variables including Secure Boot status (setup mode vs user mode), persisted across reboots
- **OVMF Firmware**: Read-only firmware code (OVMF_CODE) and writable variables template (OVMF_VARS) without pre-enrolled keys

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Developers can create a VM in Secure Boot setup mode and verify setup mode status using `bootctl status` within 2 minutes
- **SC-002**: 100% of new VMs created with bin/virtual-machine show "Secure Boot: setup" when running `bootctl status` on first boot
- **SC-003**: VM creation fails gracefully with clear error message when OVMF Secure Boot firmware is unavailable (no silent failures)
- **SC-004**: NVRAM state persists correctly across VM reboots, maintaining setup mode status until modified
- **SC-005**: The workflow is documented such that developers can verify Secure Boot setup mode without consulting external OVMF or libvirt documentation
