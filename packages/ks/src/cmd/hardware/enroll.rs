//! Per-method LUKS enrollment primitives.
//!
//! Thin wrappers around the keystone-enroll-* shell scripts in
//! `modules/os/scripts/`. The scripts encode the systemd-cryptenroll
//! argv shape and the user-facing prompts; this module exists to give
//! Rust callers (the `ks hardware setup` orchestrator and the
//! `ks hardware enroll <method>` CLI) a single typed surface.
//!
//! Rewriting the scripts in Rust is tracked as a v1.2 refactor — the
//! shell layer is battle-tested at install time and changing it would
//! expand the scope of this RC beyond what the test matrix can cover.

use anyhow::{anyhow, bail, Result};
use tokio::process::Command;

use super::probe::Method;

/// How a wrapper should connect the spawned process to the user.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IoMode {
    /// Inherit stdin/stdout/stderr so the underlying script can prompt
    /// interactively (most enroll-* scripts do this).
    Interactive,
    /// Pipe stdin from a buffer; inherit stdout/stderr. Used by the
    /// non-interactive `ks hardware setup --non-interactive` path that
    /// pre-supplies a passphrase.
    Piped { stdin: Vec<u8> },
}

/// Top-level dispatch for `ks hardware enroll <method>` (and the
/// canonical `ks hardware disks <id> fde enroll <method>` form).
///
/// `disk` is currently always `root` since the v1.1 RC scope limits
/// enrollment to the canonical credstore zvol — see the plan's
/// "Not in scope" section. Non-root disks return a clear error.
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
        Method::Password => enroll_password(IoMode::Interactive).await,
        Method::Recovery => enroll_recovery(IoMode::Interactive).await,
        Method::Tpm2 => enroll_tpm2(IoMode::Interactive).await,
        Method::Fido2 => enroll_fido2(IoMode::Interactive).await,
        Method::Fingerprint => enroll_fingerprint().await,
    }
}

/// Replace the LUKS slot 0 passphrase. Delegates to
/// `keystone-enroll-password`, which prompts for the new passphrase
/// and runs `systemd-cryptenroll --password` underneath.
pub async fn enroll_password(io: IoMode) -> Result<()> {
    run_script("keystone-enroll-password", &["--auto"], io).await
}

/// Generate a recovery key and enroll TPM2 in one shot.
///
/// `keystone-enroll-recovery --auto` performs two systemd-cryptenroll
/// operations: (1) `--recovery-key` against slot 1, and (2)
/// `--tpm2-device=auto` against a TPM token. As of this RC, the
/// script no longer wipes slot 0 — the password is preserved as a
/// manual fallback (see `modules/os/scripts/enroll-recovery.sh` and
/// the layered-fallback design in the plan).
pub async fn enroll_recovery(io: IoMode) -> Result<()> {
    run_script("keystone-enroll-recovery", &["--auto"], io).await
}

/// Enroll TPM2 only (no recovery key generation). Used for re-binding
/// after PCR drift via `ks hardware rotate tpm2`.
pub async fn enroll_tpm2(io: IoMode) -> Result<()> {
    run_script("keystone-enroll-tpm", &["--auto"], io).await
}

/// Enroll a FIDO2 device (typically a YubiKey). Requires the device
/// to be plugged in and the user to touch it when prompted.
pub async fn enroll_fido2(io: IoMode) -> Result<()> {
    run_script("keystone-enroll-fido2", &[], io).await
}

/// Enroll a fingerprint for sudo/login (not for LUKS unlock). Shells
/// out to `fprintd-enroll` against the current user's right index
/// finger. Five swipes required; the binary handles the prompts.
pub async fn enroll_fingerprint() -> Result<()> {
    let status = Command::new("fprintd-enroll")
        .status()
        .await
        .map_err(|e| anyhow!("failed to spawn fprintd-enroll: {}", e))?;
    if !status.success() {
        bail!("fprintd-enroll exited with {}", status);
    }
    Ok(())
}

async fn run_script(name: &str, args: &[&str], io: IoMode) -> Result<()> {
    if crate::cmd::util::find_executable(name).is_none() {
        bail!(
            "{} not found on PATH. Are we running on a keystone-installed system?",
            name
        );
    }

    // The keystone-enroll-* scripts require root for cryptsetup +
    // systemd-cryptenroll. If we're not already root, prepend sudo —
    // the user sees a prompt and the rest runs unchanged.
    let need_sudo = !is_root();
    let (program, full_args): (&str, Vec<&str>) = if need_sudo {
        let mut v: Vec<&str> = vec![name];
        v.extend_from_slice(args);
        ("sudo", v)
    } else {
        (name, args.to_vec())
    };

    let mut cmd = Command::new(program);
    cmd.args(&full_args);

    match io {
        IoMode::Interactive => {
            let status = cmd
                .status()
                .await
                .map_err(|e| anyhow!("failed to spawn {}: {}", name, e))?;
            if !status.success() {
                bail!("{} exited with {}", name, status);
            }
        }
        IoMode::Piped { stdin } => {
            use tokio::io::AsyncWriteExt;
            cmd.stdin(std::process::Stdio::piped());
            let mut child = cmd
                .spawn()
                .map_err(|e| anyhow!("failed to spawn {}: {}", name, e))?;
            if let Some(handle) = child.stdin.as_mut() {
                handle.write_all(&stdin).await?;
                handle.shutdown().await?;
            }
            let status = child.wait().await?;
            if !status.success() {
                bail!("{} exited with {}", name, status);
            }
        }
    }
    Ok(())
}

fn is_root() -> bool {
    // SAFETY: getuid is async-signal-safe and always succeeds.
    unsafe { libc::getuid() == 0 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn enroll_on_non_root_volume_refuses_in_v1_1() {
        let err = execute(Method::Tpm2, Some("tank".into())).await.unwrap_err();
        let msg = format!("{}", err);
        assert!(msg.contains("non-root LUKS volumes"), "got: {}", msg);
        assert!(msg.contains("tank"));
    }

    #[tokio::test]
    async fn fingerprint_does_not_check_disk_target() {
        // Fingerprint is machine-level; passing --disk should be ignored
        // for the purpose of the LUKS guard (the call itself will fail
        // here because fprintd-enroll isn't on PATH in the test env,
        // but the rejection happens at the fprintd-enroll spawn, not
        // at the disk-guard layer).
        let result = execute(Method::Fingerprint, Some("tank".into())).await;
        // Either succeeded (very unlikely in test env) or failed at
        // the fprintd-enroll spawn level — not at the disk guard.
        match result {
            Ok(_) => {}
            Err(e) => {
                let msg = format!("{}", e);
                assert!(
                    !msg.contains("non-root LUKS volumes"),
                    "fingerprint should bypass the LUKS-only disk guard, got: {}",
                    msg
                );
            }
        }
    }
}
