# Feature Specification: Secure Boot Custom Key Enrollment

**Feature Branch**: `004-specify-scripts-bash`
**Created**: 2025-11-01
**Status**: Draft
**Input**: User description: "Generate our own keys and then enroll them. Then we need to verify that secure boot has been enabled. Reference this doc for more info, https://github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md. Note we do not actually want to get lanzaboote installed just yet, we simply want to enroll the secureboot keys and verify we are not in setup mode but have our custom secureboot keys used and secureboot mode is enabled. This should be verified in the test vm script."

## User Scenarios & Testing

### User Story 1 - Generate Custom Secure Boot Keys (Priority: P1)

As a system deployer, I need to generate custom Secure Boot keys so that I can enroll them in the VM's firmware and establish a trusted boot chain with my own Platform Key (PK), Key Exchange Key (KEK), and database keys.

**Why this priority**: This is the foundational step - without generating keys, enrollment cannot happen. This provides immediate value by creating the cryptographic foundation for custom Secure Boot.

**Independent Test**: Can be fully tested by running the key generation process and verifying that all required key files (PK, KEK, db) are created with correct permissions and formats, without requiring any subsequent enrollment steps.

**Acceptance Scenarios**:

1. **Given** a VM in Secure Boot Setup Mode, **When** the key generation process is initiated, **Then** the system creates Platform Key (PK), Key Exchange Key (KEK), and signature database (db) keys in the correct format
2. **Given** the key generation process completes, **When** examining the generated files, **Then** private keys have restricted permissions (readable only by root) and public keys are available for enrollment
3. **Given** no existing keys in the target directory, **When** generating keys, **Then** the process completes successfully without errors

---

### User Story 2 - Enroll Custom Keys in VM Firmware (Priority: P2)

As a system deployer, I need to enroll my custom Secure Boot keys into the VM's UEFI firmware so that the system transitions from Setup Mode to User Mode with my own trusted keys controlling the boot process.

**Why this priority**: Key enrollment is the critical step that activates Secure Boot with custom keys. It depends on P1 (key generation) but delivers the core security value by establishing firmware-level trust.

**Independent Test**: Can be tested independently by providing pre-generated keys and verifying successful enrollment through firmware variables, without requiring subsequent boot verification.

**Acceptance Scenarios**:

1. **Given** a VM in Setup Mode with generated Secure Boot keys, **When** the enrollment process runs, **Then** the Platform Key (PK) is enrolled in the firmware, transitioning the system from Setup Mode to User Mode
2. **Given** successful PK enrollment, **When** checking firmware variables, **Then** the KEK and db keys are also enrolled and visible in UEFI variables
3. **Given** the enrollment completes, **When** querying the firmware, **Then** the SetupMode variable changes from 1 (setup) to 0 (user)
4. **Given** Microsoft OEM certificates are included in enrollment (optional), **When** enrolling keys, **Then** the Microsoft keys are added to the signature database to maintain hardware OptionROM compatibility

---

### User Story 3 - Verify Secure Boot Enabled Status (Priority: P3)

As a system deployer, I need automated verification that Secure Boot has been successfully enabled with custom keys so that I can confirm the security posture of the deployed system without manual inspection.

**Why this priority**: Verification provides confidence and automation value but depends on P1 and P2. The system is technically functional after enrollment; verification adds operational assurance.

**Independent Test**: Can be tested by running verification checks against a VM with known Secure Boot state (either enabled or disabled), delivering value as a standalone diagnostic tool.

**Acceptance Scenarios**:

1. **Given** a VM with enrolled custom keys, **When** running verification checks, **Then** the system confirms Secure Boot status shows "enabled (user)" via bootctl or equivalent tooling
2. **Given** successful key enrollment, **When** verification runs, **Then** the system confirms SetupMode variable equals 0 (not in setup mode)
3. **Given** verification runs in the test VM script, **When** Secure Boot is not properly enabled, **Then** the test fails with a clear error message indicating the specific verification failure
4. **Given** verification runs in the test VM script, **When** Secure Boot is properly enabled with custom keys, **Then** the test passes and logs confirmation of the secure boot state

---

### Edge Cases

