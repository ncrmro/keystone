# Feature Specification: TPM-Based Disk Encryption Enrollment

**Feature Branch**: `006-tpm-enrollment`
**Created**: 2025-11-03
**Status**: Draft
**Input**: User description: "After the test-vm boots for the first time, secureboot is fully enabled with our custom keys. We now need a TPM nix module..."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - First-Boot TPM Enrollment Notification (Priority: P1)

After installing Keystone on a new system with Secure Boot enabled, the system administrator needs to know that TPM enrollment has not yet been configured so they can complete the security setup.

**Why this priority**: This is the foundation of the entire feature - without notifying users that TPM is not enrolled, they won't know they need to take action. This is a security-critical notification that ensures users don't leave their systems in a partially-secured state.

**Independent Test**: Can be fully tested by performing a fresh Keystone installation on a VM with Secure Boot enabled, logging in for the first time, and verifying the enrollment status banner appears. Delivers immediate value by informing users of their security posture.

**Acceptance Scenarios**:

1. **Given** a fresh Keystone installation with Secure Boot enabled and TPM not yet enrolled, **When** the user logs in for the first time, **Then** a clear warning banner is displayed indicating TPM enrollment has not been configured
2. **Given** the TPM enrollment warning banner is displayed, **When** the user reads the message, **Then** it clearly explains what TPM enrollment means and why it's important for system security
3. **Given** a system where TPM has already been enrolled, **When** the user logs in, **Then** no TPM enrollment warning is displayed

---

### User Story 2 - Generate Recovery Key (Priority: P2)

After being notified that TPM is not enrolled, the system administrator needs to generate a secure recovery key to ensure they can unlock the disk if TPM becomes unavailable (e.g., hardware failure, PCR changes).

**Why this priority**: Recovery keys are essential for business continuity and disaster recovery. Without them, hardware changes or TPM failures could result in complete data loss. This should be configured before users store critical data on the system.

**Independent Test**: Can be fully tested by triggering the recovery key generation flow on a fresh installation, saving the generated key, and verifying it works by simulating a TPM failure scenario. Delivers standalone value as a backup authentication method.

**Acceptance Scenarios**:

1. **Given** the TPM enrollment notification is displayed, **When** the user chooses to generate a recovery key, **Then** the system generates a cryptographically secure recovery key
2. **Given** a recovery key has been generated, **When** the generation process completes, **Then** the key is displayed to the user with clear instructions to save it in a secure location
3. **Given** a recovery key has been generated and saved, **When** the user confirms they have saved the key, **Then** the default LUKS password "keystone" is removed from the credstore volume
4. **Given** a recovery key has been enrolled, **When** TPM becomes unavailable (PCR mismatch or hardware failure), **Then** the user can unlock the disk using the recovery key
5. **Given** the recovery key generation process fails, **When** the error occurs, **Then** the user receives a clear error message and the default "keystone" password remains active

---

### User Story 3 - Replace Default Password with Custom Password (Priority: P2)

After being notified that TPM is not enrolled, the system administrator needs to replace the default "keystone" password with their own secure password to protect against unauthorized access if TPM fails.

**Why this priority**: While TPM provides automatic unlock, having a strong custom password as fallback is critical for security. The default "keystone" password is publicly known and represents a security vulnerability. This priority is equal to P2 (same as recovery key) because users should choose either recovery key OR custom password.

**Independent Test**: Can be fully tested by triggering the password replacement flow, setting a new password, removing the default password, and verifying the new password works during boot. Delivers standalone value as an alternative authentication method.

**Acceptance Scenarios**:

1. **Given** the TPM enrollment notification is displayed, **When** the user chooses to replace the default password, **Then** the system prompts for a new password
2. **Given** the password replacement prompt is displayed, **When** the user enters and confirms a new password meeting minimum complexity requirements, **Then** the new password is added to the LUKS keyslot
3. **Given** a new custom password has been added, **When** the enrollment completes successfully, **Then** the default "keystone" password is removed from the credstore volume
4. **Given** the password replacement process has been completed, **When** the user needs to unlock the disk manually (TPM unavailable), **Then** they can unlock using their custom password
5. **Given** the user enters passwords that don't match during confirmation, **When** the mismatch is detected, **Then** an error is displayed and the user can retry
6. **Given** the password replacement process fails, **When** the error occurs, **Then** the user receives a clear error message and the default "keystone" password remains active

---

### User Story 4 - Automatic TPM Enrollment (Priority: P3)

After the user has configured either a recovery key or custom password, the system should automatically configure TPM-based unlock so that future boots don't require manual password entry under normal conditions.

**Why this priority**: This is the final step that enables the convenience of automatic unlock. While important for user experience, the system is already secure after P1-P2 are complete (user aware of security state + backup authentication configured). This can be deferred if needed.

**Independent Test**: Can be fully tested by completing the recovery key or password setup, verifying TPM enrollment occurs automatically, rebooting the system, and confirming automatic unlock works. Delivers standalone value as a convenience feature.

**Acceptance Scenarios**:

1. **Given** the user has successfully configured a recovery key or custom password, **When** they complete the enrollment process, **Then** the system automatically enrolls TPM unlock using PCRs 1 and 7
2. **Given** TPM enrollment has been configured, **When** the system reboots under normal conditions (no firmware changes), **Then** the disk unlocks automatically without requiring password entry
3. **Given** TPM enrollment has been configured, **When** firmware or bootloader changes occur (PCR values change), **Then** automatic unlock fails and the system prompts for the recovery key or custom password
4. **Given** the TPM enrollment process is triggered, **When** Secure Boot is not enabled, **Then** the enrollment fails with a clear error message explaining Secure Boot is required
5. **Given** the TPM enrollment process is triggered, **When** no TPM hardware is available, **Then** the enrollment fails gracefully with an informative error message

