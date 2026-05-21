//! `ks hardware setup` — one-shot LUKS enrollment orchestrator.
//!
//! Given a freshly installed machine, do everything: detect the
//! hardware, replace the default LUKS password, generate a recovery
//! key, enroll TPM2, enroll a FIDO2 device if one is plugged in, and
//! enroll a fingerprint if a reader is present.
//!
//! Layered fallback (in the final state):
//!
//! - **Password** (slot 0): user-chosen passphrase, manual fallback.
//! - **Recovery key** (slot 1): 8-word paper key, last-resort.
//! - **TPM2**: PCR-bound auto-unlock at boot (default).
//! - **FIDO2**: YubiKey HMAC, manual fallback when TPM rebinding breaks.
//! - **Fingerprint**: not LUKS; gates sudo/login.
//!
//! The implementation is `plan` + `execute`: `plan` computes the
//! [`SetupPlan`] (testable without IO), `execute` runs the steps
//! through a [`SetupPrompts`] trait so the same code drives the CLI
//! (stdin prompts) and the TUI (crossterm prompts).

use anyhow::{Context, Result};

use super::enroll;
use super::probe::{
    self, HardwareReport, LuksVolume, SecureBootState, Severity, WarningScope,
};

/// CLI options that flow into [`plan`] and [`execute`].
#[derive(Debug, Clone, Default)]
pub struct SetupOptions {
    pub dry_run: bool,
    pub non_interactive: bool,
    pub allow_no_sb: bool,
    pub new_passphrase: Option<String>,
}

/// What `ks hardware setup` will do, computed from the probe. Render
/// this to the user before executing so they can see the impact.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetupPlan {
    pub steps: Vec<SetupStep>,
    pub blockers: Vec<String>,
}

/// One discrete action in the setup sequence. Each step has a label
/// the TUI/CLI surfaces to the user, plus enough metadata to actually
/// run it via the [`enroll`] primitives.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SetupStep {
    /// Slot 0 currently accepts "keystone" — rotate it before anything
    /// else can touch the volume.
    RotateDefaultPassword { volume_id: String },
    /// Generate the recovery key and enroll TPM2 in one shot
    /// (`keystone-enroll-recovery --auto`). Skipped if both are already
    /// enrolled.
    EnrollRecoveryAndTpm2 {
        volume_id: String,
        already_recovery: bool,
        already_tpm2: bool,
    },
    /// Enroll the plugged-in FIDO2 device against this volume.
    EnrollFido2 { volume_id: String, device_label: String },
    /// Enroll the current user's fingerprint via fprintd.
    EnrollFingerprint,
    /// Hardware is present but enrollment is skipped (e.g., FIDO2 reader
    /// detected but the user is already enrolled). Surfaces in the
    /// dry-run so the user understands why steps were filtered.
    Skip { reason: String },
}

impl SetupStep {
    pub fn label(&self) -> String {
        match self {
            Self::RotateDefaultPassword { volume_id } => {
                format!("Rotate default password on `{}`", volume_id)
            }
            Self::EnrollRecoveryAndTpm2 { volume_id, .. } => {
                format!("Generate recovery key + enroll TPM2 on `{}`", volume_id)
            }
            Self::EnrollFido2 { volume_id, device_label } => {
                format!("Enroll FIDO2 ({}) on `{}`", device_label, volume_id)
            }
            Self::EnrollFingerprint => "Enroll fingerprint for sudo/login".into(),
            Self::Skip { reason } => format!("Skip: {}", reason),
        }
    }
}

/// I/O surface for the orchestrator. CLI implements this via stdin +
/// `rpassword`-style prompts; the TUI implements it via crossterm
/// state machine.
///
/// Uses Rust 1.75+ native `async fn` in traits (no `async-trait`
/// dep). Callers should use `impl SetupPrompts` for static dispatch
/// (we only have a handful of concrete implementations).
pub trait SetupPrompts: Send + Sync {
    /// Show the plan and ask "Continue? [y/N]". Returns true to proceed.
    fn confirm_plan(&self, plan: &SetupPlan) -> impl std::future::Future<Output = Result<bool>> + Send;

