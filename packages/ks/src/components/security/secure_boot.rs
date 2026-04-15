//! Secure Boot enrollment — sbctl key management.
//!
//! Onboarding Stage 5: guides the user through Secure Boot key enrollment.
//!
//! Flow:
//! 1. Check sbctl status (enrolled / setup mode / not in setup mode)
//! 2. If setup mode → generate keys if needed, then enroll
//! 3. Verify enrollment succeeded
//! 4. Prompt reboot

use anyhow::Context;
use tokio::process::Command;

const PKI_BUNDLE: &str = "/var/lib/sbctl";
const DB_PEM: &str = "/var/lib/sbctl/keys/db/db.pem";

/// Secure Boot enrollment state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    /// Not yet checked.
    Unknown,
    /// Secure Boot enabled in user mode — keys enrolled and active.
    Enrolled,
    /// Keys exist at /var/lib/sbctl but Secure Boot not yet active (needs reboot).
    KeysGenerated,
    /// UEFI is in setup mode — ready to enroll.
    SetupMode,
    /// Not in setup mode, no keys — user must enable Setup Mode in BIOS.
    NotInSetupMode,
}

/// Check Secure Boot status via `sbctl status`.
///
/// Parses lines like:
///   Secure Boot:  ✓ Enabled
///   Setup Mode:   ✓ Enabled
pub async fn check_status() -> Status {
    let output = match Command::new("sbctl").arg("status").output().await {
        Ok(o) => o,
        Err(_) => return Status::Unknown,
    };

    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
    );

    let secure_boot_enabled = text
        .lines()
        .any(|l| l.contains("Secure Boot:") && l.contains("Enabled"));

    let setup_mode_enabled = text
        .lines()
        .any(|l| l.contains("Setup Mode:") && l.contains("Enabled"));

    if secure_boot_enabled {
        return Status::Enrolled;
    }

    // Keys exist but SB not active yet — generated during install, awaiting reboot
    if keys_exist() {
        return Status::KeysGenerated;
    }

    if setup_mode_enabled {
        return Status::SetupMode;
    }

    // sbctl ran but we couldn't parse meaningful status
    if text.contains("Setup Mode:") {
        return Status::NotInSetupMode;
    }

    Status::Unknown
}

/// Generate Secure Boot keys via `sbctl create-keys`.
///
/// Idempotent: returns Ok immediately if keys already exist.
pub async fn generate_keys() -> anyhow::Result<String> {
    if keys_exist() {
        return Ok("Secure Boot keys already exist.".into());
    }

    let output = Command::new("sbctl")
        .arg("create-keys")
        .output()
        .await
        .context("failed to run sbctl create-keys")?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if output.status.success() {
        Ok(format!("{}{}", stdout, stderr).trim().to_string())
    } else {
        anyhow::bail!(
            "sbctl create-keys failed: {}{}",
            stdout.trim(),
            stderr.trim()
        )
    }
}

/// Enroll Secure Boot keys via `sbctl enroll-keys`.
pub async fn enroll_keys() -> anyhow::Result<String> {
    let output = Command::new("sbctl")
        .args(["enroll-keys", "--yes-this-might-brick-my-machine"])
        .output()
        .await
        .context("failed to run sbctl enroll-keys")?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if output.status.success() {
        Ok(format!("{}{}", stdout, stderr).trim().to_string())
    } else {
        anyhow::bail!(
            "sbctl enroll-keys failed: {}{}",
            stdout.trim(),
            stderr.trim()
        )
    }
}

/// Check whether SB keys have been generated at the expected PKI bundle path.
fn keys_exist() -> bool {
    std::path::Path::new(DB_PEM).exists()
}

/// Provision Secure Boot: generate keys and enroll if in setup mode.
///
/// Called by `ks provision-secure-boot` and the install flow.
pub async fn provision() -> anyhow::Result<String> {
    if keys_exist() {
        let status = check_status().await;
        return match status {
            Status::Enrolled => Ok("Secure Boot is already enrolled.".into()),
            Status::KeysGenerated => {
                Ok("Keys exist. Reboot to activate Secure Boot.".into())
            }
            _ => Ok("Secure Boot keys already exist.".into()),
        };
    }

    generate_keys().await?;

    let status = check_status().await;
    if status == Status::SetupMode {
        enroll_keys().await?;
        Ok("Keys generated and enrolled. Reboot to activate Secure Boot.".into())
    } else {
        Ok("Keys generated. Enter UEFI Setup Mode and re-run to enroll.".into())
    }
}
