//! Native LUKS enrollment primitives.
//!
//! Direct invocations of `systemd-cryptenroll` and `cryptsetup` with
//! captured stdout/stdin — no shell scripts in the loop. Replaces the
//! four `enroll-*.sh` scripts under `modules/os/scripts/` that this
//! module previously wrapped.
//!
//! Design split:
//!
//! - Pure helpers ([`validate_passphrase`], [`parse_recovery_key`]) are
//!   unit-tested without a real LUKS device or TPM.
//! - IO-doing helpers ([`preflight`], [`current_passphrase_keyfile`],
//!   [`run_systemd_cryptenroll`]) shell out via `tokio::process::Command`
//!   and propagate stderr context on failure.
//! - Each `enroll_*` primitive composes the helpers into the canonical
//!   four-step flow: preflight → unlock-key → systemd-cryptenroll →
//!   verify + marker.

use std::path::Path;

use anyhow::{anyhow, bail, Context, Result};
use regex::Regex;
use tempfile::NamedTempFile;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

use super::probe::{self, Method, DEFAULT_PASSWORD, ROOT_CREDSTORE};

/// PCRs that `keystone.os.tpm.pcrs` defaults to. The orchestrator does
/// not currently override these per-host — that's tracked as a v1.2
/// option once non-root volume support lands.
const TPM_PCRS: &str = "1,7";

const ENROLLMENT_MARKER: &str = "/var/lib/keystone/tpm-enrollment-complete";

const MIN_PASSPHRASE_LEN: usize = 12;
const MAX_PASSPHRASE_LEN: usize = 64;

// ---------------------------------------------------------------------------
// Public dispatch
// ---------------------------------------------------------------------------

/// Top-level dispatch for `ks hardware enroll <method>` (and the
/// canonical `ks hardware disks <id> fde enroll <method>` form).
pub async fn execute(method: Method, disk: Option<String>) -> Result<()> {
    let disk = disk.unwrap_or_else(|| "root".to_string());
    if disk != "root" && method.is_luks_unlock_method() {
        bail!(
            "enrollment on non-root LUKS volumes is not yet implemented (target: {}). \
             v1.1 RC supports the root credstore only; additional volumes land in v1.2.",
            disk
        );
    }
    match method {
        Method::Password => enroll_password().await,
        Method::Recovery => enroll_recovery().await,
        Method::Tpm2 => enroll_tpm().await,
        Method::Fido2 => enroll_fido2().await,
        Method::Fingerprint => enroll_fingerprint().await,
    }
}

// ---------------------------------------------------------------------------
// Per-method primitives
// ---------------------------------------------------------------------------

/// Rotate the LUKS slot-0 passphrase. After this runs, the default
/// installer string ("keystone") no longer unlocks the disk; the
/// user-chosen passphrase does. TPM/FIDO2 enrollment are out of scope
/// for this primitive — they're separate slots and `enroll_recovery`
/// / `enroll_tpm` handle them.
pub async fn enroll_password() -> Result<()> {
    println!("=== Keystone enrollment: rotate LUKS password ===\n");
    preflight().await?;

    let new_pw = read_new_passphrase_with_confirmation()?;
    let old_keyfile = current_passphrase_keyfile().await?;

    println!("\nRotating slot 0 to the new passphrase...");
    let device = Path::new(ROOT_CREDSTORE);
    let mut child = Command::new("cryptsetup")
        .arg("luksChangeKey")
        .arg(device)
        .arg("--key-file")
        .arg(old_keyfile.path())
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::inherit())
        .stderr(std::process::Stdio::inherit())
        .spawn()
        .context("spawning cryptsetup luksChangeKey")?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(new_pw.as_bytes()).await?;
        stdin.write_all(b"\n").await?;
        stdin.shutdown().await?;
    }
    let status = child.wait().await?;
    if !status.success() {
        bail!("cryptsetup luksChangeKey failed: {}", status);
    }
    println!("[OK] LUKS slot 0 rotated.\n");
    Ok(())
}

