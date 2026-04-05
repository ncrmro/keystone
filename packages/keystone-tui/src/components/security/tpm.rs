//! TPM2 enrollment — automatic disk unlock via PCR policy.
//!
//! Onboarding Stage 5: guides the user through TPM2 enrollment
//! so the disk unlocks automatically on trusted boots.
//!
//! Flow:
//! 1. Check if TPM2 device exists (/dev/tpmrm0)
//! 2. Enroll LUKS key with systemd-cryptenroll --tpm2-device=auto
//! 3. Verify unlock works
//! 4. Prompt reboot

/// TPM2 enrollment state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    /// Not yet checked.
    Unknown,
    /// TPM2 device detected, not yet enrolled.
    Available,
    /// Already enrolled for auto-unlock.
    Enrolled,
    /// No TPM2 device found.
    NotAvailable,
}

/// Check TPM2 status.
///
/// TODO: check /dev/tpmrm0 exists, check if LUKS already has TPM2 token
pub async fn check_status() -> Status {
    Status::Unknown
}

/// Enroll TPM2 for automatic disk unlock.
///
/// TODO: run `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=1+7`
pub async fn enroll() -> anyhow::Result<String> {
    anyhow::bail!("TPM2 enrollment not yet implemented")
}
