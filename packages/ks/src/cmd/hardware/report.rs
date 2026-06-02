//! `ks hardware report` — render the [`HardwareReport`] from
//! [`super::probe`] in human-readable or JSON form.
//!
//! Pure (no IO): given a probed report, produces a `String`. The
//! IO-doing entry point [`execute`] is the CLI surface that ties
//! probing + rendering together, plus the optional
//! `--write-status-file` side effect used by the
//! `keystone-tpm-check` systemd service.

use std::fmt::Write as _;
use std::path::PathBuf;

use anyhow::{Context, Result};

use super::probe::{
    self, BootStage, Fido2Device, FingerprintState, HardwareReport, LuksVolume, MachineState,
    SecureBootState, Severity, SlotMap, SlotState, TpmDeviceState, VolumeRole, Warning,
    WarningScope,
};
use crate::cmd::{JsonError, JsonOutput};

/// Context in which the report is being rendered.
///
/// The probed *facts* don't depend on context — what changes is the
/// *hint text* attached to each finding. On the live installer, a
/// missing TPM enrollment isn't actionable yet ("install first");
/// post-install, the same fact yields a "run `ks hardware enroll tpm`"
/// hint.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Context_ {
    PreInstall,
    PostInstall,
}

/// Top-level CLI handler for `ks hardware report`.
pub async fn execute(
    json: bool,
    pre_install: bool,
    post_install: bool,
    write_status_file: Option<PathBuf>,
    disk_filter: Option<String>,
) -> Result<()> {
    let ctx = if pre_install {
        Context_::PreInstall
    } else if post_install {
        Context_::PostInstall
    } else {
        detect_context()
    };

    let unfiltered = probe::probe().await;

    // Status-file writing always uses the *unfiltered* report so the
    // systemd consumer (`components/security/tpm.rs::DiskUnlockStatus`)
    // sees the root volume's true enrollment state regardless of
    // whether the caller is currently focused on a different disk.
    // Filtering applies only to the human/JSON output below.
    if let Some(path) = write_status_file.as_ref() {
        write_status(&unfiltered, path)
            .await
            .with_context(|| format!("writing status file to {}", path.display()))?;
    }

    let mut report = unfiltered;
    if let Some(ref id) = disk_filter {
        apply_disk_filter(&mut report, id);
    }

    if json {
        let serialized = serde_json::to_string_pretty(&JsonOutput::ok(&report))?;
        println!("{}", serialized);
    } else {
        print!("{}", format_text(&report, ctx));
    }
    Ok(())
}

/// Top-level CLI handler with a fallback that emits a JSON error rather
/// than panicking when called via `--json` mode but the underlying
/// probe fails. (Reserved for future use — the current `probe::probe`
/// is infallible by design.)
#[allow(dead_code)]
pub fn json_error(err: &anyhow::Error) -> Result<()> {
    let serialized = serde_json::to_string_pretty(&JsonError::new(err.to_string()))?;
    println!("{}", serialized);
    Ok(())
}

/// Heuristic: a post-install system has the keystone activation marker;
/// the live installer does not.
fn detect_context() -> Context_ {
    if std::path::Path::new("/run/current-system/keystone-system-flake").exists() {
        Context_::PostInstall
    } else {
        Context_::PreInstall
    }
}

/// Compact, legacy-compatible status schema written by
/// `--write-status-file`. The shape matches what
/// `components/security/tpm.rs::DiskUnlockStatus` and the previous
/// inline `refresh-disk-unlock-status.sh` produced, so existing
/// consumers continue to work unchanged. The richer
/// [`HardwareReport`] is only available via stdout `--json`.
#[derive(Debug, serde::Serialize)]
struct LegacyStatus<'a> {
    checked_at: String,
    device: &'a str,
    tpm_enrolled: bool,
    fido2_enrolled: bool,
}