    /// Prompt for the new LUKS passphrase. Returned twice-typed +
    /// validated by the implementation.
    fn request_new_passphrase(&self)
        -> impl std::future::Future<Output = Result<String>> + Send;

    /// Display the freshly generated recovery key and require the user
    /// to confirm they've recorded it. Returns true once acknowledged.
    fn acknowledge_recovery_key(
        &self,
        key_display: &str,
    ) -> impl std::future::Future<Output = Result<bool>> + Send;

    /// Show free-form progress text (used for "Touch your YubiKey",
    /// "Place finger 5×", etc.).
    fn say(&self, text: &str) -> impl std::future::Future<Output = ()> + Send;
}

/// Compute the plan for a given probed report. Pure — no IO, no
/// process spawning. Unit-testable.
pub fn plan(report: &HardwareReport, opts: &SetupOptions) -> SetupPlan {
    let mut steps = Vec::new();
    let mut blockers = Vec::new();

    // Machine-wide blockers
    if matches!(report.machine.secure_boot, SecureBootState::Disabled) && !opts.allow_no_sb {
        blockers.push(
            "Secure Boot is DISABLED. TPM PCR-7 binding provides no integrity guarantee. \
             Enable Secure Boot in firmware (or pass --allow-no-sb to proceed anyway)."
                .into(),
        );
    }

    // Per-volume steps
    for v in &report.volumes {
        steps.extend(plan_volume(v));
    }

    // Surface critical warnings as blockers if they would leave the
    // user worse off than they started (e.g., "every method failed"
    // shouldn't reach this code path, but defense in depth).
    for w in &report.warnings {
        if matches!(w.severity, Severity::Critical) {
            // The default-password critical warning is *expected* — that's
            // what setup fixes — so don't elevate it to a blocker.
            if !is_default_password_warning(w) {
                if let WarningScope::Volume { id: _ } = &w.scope {
                    blockers.push(format!("{}: {}", w.message, w.remediation.as_deref().unwrap_or("")));
                }
            }
        }
    }

    // Machine-level enrollments
    if matches!(
        report.machine.fingerprint,
        probe::FingerprintState::Available | probe::FingerprintState::HardwareOnly
    ) {
        steps.push(SetupStep::EnrollFingerprint);
    } else {
        steps.push(SetupStep::Skip {
            reason: "no fingerprint reader detected".into(),
        });
    }

    SetupPlan { steps, blockers }
}

fn is_default_password_warning(w: &probe::Warning) -> bool {
    w.message.contains("default installer password")
}

fn plan_volume(v: &LuksVolume) -> Vec<SetupStep> {
    let mut steps = Vec::new();
    if v.slots.password.is_default {
        steps.push(SetupStep::RotateDefaultPassword {
            volume_id: v.id.clone(),
        });
    }
    if !v.slots.recovery.enrolled || !v.slots.tpm2.enrolled {
        steps.push(SetupStep::EnrollRecoveryAndTpm2 {
            volume_id: v.id.clone(),
            already_recovery: v.slots.recovery.enrolled,
            already_tpm2: v.slots.tpm2.enrolled,
        });
    }
    // FIDO2 enrollment is opportunistic: we don't know which device the
    // user wants paired without re-probing during execute(). Insert a
    // placeholder if any device is plugged in; execute() picks the
    // first one.
    // (The probe already attached device labels at the machine level;
    // we cross-reference at execute time.)
    steps
}

