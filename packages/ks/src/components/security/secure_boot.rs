//! Secure Boot enrollment — sbctl key management.
//!
//! Onboarding Stage 5: guides the user through Secure Boot key enrollment.
//!
//! Flow:
//! 1. Check sbctl status (enrolled / setup mode / not in setup mode)
//! 2. If setup mode → run `sbctl enroll-keys --microsoft`
//! 3. Verify enrollment succeeded
//! 4. Prompt reboot

/// Secure Boot enrollment state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    /// Not yet checked.
    Unknown,
    /// Keys are already enrolled.
    Enrolled,
    /// UEFI is in setup mode — ready to enroll.
    SetupMode,
    /// Not in setup mode — user must enable in BIOS first.
    NotInSetupMode,
}

/// Check Secure Boot status via sbctl.
///
/// TODO: run `sbctl status` and parse output to determine Status
pub async fn check_status() -> Status {
    Status::Unknown
}

/// Enroll Secure Boot keys via sbctl.
///
/// TODO: run `sbctl enroll-keys --microsoft`, capture output
pub async fn enroll_keys() -> anyhow::Result<String> {
    anyhow::bail!("Secure Boot enrollment not yet implemented")
}