async fn write_status(report: &HardwareReport, path: &std::path::Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .with_context(|| format!("creating parent directory {}", parent.display()))?;
    }
    let root = report.volumes.iter().find(|v| v.id == "root");
    let default_device = probe::credstore_device();
    let device = root.map(|v| v.device.as_path()).unwrap_or(default_device);
    let body = serde_json::to_string_pretty(&LegacyStatus {
        checked_at: chrono::Utc::now().to_rfc3339(),
        device: device.to_str().unwrap_or(probe::ROOT_CREDSTORE),
        tpm_enrolled: root.map(|v| v.slots.tpm2.enrolled).unwrap_or(false),
        fido2_enrolled: root.map(|v| v.slots.fido2.enrolled).unwrap_or(false),
    })?;
    tokio::fs::write(path, body).await?;
    // World-readable 0644: the legacy refresh-disk-unlock-status.sh
    // chmod'd this explicitly so non-root consumers (ks doctor, the
    // first-boot wizard) can read it. Setting umask-independent
    // permissions here preserves that contract.
    set_world_readable(path).await?;
    Ok(())
}

#[cfg(unix)]
async fn set_world_readable(path: &std::path::Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let mut perms = tokio::fs::metadata(path).await?.permissions();
    perms.set_mode(0o644);
    tokio::fs::set_permissions(path, perms).await?;
    Ok(())
}

#[cfg(not(unix))]
async fn set_world_readable(_path: &std::path::Path) -> Result<()> {
    Ok(())
}

fn apply_disk_filter(report: &mut HardwareReport, id: &str) {
    report.volumes.retain(|v| v.id == id);
    // Warnings must follow the same filter: drop per-volume
    // findings that aren't for the focused disk, but keep all
    // machine-wide warnings (Secure Boot disabled, etc.).
    report.warnings.retain(|w| match &w.scope {
        probe::WarningScope::Machine => true,
        probe::WarningScope::Volume { id: warn_id } => warn_id == id,
    });
}

// ---------------------------------------------------------------------------
// Pure renderer
// ---------------------------------------------------------------------------

/// Render the report as a human-readable block. Pure — no IO, no probes.
pub fn format_text(report: &HardwareReport, ctx: Context_) -> String {
    let mut out = String::new();
    let _ = writeln!(out);
    format_machine(&mut out, &report.machine);
    format_volumes(&mut out, &report.volumes);
    format_warnings(&mut out, &report.warnings, ctx);
    out
}

fn format_machine(out: &mut String, m: &MachineState) {
    let _ = writeln!(out, "Machine");
    let _ = writeln!(
        out,
        "  Secure Boot:        {}",
        render_secure_boot(m.secure_boot)
    );
    let _ = writeln!(out, "  TPM2 device:        {}", render_tpm(m.tpm2));
    let _ = writeln!(
        out,
        "  FIDO2 devices:      {}",
        render_fido2_list(&m.fido2_devices)
    );
    let _ = writeln!(
        out,
        "  Fingerprint reader: {}",
        render_fingerprint(m.fingerprint)
    );
    let _ = writeln!(out);
}

fn render_secure_boot(s: SecureBootState) -> &'static str {
    match s {
        SecureBootState::Enrolled => "enrolled",
        SecureBootState::AuditMode => "Audit Mode (enforcement disabled)",
        SecureBootState::SetupMode => "Setup Mode (ready to enroll keys)",
        SecureBootState::Disabled => "⚠ DISABLED",
        SecureBootState::NotSupported => "not supported (non-UEFI)",
        SecureBootState::Unknown => "unknown",
    }
}

fn render_tpm(s: TpmDeviceState) -> &'static str {
    match s {
        TpmDeviceState::Present => "present (/dev/tpmrm0)",
        TpmDeviceState::Absent => "none detected",
    }
}

fn render_fido2_list(devs: &[Fido2Device]) -> String {
    if devs.is_empty() {
        "none plugged in".into()
    } else {
        devs.iter()
            .map(|d| format!("{} ({})", d.label, d.path))
            .collect::<Vec<_>>()
            .join(", ")
    }
}

fn render_fingerprint(s: FingerprintState) -> &'static str {
    match s {
        FingerprintState::Available => "available (fprintd running)",
        FingerprintState::HardwareOnly => "hardware present, fprintd not running",
        FingerprintState::NotDetected => "none detected",
    }
}