/// Generate a recovery key, display it once, then enroll TPM2 in the
/// same run. The slot 0 passphrase is preserved as a manual fallback
/// (the `--wipe-slot=password` flag the old script used is gone — see
/// the layered-fallback design).
pub async fn enroll_recovery() -> Result<()> {
    println!("=== Keystone enrollment: recovery key + TPM2 ===\n");
    preflight().await?;
    let keyfile = current_passphrase_keyfile().await?;
    let device = Path::new(ROOT_CREDSTORE);
    let device_str = device.to_string_lossy().to_string();
    let unlock_arg = format!("--unlock-key-file={}", keyfile.path().display());
    let pcrs_arg = format!("--tpm2-pcrs={}", TPM_PCRS);

    println!("[Step 1/3] Generating recovery key...");
    let stdout = run_systemd_cryptenroll(&[&device_str, "--recovery-key", &unlock_arg])
        .await
        .context("generating recovery key")?;

    let recovery_key = parse_recovery_key(&stdout)
        .ok_or_else(|| anyhow!("could not extract recovery key from systemd-cryptenroll output"))?;
    display_recovery_key(&recovery_key);

    println!("[Step 2/3] Enrolling TPM2 (PCRs {})...", TPM_PCRS);
    run_systemd_cryptenroll(&[&device_str, "--tpm2-device=auto", &pcrs_arg, &unlock_arg])
        .await
        .context("enrolling TPM2")?;
    println!("[OK] TPM2 enrolled (password slot preserved as manual fallback).\n");

    println!("[Step 3/3] Writing enrollment marker...");
    write_enrollment_marker("recovery-key+tpm2").await?;
    println!("[OK] Done. Test with: sudo reboot\n");
    Ok(())
}

/// Standalone TPM2 enrollment — used for re-binding after PCR drift
/// (kernel upgrade, BIOS change, etc.). Assumes a non-default
/// passphrase already exists; the current-passphrase probe will
/// prompt for it if `keystone` no longer unlocks.
pub async fn enroll_tpm() -> Result<()> {
    println!("=== Keystone enrollment: TPM2 (standalone) ===\n");
    preflight().await?;
    let keyfile = current_passphrase_keyfile().await?;
    let device = Path::new(ROOT_CREDSTORE);
    let device_str = device.to_string_lossy().to_string();
    let unlock_arg = format!("--unlock-key-file={}", keyfile.path().display());
    let pcrs_arg = format!("--tpm2-pcrs={}", TPM_PCRS);

    println!("Enrolling TPM2 (PCRs {})...", TPM_PCRS);
    run_systemd_cryptenroll(&[&device_str, "--tpm2-device=auto", &pcrs_arg, &unlock_arg])
        .await
        .context("enrolling TPM2")?;
    println!("[OK] TPM2 enrolled.\n");

    write_enrollment_marker("standalone-tpm2").await?;
    println!("Test with: sudo reboot\n");
    Ok(())
}

/// Enroll the plugged-in FIDO2 device for LUKS unlock. Requires
/// `systemd-cryptenroll --fido2-device=list` to return at least one
/// device, and the user to touch it when prompted.
pub async fn enroll_fido2() -> Result<()> {
    println!("=== Keystone enrollment: FIDO2 hardware key ===\n");
    preflight().await?;

    let device_list = run_systemd_cryptenroll(&["--fido2-device=list"])
        .await
        .context("listing FIDO2 devices")?;
    let devices = probe::parse_fido2_device_list(&device_list);
    if devices.is_empty() {
        bail!("no FIDO2 hardware key detected — plug one in and re-run");
    }
    println!("Detected FIDO2 device: {}", devices[0].label);

    let keyfile = current_passphrase_keyfile().await?;
    let device = Path::new(ROOT_CREDSTORE);
    let device_str = device.to_string_lossy().to_string();
    let unlock_arg = format!("--unlock-key-file={}", keyfile.path().display());

    println!("\nTouch your FIDO2 device when it blinks...");
    run_systemd_cryptenroll(&[&device_str, "--fido2-device=auto", &unlock_arg])
        .await
        .context("enrolling FIDO2")?;
    println!("[OK] FIDO2 enrolled.\n");
    Ok(())
}

