//! `ks run-background <unit>` — start a systemd user unit, intended for
//! Walker dispatch paths and keybinds that kick off a supervised background
//! task (e.g., `ks-update.service`) without opening a terminal.
//!
//! Thin wrapper around `systemctl --user start`. The unit name is restricted
//! to a `ks-<name>.service` allowlist so caller surfaces that accept
//! external input (Walker dispatch values, future keybinds, potentially
//! cron) cannot activate arbitrary user units. The consumer stays simple:
//! one binary invocation instead of reimplementing the systemctl spawn
//! plus error-surface translation per caller.

use anyhow::{anyhow, Context, Result};
use std::process::Command;

/// Validate that a unit name matches the `ks-<name>.service` shape this
/// verb is intended to start. Rejects anything outside the allowlist so
/// callers cannot trick the verb into starting arbitrary user units.
///
/// Allowed characters in `<name>`: lowercase ASCII, digits, hyphens.
/// These are the conventions keystone uses for its own service names
/// and are all safe under shell and systemd unit-name rules.
pub(crate) fn validate_unit_name(unit: &str) -> Result<()> {
    if !unit.ends_with(".service") {
        return Err(anyhow!("unit {unit:?} is not a .service unit"));
    }
    if !unit.starts_with("ks-") {
        return Err(anyhow!(
            "unit {unit:?} is not in the ks-<name>.service allowlist"
        ));
    }
    let stem = unit.trim_end_matches(".service").trim_start_matches("ks-");
    if stem.is_empty() {
        return Err(anyhow!("unit {unit:?} has an empty task name"));
    }
    if !stem
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
    {
        return Err(anyhow!(
            "unit {unit:?} contains characters outside the allowlist (lowercase ascii, digits, hyphens)"
        ));
    }
    Ok(())
}

pub fn execute(unit: &str) -> Result<()> {
    validate_unit_name(unit)?;

    let status = Command::new("systemctl")
        .args(["--user", "start", unit])
        .status()
        .with_context(|| format!("failed to invoke systemctl --user start {unit}"))?;

    if !status.success() {
        anyhow::bail!(
            "systemctl --user start {unit} exited with status {:?}",
            status.code()
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_canonical_keystone_unit_names() {
        validate_unit_name("ks-update.service").unwrap();
        validate_unit_name("ks-build.service").unwrap();
        validate_unit_name("ks-backup.service").unwrap();
        validate_unit_name("ks-photos-import.service").unwrap();
    }

    #[test]
    fn rejects_non_ks_prefixed_units() {
        let err = validate_unit_name("user-session.service").unwrap_err();
        assert!(err.to_string().contains("allowlist"), "got: {err}");
    }

    #[test]
    fn rejects_non_service_suffixes() {
        assert!(validate_unit_name("ks-update.timer").is_err());
        assert!(validate_unit_name("ks-update.socket").is_err());
        assert!(validate_unit_name("ks-update").is_err());
    }

    #[test]
    fn rejects_shell_metacharacters_and_uppercase() {
        // Each of these attempts to smuggle something past the systemd
        // spawn; the allowlist must reject all of them.
        assert!(validate_unit_name("ks-update.service; rm -rf /").is_err());
        assert!(validate_unit_name("ks-up date.service").is_err());
        assert!(validate_unit_name("ks-UPPER.service").is_err());
        assert!(validate_unit_name("ks-../other.service").is_err());
        assert!(validate_unit_name("ks-up$date.service").is_err());
    }

    #[test]
    fn rejects_empty_stem() {
        assert!(validate_unit_name("ks-.service").is_err());
    }
}