fn format_volumes(out: &mut String, volumes: &[LuksVolume]) {
    let _ = writeln!(out, "LUKS volumes ({} unlock targets):", volumes.len());
    if volumes.is_empty() {
        let _ = writeln!(
            out,
            "  (none discovered — keystone expects {} after install)",
            probe::ROOT_CREDSTORE
        );
        let _ = writeln!(out);
        return;
    }
    for v in volumes {
        format_volume(out, v);
    }
}

fn format_volume(out: &mut String, v: &LuksVolume) {
    let _ = writeln!(
        out,
        "  {:<14}  {}  [{}, {}]",
        v.id,
        v.device.display(),
        render_role(v.role),
        render_boot_stage(v.boot_stage),
    );
    let _ = writeln!(out, "    Holds: {}", v.holds);
    format_slots(out, &v.slots);
    let _ = writeln!(out);
}

fn render_role(r: VolumeRole) -> &'static str {
    match r {
        VolumeRole::Primary => "primary",
        VolumeRole::Secondary => "secondary",
        VolumeRole::Manual => "manual",
    }
}

fn render_boot_stage(s: BootStage) -> &'static str {
    match s {
        BootStage::Initrd => "opens in initrd",
        BootStage::AfterRoot => "opens after root",
        BootStage::OnDemand => "on-demand only",
    }
}

fn format_slots(out: &mut String, slots: &SlotMap) {
    format_slot_row(out, "password", &slots.password);
    format_slot_row(out, "recovery", &slots.recovery);
    format_slot_row(out, "tpm2", &slots.tpm2);
    format_slot_row(out, "fido2", &slots.fido2);
}

fn format_slot_row(out: &mut String, label: &str, state: &SlotState) {
    let mark = if state.enrolled {
        if state.is_default {
            "⚠"
        } else {
            "✓"
        }
    } else {
        "—"
    };
    let detail = state.detail.as_deref().unwrap_or("");
    let _ = writeln!(out, "    {:<10} {}  {}", label, mark, detail);
}

fn format_warnings(out: &mut String, warnings: &[Warning], ctx: Context_) {
    if warnings.is_empty() {
        let _ = writeln!(out, "Warnings: none");
        return;
    }
    let _ = writeln!(out, "Warnings:");
    for w in warnings {
        let sev = match w.severity {
            Severity::Critical => "✖",
            Severity::Warning => "⚠",
            Severity::Info => "ℹ",
        };
        let scope = match &w.scope {
            WarningScope::Machine => "[machine]".to_string(),
            WarningScope::Volume { id } => format!("[volume {}]", id),
        };
        let _ = writeln!(out, "  {} {} {}", sev, scope, w.message);
        if let Some(rem) = &w.remediation {
            let _ = writeln!(out, "      → {}", rewrite_remediation_for_context(rem, ctx));
        }
    }
}