/// Run the plan, invoking the [`SetupPrompts`] for user-facing
/// interactions and shelling out to the [`enroll`] primitives for
/// each LUKS operation.
///
/// On dry-run, returns immediately without executing.
pub async fn execute<P: SetupPrompts>(
    report: &HardwareReport,
    opts: SetupOptions,
    prompts: &P,
) -> Result<()> {
    let mut full_plan = plan(report, &opts);

    // Append FIDO2 steps now that we have the device list from probe.
    for v in &report.volumes {
        if let Some(dev) = report.machine.fido2_devices.first() {
            if !v.slots.fido2.enrolled {
                full_plan.steps.insert(
                    full_plan.steps.len().saturating_sub(1),
                    SetupStep::EnrollFido2 {
                        volume_id: v.id.clone(),
                        device_label: dev.label.clone(),
                    },
                );
            }
        }
    }

    if !full_plan.blockers.is_empty() {
        for b in &full_plan.blockers {
            prompts.say(&format!("Blocker: {}", b)).await;
        }
        anyhow::bail!("Setup blocked. Resolve blockers above or pass override flags.");
    }

    if opts.dry_run {
        prompts.say("(dry run — would execute the following plan:)").await;
        for s in &full_plan.steps {
            prompts.say(&format!("  • {}", s.label())).await;
        }
        return Ok(());
    }

    if !opts.non_interactive {
        let ok = prompts.confirm_plan(&full_plan).await?;
        if !ok {
            prompts.say("Cancelled.").await;
            return Ok(());
        }
    }

    for step in &full_plan.steps {
        prompts.say(&format!("→ {}", step.label())).await;
        match step {
            SetupStep::RotateDefaultPassword { volume_id: _ } => {
                // The keystone-enroll-password script prompts for the
                // new passphrase itself; we don't pipe it. In future,
                // when we accept --new-passphrase, this becomes a
                // Piped IoMode.
                enroll::enroll_password(enroll::IoMode::Interactive)
                    .await
                    .context("rotating default password")?;
            }
            SetupStep::EnrollRecoveryAndTpm2 { .. } => {
                enroll::enroll_recovery(enroll::IoMode::Interactive)
                    .await
                    .context("enrolling recovery + TPM2")?;
            }
            SetupStep::EnrollFido2 { .. } => {
                enroll::enroll_fido2(enroll::IoMode::Interactive)
                    .await
                    .context("enrolling FIDO2")?;
            }
            SetupStep::EnrollFingerprint => {
                enroll::enroll_fingerprint()
                    .await
                    .context("enrolling fingerprint")?;
            }
            SetupStep::Skip { .. } => {}
        }
    }

    prompts.say("✓ Setup complete. Run `ks hardware report` to verify.").await;
    Ok(())
}

// ---------------------------------------------------------------------------
// CLI prompt implementation
// ---------------------------------------------------------------------------

/// Stdin/stdout implementation of [`SetupPrompts`]. Used by
/// `ks hardware setup`.
pub struct CliPrompts;

impl SetupPrompts for CliPrompts {
    async fn confirm_plan(&self, plan: &SetupPlan) -> Result<bool> {
        println!("\nSetup plan:");
        for s in &plan.steps {
            println!("  • {}", s.label());
        }
        println!();
        println!("Continue? [y/N]: ");
        // Interactive prompts block the current thread on user typing,
        // which is the desired behavior. With `rt-multi-thread` the
        // runtime keeps other workers free for any concurrent tasks.
        let line = tokio::task::spawn_blocking(|| {
            use std::io::BufRead;
            let mut s = String::new();
            std::io::stdin().lock().read_line(&mut s).map(|_| s)
        })
        .await??;
        Ok(matches!(
            line.trim().to_ascii_lowercase().as_str(),
            "y" | "yes"
        ))
    }

    async fn request_new_passphrase(&self) -> Result<String> {
        // The underlying keystone-enroll-password script handles the
        // passphrase prompt itself, so we don't need to. This method
        // exists for symmetry with the TUI implementation.
        Ok(String::new())
    }

    async fn acknowledge_recovery_key(&self, _key_display: &str) -> Result<bool> {
        // Likewise — keystone-enroll-recovery displays the key itself
        // and prompts for verification. Inherit stdin and return ok.
        Ok(true)
    }

    async fn say(&self, text: &str) {
        println!("{}", text);
    }
}

