# Feature Specification: Secure Boot Automation with Lanzaboote

**Feature Branch**: `003-secureboot-automation`
**Created**: 2025-10-29
**Status**: Draft
**Input**: User description: "Now that we have a script that automates installing a zfs encrypted root and then unlocks over serial and can ssh into. The next phase is to automate enabling secureboot using lanzaboote which should extend the current test-vm script"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automated Secure Boot Enrollment (Priority: P1)

As a developer testing Keystone deployments, I need the test-vm script to automatically enroll Secure Boot keys using lanzaboote after a successful ZFS encrypted root installation, so that I can verify the complete security stack without manual intervention.

**Why this priority**: This is the core value proposition of the feature. Secure Boot is a critical security component that currently requires manual setup, blocking full automated testing of the security architecture. Without this, users cannot verify that Secure Boot works correctly with ZFS encryption and TPM2 integration.

**Independent Test**: Can be fully tested by running the extended test-vm script and verifying that Secure Boot is enabled and functional in the VM after deployment completes. Success means SSH access to a running system with Secure Boot actively enforcing boot security.

**Note**: This process uses a two-phase provisioning approach:
- **Phase 1**: `bin/test-deployment` deploys the base system with systemd-boot
- **Phase 2**: `bin/post-install-provisioner` generates and enrolls Secure Boot keys via SSH on the deployed system

**Acceptance Scenarios**:

1. **Given** a VM has successfully deployed with ZFS encrypted root and unlocked via serial, **When** the test script proceeds to Phase 2 (Secure Boot enrollment), **Then** `post-install-provisioner` connects via SSH and uses sbctl to generate custom Secure Boot keys without manual interaction
2. **Given** Secure Boot keys have been enrolled, **When** the system reboots, **Then** the bootloader verifies all boot components using Secure Boot and successfully boots to the encrypted system
3. **Given** the test script has completed, **When** a developer verifies the deployment, **Then** Secure Boot status shows as enabled and enforcing with custom keys enrolled

---

### User Story 2 - Automated Post-Enrollment Verification (Priority: P2)

As a developer testing Keystone deployments, I need the test-vm script to automatically verify that Secure Boot is properly configured and functional after enrollment, so that I can trust the deployment is secure without manual inspection.

**Why this priority**: Verification ensures the enrollment succeeded and the security posture is correct. This catches configuration errors early but is secondary to actually getting Secure Boot working. Manual verification is possible but error-prone and time-consuming.

**Independent Test**: Can be tested by running the test script and examining the verification output logs. Success means clear pass/fail indicators for Secure Boot status, key enrollment, and boot chain verification.

**Acceptance Scenarios**:

1. **Given** Secure Boot enrollment has completed, **When** the verification phase runs, **Then** the script checks and confirms Secure Boot is enabled in firmware
2. **Given** the system has booted with Secure Boot, **When** verification runs, **Then** the script confirms all boot components are signed and verified
3. **Given** any verification check fails, **When** the script completes, **Then** it reports specific failure details and returns a non-zero exit code

---

### User Story 3 - Graceful Fallback for Unsupported Hardware (Priority: P3)

As a developer testing Keystone on various VM configurations, I need the test script to detect when Secure Boot is not supported by the virtualization platform and skip enrollment gracefully, so that testing can continue on platforms that don't support UEFI Secure Boot.

**Why this priority**: Some development and testing environments may not support Secure Boot (older QEMU versions, certain VM configurations). While important for developer experience, this is an edge case that doesn't block the primary use case of testing Secure Boot on supported platforms.

**Independent Test**: Can be tested by running the test script on a VM configured without Secure Boot support (legacy BIOS or UEFI without Secure Boot variables). Success means the script detects the limitation, logs a clear warning, skips Secure Boot enrollment, and continues with other verification steps.

**Acceptance Scenarios**:

1. **Given** a VM boots without UEFI Secure Boot support, **When** the test script reaches the Secure Boot phase, **Then** it detects the lack of support and logs a clear warning message
2. **Given** Secure Boot is unsupported, **When** the script continues, **Then** it skips Secure Boot enrollment and verification but completes all other deployment tests
3. **Given** Secure Boot was skipped, **When** the script finishes, **Then** the summary indicates Secure Boot was not tested due to platform limitations

---

### Edge Cases