/// Pre-install hints differ from post-install hints for the same fact:
/// e.g., "run `ks hardware enroll tpm`" doesn't apply when there's no
/// installed system to run it against. This swap is the only place
/// where [`Context_`] affects output.
fn rewrite_remediation_for_context(rem: &str, ctx: Context_) -> String {
    match ctx {
        Context_::PostInstall => rem.to_string(),
        Context_::PreInstall => {
            // The pre-install live ISO can't run enrollment yet —
            // remediation text that says "run `ks hardware enroll`"
            // gets reworded to the install-time equivalent.
            if rem.contains("ks hardware enroll") || rem.contains("ks hardware setup") {
                "After install, run `ks hardware setup` to enroll the encrypted root disk.".into()
            } else {
                rem.to_string()
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::probe::{
        BootStage, Fido2Device, FingerprintState, HardwareReport, LuksVolume, MachineState,
        SecureBootState, Severity, SlotMap, SlotState, TpmDeviceState, VolumeRole, Warning,
        WarningScope,
    };
    use super::*;
    use std::path::PathBuf;

    fn sample_report() -> HardwareReport {
        HardwareReport {
            machine: MachineState {
                secure_boot: SecureBootState::Disabled,
                tpm2: TpmDeviceState::Present,
                fido2_devices: vec![Fido2Device {
                    path: "/dev/hidraw0".into(),
                    label: "Yubico YubiKey OTP+FIDO+CCID".into(),
                }],
                fingerprint: FingerprintState::NotDetected,
            },
            volumes: vec![LuksVolume {
                id: "root".into(),
                device: PathBuf::from("/dev/zvol/rpool/credstore"),
                role: VolumeRole::Primary,
                boot_stage: BootStage::Initrd,
                holds: "rootfs encryption keys".into(),
                slots: SlotMap {
                    password: SlotState {
                        enrolled: true,
                        is_default: true,
                        detail: Some("DEFAULT — must be rotated".into()),
                    },
                    recovery: SlotState::default(),
                    tpm2: SlotState::default(),
                    fido2: SlotState::default(),
                },
            }],
            warnings: vec![
                Warning {
                    severity: Severity::Warning,
                    scope: WarningScope::Machine,
                    message: "Secure Boot is DISABLED.".into(),
                    remediation: Some(
                        "Run `ks hardware setup` to stage Secure Boot keys, then enable Secure Boot in firmware.".into(),
                    ),
                },
                Warning {
                    severity: Severity::Critical,
                    scope: WarningScope::Volume { id: "root".into() },
                    message: "Volume `root` still accepts the default installer password.".into(),
                    remediation: Some("Run `ks hardware enroll password --disk=root`.".into()),
                },
            ],
        }
    }

    #[test]
    fn post_install_rendering_includes_enroll_hint_verbatim() {
        let out = format_text(&sample_report(), Context_::PostInstall);
        assert!(out.contains("⚠ DISABLED"));
        assert!(out.contains("✖ [volume root]"));
        assert!(out.contains("ks hardware enroll password"));
    }

    #[test]
    fn pre_install_rendering_rewrites_enroll_hint_to_install_first() {
        let out = format_text(&sample_report(), Context_::PreInstall);
        assert!(out.contains("⚠ DISABLED"));
        assert!(out.contains("After install"));
        assert!(!out.contains("ks hardware enroll password"));
    }

    #[test]
    fn empty_volumes_renders_a_helpful_hint() {
        let mut r = sample_report();
        r.volumes.clear();
        r.warnings.clear();
        let out = format_text(&r, Context_::PostInstall);
        assert!(out.contains("(none discovered"));
        assert!(out.contains("Warnings: none"));
    }

    #[test]
    fn default_password_renders_warning_glyph() {
        let r = sample_report();
        let out = format_text(&r, Context_::PostInstall);
        // The default-password row should have the ⚠ glyph, not ✓ or —.
        let pw_line = out
            .lines()
            .find(|l| l.contains("password"))
            .expect("password row");
        assert!(pw_line.contains("⚠"), "expected ⚠ in {:?}", pw_line);
    }

    #[test]
    fn disk_filter_keeps_machine_and_matching_volume_warnings_only() {
        let mut r = sample_report();
        r.volumes.push(LuksVolume {
            id: "data".into(),
            device: PathBuf::from("/dev/disk/by-id/data"),
            role: VolumeRole::Secondary,
            boot_stage: BootStage::AfterRoot,
            holds: "bulk storage".into(),
            slots: SlotMap::default(),
        });
        r.warnings.push(Warning {
            severity: Severity::Info,
            scope: WarningScope::Volume { id: "data".into() },
            message: "Volume `data` is not enrolled with TPM2.".into(),
            remediation: Some("Run `ks hardware enroll tpm --disk=data`.".into()),
        });

        apply_disk_filter(&mut r, "root");

        assert_eq!(r.volumes.len(), 1);
        assert_eq!(r.volumes[0].id, "root");
        assert!(r
            .warnings
            .iter()
            .any(|w| matches!(w.scope, WarningScope::Machine)));
        assert!(r
            .warnings
            .iter()
            .any(|w| matches!(&w.scope, WarningScope::Volume { id } if id == "root")));
        assert!(!r
            .warnings
            .iter()
            .any(|w| matches!(&w.scope, WarningScope::Volume { id } if id == "data")));
    }
}