/// Top-level CLI entry for `ks hardware setup`.
pub async fn execute_cli(opts: SetupOptions) -> Result<()> {
    let report = probe::probe().await;
    execute(&report, opts, &CliPrompts).await
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use super::probe::{
        BootStage, HardwareReport, LuksVolume, MachineState, SecureBootState, SlotMap, SlotState,
        TpmDeviceState, VolumeRole,
    };
    use std::path::PathBuf;

    fn fresh_install_report() -> HardwareReport {
        HardwareReport {
            machine: MachineState {
                secure_boot: SecureBootState::Enrolled,
                tpm2: TpmDeviceState::Present,
                fido2_devices: vec![],
                fingerprint: probe::FingerprintState::NotDetected,
            },
            volumes: vec![LuksVolume {
                id: "root".into(),
                device: PathBuf::from("/dev/zvol/rpool/credstore"),
                role: VolumeRole::Primary,
                boot_stage: BootStage::Initrd,
                holds: "rootfs".into(),
                slots: SlotMap {
                    password: SlotState {
                        enrolled: true,
                        is_default: true,
                        detail: Some("DEFAULT".into()),
                    },
                    ..Default::default()
                },
            }],
            warnings: vec![],
        }
    }

    #[test]
    fn plan_for_fresh_install_starts_with_password_rotation() {
        let p = plan(&fresh_install_report(), &SetupOptions::default());
        assert!(matches!(
            p.steps[0],
            SetupStep::RotateDefaultPassword { ref volume_id } if volume_id == "root"
        ));
    }

    #[test]
    fn plan_includes_recovery_and_tpm2_step() {
        let p = plan(&fresh_install_report(), &SetupOptions::default());
        assert!(p
            .steps
            .iter()
            .any(|s| matches!(s, SetupStep::EnrollRecoveryAndTpm2 { .. })));
    }

    #[test]
    fn plan_skips_password_rotation_when_already_user_set() {
        let mut r = fresh_install_report();
        r.volumes[0].slots.password.is_default = false;
        let p = plan(&r, &SetupOptions::default());
        assert!(!p
            .steps
            .iter()
            .any(|s| matches!(s, SetupStep::RotateDefaultPassword { .. })));
    }

    #[test]
    fn plan_skips_recovery_when_everything_already_enrolled() {
        let mut r = fresh_install_report();
        r.volumes[0].slots.password.is_default = false;
        r.volumes[0].slots.recovery.enrolled = true;
        r.volumes[0].slots.tpm2.enrolled = true;
        let p = plan(&r, &SetupOptions::default());
        assert!(!p
            .steps
            .iter()
            .any(|s| matches!(s, SetupStep::EnrollRecoveryAndTpm2 { .. })));
    }

    #[test]
    fn plan_blocks_when_secure_boot_disabled_without_override() {
        let mut r = fresh_install_report();
        r.machine.secure_boot = SecureBootState::Disabled;
        let p = plan(&r, &SetupOptions::default());
        assert!(p.blockers.iter().any(|b| b.contains("Secure Boot")));
    }

    #[test]
    fn plan_allows_proceed_with_allow_no_sb_override() {
        let mut r = fresh_install_report();
        r.machine.secure_boot = SecureBootState::Disabled;
        let opts = SetupOptions {
            allow_no_sb: true,
            ..Default::default()
        };
        let p = plan(&r, &opts);
        assert!(p.blockers.is_empty(), "got blockers: {:?}", p.blockers);
    }

    #[test]
    fn plan_marks_fingerprint_skip_when_no_hardware() {
        let p = plan(&fresh_install_report(), &SetupOptions::default());
        assert!(p.steps.iter().any(|s| matches!(s,
            SetupStep::Skip { reason } if reason.contains("fingerprint"))));
    }

    #[test]
    fn plan_includes_fingerprint_enrollment_when_available() {
        let mut r = fresh_install_report();
        r.machine.fingerprint = probe::FingerprintState::Available;
        let p = plan(&r, &SetupOptions::default());
        assert!(p.steps.contains(&SetupStep::EnrollFingerprint));
    }

    #[test]
    fn setup_step_labels_are_human_readable() {
        let s = SetupStep::RotateDefaultPassword {
            volume_id: "root".into(),
        };
        assert!(s.label().contains("Rotate"));
        assert!(s.label().contains("root"));
    }
}