/// Enroll a fingerprint via `fprintd-enroll`. Off the LUKS path —
/// fingerprint auths sudo/login, not the disk.
pub async fn enroll_fingerprint() -> Result<()> {
    if !is_executable_present("fprintd-enroll") {
        bail!(
            "fprintd-enroll is not installed; fingerprint enrollment is unavailable on this host"
        );
    }
    let status = Command::new("fprintd-enroll")
        .status()
        .await
        .map_err(|e| anyhow!("failed to spawn fprintd-enroll: {}", e))?;
    if !status.success() {
        bail!("fprintd-enroll exited with {}", status);
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// IO helpers
// ---------------------------------------------------------------------------

/// Preflight: Secure Boot enabled, TPM2 device present, credstore
/// device exists. Mirrors the prerequisite blocks the old enroll-*.sh
/// scripts ran before doing anything destructive.
async fn preflight() -> Result<()> {
    println!("[Preflight]");
    let report = probe::probe().await;
    if matches!(report.machine.secure_boot, probe::SecureBootState::Disabled) {
        bail!(
            "Secure Boot is DISABLED. TPM PCR-7 binding has no integrity anchor. \
             Enable Secure Boot in firmware before enrolling."
        );
    }
    println!("[OK] Secure Boot: {:?}", report.machine.secure_boot);

    if !matches!(report.machine.tpm2, probe::TpmDeviceState::Present) {
        bail!("no TPM2 device found at /dev/tpmrm0");
    }
    println!("[OK] TPM2 device present");

    if !Path::new(ROOT_CREDSTORE).exists() {
        bail!("credstore device not found: {}", ROOT_CREDSTORE);
    }
    println!("[OK] Credstore device: {}\n", ROOT_CREDSTORE);
    Ok(())
}

/// Discover the current slot-0 passphrase and return a tempfile
/// holding it for use as `--unlock-key-file=<path>`.
///
/// First tries the installer default ("keystone"). If that doesn't
/// unlock, prompts the user interactively (no echo) for their current
/// passphrase and verifies it via `cryptsetup --test-passphrase`.
async fn current_passphrase_keyfile() -> Result<NamedTempFile> {
    let device = Path::new(ROOT_CREDSTORE);

    if test_passphrase(device, DEFAULT_PASSWORD).await? {
        return write_tempfile(DEFAULT_PASSWORD.as_bytes());
    }

    println!("Default installer password no longer unlocks slot 0.");
    println!("Enter your current LUKS passphrase to authorize enrollment:");
    let pw = rpassword::prompt_password("Passphrase: ").context("reading current passphrase")?;
    if pw.is_empty() {
        bail!("empty passphrase rejected");
    }
    if !test_passphrase(device, &pw).await? {
        bail!("that passphrase does not unlock slot 0");
    }
    write_tempfile(pw.as_bytes())
}

/// Returns true iff `passphrase` unlocks `device`.
async fn test_passphrase(device: &Path, passphrase: &str) -> Result<bool> {
    let mut child = Command::new("cryptsetup")
        .args(["open", "--test-passphrase"])
        .arg(device)
        .arg("--key-file=-")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .context("spawning cryptsetup --test-passphrase")?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(passphrase.as_bytes()).await.ok();
        stdin.shutdown().await.ok();
    }
    Ok(matches!(child.wait().await, Ok(s) if s.success()))
}

/// Write `data` to a fresh tempfile and return the handle. The handle
/// keeps the file alive (and unlinks it on drop), so callers should
/// hold it for the lifetime of the unlock-key consumer process.
fn write_tempfile(data: &[u8]) -> Result<NamedTempFile> {
    use std::io::Write as _;
    let mut tf = NamedTempFile::new().context("creating tempfile for unlock key")?;
    tf.write_all(data).context("writing unlock-key tempfile")?;
    tf.flush()?;
    Ok(tf)
}

/// Spawn `systemd-cryptenroll` with the given args, capture stdout +
/// stderr, and return stdout on success. Stderr is folded into the
/// error context on failure.
async fn run_systemd_cryptenroll(args: &[&str]) -> Result<String> {
    let output = Command::new("systemd-cryptenroll")
        .args(args)
        .output()
        .await
        .context("spawning systemd-cryptenroll")?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() {
        bail!(
            "systemd-cryptenroll {:?} failed: {}\n{}",
            args,
            output.status,
            stderr.trim()
        );
    }
    // systemd-cryptenroll often writes status to stderr; surface it so
    // the user sees the same flow as the script's `tee` did.
    if !stderr.trim().is_empty() {
        eprintln!("{}", stderr.trim());
    }
    Ok(stdout)
}

fn is_executable_present(name: &str) -> bool {
    crate::cmd::util::find_executable(name).is_some()
}

async fn write_enrollment_marker(method: &str) -> Result<()> {
    if let Some(parent) = Path::new(ENROLLMENT_MARKER).parent() {
        tokio::fs::create_dir_all(parent).await.ok();
    }
    let timestamp = chrono::Utc::now().to_rfc3339();
    let body = format!(
        "Enrollment completed: {}\nMethod: {}\nTPM PCRs: {}\n",
        timestamp, method, TPM_PCRS
    );
    tokio::fs::write(ENROLLMENT_MARKER, body)
        .await
        .with_context(|| format!("writing {}", ENROLLMENT_MARKER))?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Pure helpers (unit-testable)
// ---------------------------------------------------------------------------

/// Prompt for a new LUKS passphrase twice (with confirmation),
/// validate length and disallow the default placeholder. No echo on
/// either prompt.
fn read_new_passphrase_with_confirmation() -> Result<String> {
    println!(
        "New LUKS passphrase ({} to {} characters, cannot be \"{}\"):",
        MIN_PASSPHRASE_LEN, MAX_PASSPHRASE_LEN, DEFAULT_PASSWORD
    );
    loop {
        let pw1 = rpassword::prompt_password("Passphrase: ").context("reading new passphrase")?;
        if let Err(e) = validate_passphrase(&pw1) {
            eprintln!("[error] {}", e);
            continue;
        }
        let pw2 =
            rpassword::prompt_password("Confirm: ").context("reading passphrase confirmation")?;
        if pw1 != pw2 {
            eprintln!("[error] passphrases do not match");
            continue;
        }
        return Ok(pw1);
    }
}

/// Pure validation: length bounds + reject the installer default.
fn validate_passphrase(pw: &str) -> Result<()> {
    if pw.is_empty() || pw.trim().is_empty() {
        bail!("passphrase cannot be empty");
    }
    let len = pw.chars().count();
    if len < MIN_PASSPHRASE_LEN {
        bail!(
            "passphrase must be at least {} characters (got {})",
            MIN_PASSPHRASE_LEN,
            len
        );
    }
    if len > MAX_PASSPHRASE_LEN {
        bail!(
            "passphrase must be at most {} characters (got {})",
            MAX_PASSPHRASE_LEN,
            len
        );
    }
    if pw.eq_ignore_ascii_case(DEFAULT_PASSWORD) {
        bail!(
            "passphrase \"{}\" is not allowed (publicly known installer default)",
            DEFAULT_PASSWORD
        );
    }
    Ok(())
}

/// Extract the 8-word recovery key from `systemd-cryptenroll
/// --recovery-key` stdout. The key is formatted as 8 dash-separated
/// 8-letter groups: `aaaaaaaa-bbbbbbbb-...-hhhhhhhh`.
pub fn parse_recovery_key(stdout: &str) -> Option<String> {
    let re = Regex::new(r"([a-z]{8}(?:-[a-z]{8}){7})").ok()?;
    re.captures(stdout)
        .and_then(|c| c.get(1))
        .map(|m| m.as_str().to_string())
}

fn display_recovery_key(key: &str) {
    println!();
    println!("+-------------------------------------------------------------------------+");
    println!("|                       YOUR RECOVERY KEY                                 |");
    println!("+-------------------------------------------------------------------------+");
    println!("|                                                                         |");
    println!("|  {}  |", key);
    println!("|                                                                         |");
    println!("+-------------------------------------------------------------------------+");
    println!();
    println!("[!] Save this key immediately. It will not be shown again.");
    println!();
    println!("Store in:");
    println!("  - Password manager with offline backup");
    println!("  - Printed paper in physical safe");
    println!();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_passphrase_rejects_empty() {
        assert!(validate_passphrase("").is_err());
        assert!(validate_passphrase("    ").is_err());
    }

    #[test]
    fn validate_passphrase_rejects_too_short() {
        assert!(validate_passphrase("short").is_err());
        assert!(validate_passphrase(&"a".repeat(MIN_PASSPHRASE_LEN - 1)).is_err());
    }

    #[test]
    fn validate_passphrase_rejects_too_long() {
        assert!(validate_passphrase(&"a".repeat(MAX_PASSPHRASE_LEN + 1)).is_err());
    }

    #[test]
    fn validate_passphrase_accepts_boundary_lengths() {
        assert!(validate_passphrase(&"a".repeat(MIN_PASSPHRASE_LEN)).is_ok());
        assert!(validate_passphrase(&"a".repeat(MAX_PASSPHRASE_LEN)).is_ok());
    }

    #[test]
    fn validate_passphrase_rejects_default_keystone() {
        assert!(validate_passphrase("keystone").is_err());
        assert!(validate_passphrase("KEYSTONE").is_err());
        assert!(validate_passphrase("KeyStone").is_err());
    }

    #[test]
    fn validate_passphrase_accepts_typical_strong() {
        assert!(validate_passphrase("correct horse battery staple").is_ok());
        assert!(validate_passphrase("ZF8x!42mqQ@w99").is_ok());
    }

    #[test]
    fn parse_recovery_key_matches_systemd_cryptenroll_output() {
        let stdout = "\
🔐 Please enter current passphrase for disk /dev/zvol/rpool/credstore:
A new recovery key has been generated and added as key slot 1.
🔐 The recovery key is:
    cgecnccb-gkglvevj-vihtbgee-jetghjkr-gtrvuljc-vhdirfdc-jtccfikg-jifuhvkf
(In addition to the recovery key, ...)
";
        assert_eq!(
            parse_recovery_key(stdout).as_deref(),
            Some("cgecnccb-gkglvevj-vihtbgee-jetghjkr-gtrvuljc-vhdirfdc-jtccfikg-jifuhvkf")
        );
    }

    #[test]
    fn parse_recovery_key_returns_none_when_absent() {
        assert!(parse_recovery_key("nothing here").is_none());
        assert!(parse_recovery_key("").is_none());
    }

    #[test]
    fn parse_recovery_key_rejects_partial_groups() {
        // 7 groups instead of 8 — should not match.
        assert!(parse_recovery_key(
            "  abcdefgh-abcdefgh-abcdefgh-abcdefgh-abcdefgh-abcdefgh-abcdefgh"
        )
        .is_none());
    }

    #[test]
    fn parse_recovery_key_rejects_uppercase_letters() {
        // systemd-cryptenroll always emits lowercase; uppercase shouldn't match.
        assert!(parse_recovery_key(
            "  ABCDEFGH-abcdefgh-abcdefgh-abcdefgh-abcdefgh-abcdefgh-abcdefgh-abcdefgh"
        )
        .is_none());
    }

    #[test]
    fn parse_recovery_key_rejects_digits_in_groups() {
        // Groups must be lowercase letters only.
        assert!(parse_recovery_key(
            "  abcd1234-abcdefgh-abcdefgh-abcdefgh-abcdefgh-abcdefgh-abcdefgh-abcdefgh"
        )
        .is_none());
    }

    #[test]
    fn parse_recovery_key_does_not_match_wrong_word_length() {
        // 7-char words instead of 8.
        assert!(parse_recovery_key(
            "  abcdefg-abcdefg-abcdefg-abcdefg-abcdefg-abcdefg-abcdefg-abcdefg"
        )
        .is_none());
    }
}