---

### Edge Cases

- What happens when the user attempts to enroll TPM but Secure Boot was disabled after installation?
- How does the system handle TPM enrollment when no TPM2 device is available (VM without emulated TPM, older hardware)?
- What happens if the systemd-cryptenroll command fails during TPM enrollment?
- How does the system behave if the user configures both a recovery key AND a custom password?
- What happens when the credstore volume is full and cannot accept additional LUKS keyslots?
- How does the system handle PCR bank incompatibilities or TPM firmware bugs?
- What happens if the user loses their recovery key and forgets their custom password after TPM fails?
- How does the system behave during the transition period where both "keystone" and the new credential exist?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect whether TPM enrollment has been completed during user login
- **FR-002**: System MUST display a warning banner on first login when TPM has not been enrolled
- **FR-003**: System MUST provide the user with two options for securing disk access: generate recovery key or set custom password
- **FR-004**: System MUST generate a cryptographically secure recovery key using industry-standard key derivation functions
- **FR-005**: System MUST validate that Secure Boot is enabled before allowing TPM enrollment to proceed
- **FR-006**: System MUST enroll TPM unlock using PCRs 1 and 7 when automatic enrollment is triggered
- **FR-007**: System MUST remove the default "keystone" LUKS password after successfully enrolling either recovery key or custom password
- **FR-008**: System MUST validate custom passwords meet minimum security requirements (minimum length: 12 characters)
- **FR-009**: System MUST target the credstore volume (/dev/zvol/rpool/credstore) for all LUKS operations
- **FR-010**: System MUST provide clear error messages when TPM enrollment fails, including specific reasons (no Secure Boot, no TPM device, etc.)
- **FR-011**: System MUST preserve existing LUKS keyslots when adding new credentials (until explicitly removed)
- **FR-012**: System MUST verify TPM enrollment succeeded before removing the default password
- **FR-013**: System MUST be deployed via nixos-anywhere but not execute automatically until first boot
- **FR-014**: System MUST prevent TPM enrollment if Secure Boot is not fully enabled with custom keys
- **FR-015**: System MUST use systemd-cryptenroll with --wipe-slot=empty to avoid removing existing credentials during enrollment
- **FR-016**: System MUST provide documentation explaining when recovery key or custom password would be needed (PCR changes, TPM failure, hardware replacement)

### Key Entities *(include if feature involves data)*

- **TPM Enrollment State**: Represents whether TPM-based unlock has been configured; tracked via presence of TPM keyslot in LUKS header
- **Credstore Volume**: The LUKS-encrypted ZFS volume at /dev/zvol/rpool/credstore that stores encryption keys for the main filesystem
- **LUKS Keyslot**: Container for authentication credentials; system uses multiple slots for default password, custom password, recovery key, and TPM unlock
- **Recovery Key**: A cryptographically secure credential that allows disk unlock when TPM is unavailable; must be stored offline by user
- **PCR Values**: Platform Configuration Register measurements that represent system boot state; changes to PCRs invalidate TPM unlock

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users receive clear notification of TPM enrollment status within 10 seconds of first login on a fresh installation
- **SC-002**: Users can complete the entire TPM enrollment process (notification → credential setup → TPM enrollment) in under 5 minutes
- **SC-003**: After TPM enrollment, systems boot and unlock automatically in under 30 seconds without user intervention (under normal conditions with unchanged PCRs)
- **SC-004**: Recovery keys or custom passwords successfully unlock the disk 100% of the time when TPM is unavailable
- **SC-005**: TPM enrollment fails gracefully with actionable error messages when Secure Boot is disabled, preventing insecure configurations
- **SC-006**: After successful enrollment, the default "keystone" password is removed, confirmed by LUKS keyslot inspection showing no "keystone" keyslot
- **SC-007**: Documentation clearly explains recovery scenarios, reducing user confusion about when backup credentials are needed

## Assumptions

- **Assumption 1**: Users have physical or KVM access to the console during first boot to view the enrollment notification
- **Assumption 2**: TPM2 hardware or emulation is available on target systems (feature gracefully fails on systems without TPM)
- **Assumption 3**: Secure Boot has already been configured with custom keys during installation (as per existing Keystone installation process)
- **Assumption 4**: Users understand the importance of saving recovery keys in a secure offline location (documentation will reinforce this)
- **Assumption 5**: The credstore volume has sufficient available LUKS keyslots (LUKS2 supports up to 32 keyslots)
- **Assumption 6**: Users will choose either recovery key OR custom password, not necessarily both (though both is supported)
- **Assumption 7**: PCR 1 (firmware configuration) and PCR 7 (Secure Boot state) are sufficient for most use cases while maintaining reasonable resilience to firmware updates

## Out of Scope

The following items are explicitly **out of scope** for this specification but should be tracked as future enhancements:

- **Network-unlock via Tailscale**: Partial unlock that enables SSH access via Tailscale for remote manual unlock
- **TPM2-TOTP**: Time-based one-time password generation for visual verification of boot state integrity
- **Automatic key rotation**: Periodic regeneration of recovery keys or TPM credentials
- **Multi-factor unlock**: Requiring both TPM AND password/key for unlock
- **Remote attestation**: Verifying system integrity via remote TPM attestation server
- **Key escrow**: Centralized storage of recovery keys for enterprise deployments
- **TPM-based encryption of other secrets**: Using TPM to protect SSH keys, Tailscale credentials, etc.
- **Custom PCR selection**: Allowing users to configure which PCRs to use for TPM unlock (fixed to PCRs 1,7 for this feature)