- What happens when Secure Boot enrollment fails midway through key generation?
- How does the system handle firmware that reports Secure Boot capability but fails during key enrollment?
- What happens if the VM loses power during the Secure Boot enrollment process?
- How does the script behave when Secure Boot variables are already populated from a previous test run?
- What happens when the VM firmware has Secure Boot enabled but in Setup Mode versus User Mode?
- How does the system recover if the signed bootloader fails to boot after Secure Boot enrollment?
- What happens when trying to enable lanzaboote before Secure Boot keys are in place?
- How does the system handle VMs that don't support Secure Boot (quickemu may require lower-level QEMU/libvirt configuration)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Test script MUST extend the existing test-deployment workflow to include a Secure Boot enrollment phase after successful ZFS encrypted deployment
- **FR-002**: Test script MUST use a two-phase provisioning approach: Phase 1 (`bin/test-deployment`) deploys base system with systemd-boot, Phase 2 (`bin/post-install-provisioner`) generates and enrolls Secure Boot keys
- **FR-003**: Phase 1 script (`bin/test-deployment`) MUST deploy the base NixOS system with systemd-boot via nixos-anywhere
- **FR-004**: Phase 2 script (`bin/post-install-provisioner`) MUST connect to the deployed system via SSH to perform key generation and enrollment
- **FR-005**: Test script MUST detect whether the VM firmware supports UEFI Secure Boot before attempting enrollment
- **FR-006**: `post-install-provisioner` MUST use sbctl to generate custom Secure Boot keys (PK, KEK, db) in `/var/lib/sbctl` during the enrollment phase
- **FR-007**: `post-install-provisioner` MUST enroll the generated Secure Boot keys into the VM firmware without requiring manual interaction
- **FR-008**: `post-install-provisioner` MUST support multiple operational modes: generate keys only, enroll keys, verify status, and full automation with reboot
- **FR-009**: Test script MUST trigger a system reboot after Secure Boot enrollment to verify the boot chain
- **FR-010**: Test script MUST verify Secure Boot status is enabled and enforcing after the post-enrollment reboot
- **FR-011**: Test script MUST verify that all boot components pass Secure Boot signature verification
- **FR-012**: Test script MUST log clear status messages for each phase of Secure Boot enrollment and verification
- **FR-013**: Test script MUST return appropriate exit codes indicating success or failure of the Secure Boot automation
- **FR-014**: Test script MUST skip Secure Boot enrollment gracefully when the VM firmware does not support it
- **FR-015**: Test script MUST preserve existing test-deployment functionality for ZFS encryption, serial unlock, and SSH verification
- **FR-016**: Specification MUST document that lanzaboote cannot be activated until Secure Boot keys are generated and enrolled
- **FR-017**: Specification MUST document that enabling Secure Boot in quickemu-based VMs may require lower-level tooling (direct QEMU/libvirt XML configuration)

### Key Entities *(include if feature involves data)*

- **Phase 1 (Base System)**: Initial deployment stage using `bin/test-deployment` that installs NixOS with ZFS encryption, TPM2 integration, and systemd-boot via nixos-anywhere
- **Phase 2 (Security Provisioning)**: Post-deployment stage using `bin/post-install-provisioner` that generates and enrolls Secure Boot keys via SSH
- **Secure Boot Keys**: Custom cryptographic keys (PK, KEK, db) generated by sbctl in `/var/lib/sbctl` that are enrolled in UEFI firmware to verify bootloader signatures
- **sbctl**: Tool used by `post-install-provisioner` to generate and manage Secure Boot keys
- **lanzaboote**: Secure Boot bootloader that replaces systemd-boot; cannot be activated until Secure Boot keys are in place
- **UEFI Variables**: Firmware storage containing Secure Boot configuration state (enabled/disabled, Setup Mode/User Mode, enrolled keys)
- **Boot Components**: The bootloader, kernel, and initrd that must be signed and verified during Secure Boot process
- **Enrollment State**: The configuration state tracking whether Secure Boot keys have been successfully generated and enrolled
- **VM Firmware Configuration**: UEFI firmware settings for the test VM; quickemu may not support Secure Boot, requiring direct QEMU/libvirt XML configuration

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Developers can run the test script once and have a fully deployed VM with Secure Boot enabled and verified in under 15 minutes
- **SC-002**: 100% of test runs on supported VM platforms successfully enroll and enable Secure Boot without manual intervention
- **SC-003**: Test script verification phase catches and reports all Secure Boot configuration failures within 30 seconds of completion
- **SC-004**: Test script executes all existing test steps (ZFS encryption, serial unlock, SSH access) plus Secure Boot enrollment without breaking existing functionality
- **SC-005**: Developers can identify Secure Boot support status within the first minute of script execution through clear log output