- What happens when key generation is attempted in a directory with existing keys? (System should error or prompt for confirmation to avoid overwriting)
- What happens when attempting to enroll keys on a VM that is not in Setup Mode? (Enrollment should fail with clear error message indicating firmware is not in Setup Mode)
- What happens when verification runs on a system where bootctl is not available? (Verification should fall back to checking EFI variables directly or clearly indicate the verification method is unavailable)
- What happens when the VM firmware has pre-enrolled Microsoft keys? (System should detect this and warn that it's not in Setup Mode, preventing custom key enrollment)
- What happens when enrollment partially succeeds (PK enrolled but KEK/db fail)? (System should detect partial enrollment and provide recovery guidance)

## Requirements

### Functional Requirements

- **FR-001**: System MUST generate three types of Secure Boot keys: Platform Key (PK), Key Exchange Key (KEK), and signature database (db) keys
- **FR-002**: System MUST store private keys with restricted permissions (readable only by root user)
- **FR-003**: System MUST verify the VM is in Setup Mode before attempting key enrollment
- **FR-004**: System MUST enroll the Platform Key (PK) first, which transitions the firmware from Setup Mode to User Mode
- **FR-005**: System MUST enroll Key Exchange Key (KEK) and database (db) keys after PK enrollment
- **FR-006**: System MUST support optional inclusion of Microsoft OEM certificates during enrollment for hardware compatibility
- **FR-007**: System MUST verify Secure Boot status after enrollment using firmware status queries
- **FR-008**: System MUST confirm the SetupMode variable transitions from 1 (setup) to 0 (user) after enrollment
- **FR-009**: Test VM script MUST include automated verification that Secure Boot is enabled with "user" mode (not "setup" mode)
- **FR-010**: Verification MUST check both bootctl status output and EFI firmware variables to confirm Secure Boot state
- **FR-011**: System MUST NOT install or integrate lanzaboote during this process (key enrollment only)
- **FR-012**: System MUST provide clear error messages when enrollment fails due to firmware not being in Setup Mode
- **FR-013**: Test script MUST fail if verification shows Secure Boot is still in Setup Mode after enrollment

### Key Entities

- **Secure Boot Keys**: Cryptographic key pairs (public/private) including Platform Key (PK), Key Exchange Key (KEK), and signature database (db) keys used to establish firmware trust chain
- **Firmware Variables**: UEFI variables including SetupMode (0 or 1), SecureBoot status, and enrolled key databases that represent the firmware's security state
- **VM Test Environment**: The libvirt-based test VM that boots in UEFI Secure Boot Setup Mode, providing the target environment for key enrollment and verification

## Success Criteria

### Measurable Outcomes

- **SC-001**: Key generation completes in under 30 seconds and produces all required key files (PK, KEK, db) with correct permissions
- **SC-002**: Key enrollment process successfully transitions VM from Setup Mode to User Mode in under 60 seconds
- **SC-003**: Verification correctly identifies Secure Boot status (enabled vs disabled, setup vs user) with 100% accuracy
- **SC-004**: Test VM script includes automated verification that passes when Secure Boot is properly enabled and fails when it is not
- **SC-005**: System produces clear, actionable error messages when enrollment fails, indicating the specific failure reason (e.g., "Firmware not in Setup Mode")

## Assumptions

- The VM firmware (OVMF) is already configured to boot in Secure Boot Setup Mode (no pre-enrolled keys)
- The test environment has access to tools for querying EFI variables (e.g., efivar, bootctl)
- Key generation uses industry-standard cryptographic tools available in the NixOS installer environment
- The bin/test-deployment script is the appropriate location for adding Secure Boot verification checks
- Verification will primarily use bootctl status command with fallback to direct EFI variable inspection
- Microsoft OEM certificate inclusion is optional and can be implemented as a flag or configuration option

## Out of Scope

- Installation or integration of lanzaboote (deferred to future feature)
- Signing of bootloader or kernel binaries with the enrolled keys
- Automatic key rotation or key management lifecycle
- Multi-boot scenarios with other operating systems
- Recovery mechanisms for systems with corrupted or lost keys
- Integration with hardware TPM for key storage (uses firmware variables only)
