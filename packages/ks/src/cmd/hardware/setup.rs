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
use super::probe::{self, HardwareReport, LuksVolume, SecureBootState, Severity, WarningScope};

/// CLI options that flow into [`plan`] and [`execute`].
#[derive(Debug, Clone, Default)]
pub struct SetupOptions {
    pub dry_run: bool,
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
    /// Generate the recovery key and enroll TPM2 in one shot via
    /// [`enroll::enroll_recovery`]. Skipped if both are already
    /// enrolled.
    EnrollRecoveryAndTpm2 {
        volume_id: String,
        already_recovery: bool,
        already_tpm2: bool,
    },
    /// Enroll the plugged-in FIDO2 device against this volume.
    EnrollFido2 {
        volume_id: String,
        device_label: String,
    },
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
            Self::EnrollFido2 {
                volume_id,
                device_label,
            } => {
                format!("Enroll FIDO2 ({}) on `{}`", device_label, volume_id)
            }
            Self::EnrollFingerprint => "Enroll fingerprint for sudo/login".into(),
            Self::Skip { reason } => format!("Skip: {}", reason),
        }
    }
}

/// I/O surface for the orchestrator. CLI implements this via stdin;
/// the TUI implements it via crossterm state machine.
///
/// Currently exposes only `confirm_plan` and `say` — passphrase entry
/// and recovery-key acknowledgment happen inside the per-method
/// primitives in [`enroll`] (which use `rpassword` directly and the
/// terminal stdout for the recovery key display). The TUI integration
/// will reintroduce passphrase + recovery-key methods on this trait
/// when it needs to drive those prompts through ratatui instead of
/// the per-method stdin/stdout path.
///
/// Uses Rust 1.75+ native `async fn` in traits (no `async-trait`
/// dep). Callers should use `impl SetupPrompts` for static dispatch.
pub trait SetupPrompts: Send + Sync {
    /// Show the plan and ask "Continue? [y/N]". Returns true to proceed.
    fn confirm_plan(
        &self,
        plan: &SetupPlan,
    ) -> impl std::future::Future<Output = Result<bool>> + Send;

    /// Show free-form progress text (used for "Touch your YubiKey",
    /// "Place finger 5×", etc.).
    fn say(&self, text: &str) -> impl std::future::Future<Output = ()> + Send;
}

/// v1.1 RC limits enrollment to the canonical `root` volume; bail
/// loudly if the planner ever produced a step against a different
/// target. Multi-volume support is tracked as a v1.2 follow-up.
fn require_root_volume(volume_id: &str) -> Result<()> {
    if volume_id != "root" {
        anyhow::bail!(
            "setup tried to enroll on non-root volume `{}`; v1.1 only supports root",
            volume_id
        );
    }
    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EnrollmentAction {
    RotatePassword,
    EnrollRecoveryAndTpm2,
    EnrollTpm2Only,
    EnrollFido2,
    EnrollFingerprint,
}

fn action_for_step(step: &SetupStep) -> Result<Option<EnrollmentAction>> {
    match step {
        SetupStep::RotateDefaultPassword { volume_id } => {
            require_root_volume(volume_id)?;
            Ok(Some(EnrollmentAction::RotatePassword))
        }
        SetupStep::EnrollRecoveryAndTpm2 {
            volume_id,
            already_recovery,
            already_tpm2: _,
        } => {
            require_root_volume(volume_id)?;
            if *already_recovery {
                Ok(Some(EnrollmentAction::EnrollTpm2Only))
            } else {
                Ok(Some(EnrollmentAction::EnrollRecoveryAndTpm2))
            }
        }
        SetupStep::EnrollFido2 { volume_id, .. } => {
            require_root_volume(volume_id)?;
            Ok(Some(EnrollmentAction::EnrollFido2))
        }
        SetupStep::EnrollFingerprint => Ok(Some(EnrollmentAction::EnrollFingerprint)),
        SetupStep::Skip { .. } => Ok(None),
    }
}

/// Compute the plan for a given probed report. Pure — no IO, no
/// process spawning. Unit-testable.
pub fn plan(report: &HardwareReport, _opts: &SetupOptions) -> SetupPlan {
    let mut steps = Vec::new();
    let mut blockers = Vec::new();

    // Machine-wide blockers
    if !matches!(report.machine.secure_boot, SecureBootState::Enrolled) {
        blockers.push(format!(
            "Secure Boot is not enrolled (current state: {:?}). \
             TPM PCR-7 binding provides no integrity guarantee unless Secure Boot is \
             active with enrolled keys. Enroll Secure Boot keys in firmware before \
             running `ks hardware setup`.",
            report.machine.secure_boot
        ));
    }

    // Per-volume steps. TPM and FIDO2 enrollment depend on the
    // machine having those credentials available; password rotation
    // does not. We pass machine-level state in so the planner can
    // skip TPM steps on TPM-less hosts instead of generating a plan
    // that will fail at execute time.
    let tpm_available = matches!(report.machine.tpm2, probe::TpmDeviceState::Present);
    for v in &report.volumes {
        steps.extend(plan_volume(v, &report.machine.fido2_devices, tpm_available));
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
                    blockers.push(format!(
                        "{}: {}",
                        w.message,
                        w.remediation.as_deref().unwrap_or("")
                    ));
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

fn plan_volume(
    v: &LuksVolume,
    fido2_devices: &[probe::Fido2Device],
    tpm_available: bool,
) -> Vec<SetupStep> {
    let mut steps = Vec::new();
    if v.slots.password.is_default {
        steps.push(SetupStep::RotateDefaultPassword {
            volume_id: v.id.clone(),
        });
    }
    // EnrollRecoveryAndTpm2 covers both the recovery key slot and the
    // TPM2 token in one systemd-cryptenroll invocation pair. If TPM2
    // isn't available, skip the whole step with an explicit reason
    // so the user sees why it's missing in the dry-run.
    if !v.slots.recovery.enrolled || !v.slots.tpm2.enrolled {
        if tpm_available {
            steps.push(SetupStep::EnrollRecoveryAndTpm2 {
                volume_id: v.id.clone(),
                already_recovery: v.slots.recovery.enrolled,
                already_tpm2: v.slots.tpm2.enrolled,
            });
        } else {
            steps.push(SetupStep::Skip {
                reason: format!(
                    "no TPM2 device on this host — skipping recovery+TPM2 on `{}`",
                    v.id
                ),
            });
        }
    }
    // Opportunistic FIDO2 enrollment: if a device is plugged in *now*
    // and this volume doesn't already have a FIDO2 token, pair the
    // first detected device. Re-running setup later with the device
    // unplugged will skip this step automatically.
    if !v.slots.fido2.enrolled {
        if let Some(dev) = fido2_devices.first() {
            steps.push(SetupStep::EnrollFido2 {
                volume_id: v.id.clone(),
                device_label: dev.label.clone(),
            });
        }
    }
    steps
}

/// Run the plan, invoking the [`SetupPrompts`] for user-facing
/// interactions and shelling out to the [`enroll`] primitives for
/// each LUKS operation.
///
/// On dry-run, returns immediately without executing.
///
/// The orchestrator's apparent complexity is sequential: it walks
/// the [`SetupPlan`] one step at a time. Splitting each step into a
/// separate function would just trade structural complexity for
/// indirection without making the flow clearer.
#[allow(clippy::cognitive_complexity)]
pub async fn execute<P: SetupPrompts>(
    report: &HardwareReport,
    opts: SetupOptions,
    prompts: &P,
) -> Result<()> {
    let full_plan = plan(report, &opts);

    if !full_plan.blockers.is_empty() {
        for b in &full_plan.blockers {
            prompts.say(&format!("Blocker: {}", b)).await;
        }
        anyhow::bail!("Setup blocked. Resolve blockers above and re-run.");
    }

    if opts.dry_run {
        prompts
            .say("(dry run — would execute the following plan:)")
            .await;
        for s in &full_plan.steps {
            prompts.say(&format!("  • {}", s.label())).await;
        }
        return Ok(());
    }

    let ok = prompts.confirm_plan(&full_plan).await?;
    if !ok {
        prompts.say("Cancelled.").await;
        return Ok(());
    }

    for step in &full_plan.steps {
        prompts.say(&format!("→ {}", step.label())).await;
        match action_for_step(step)? {
            Some(EnrollmentAction::RotatePassword) => {
                enroll::enroll_password()
                    .await
                    .context("rotating default password")?;
            }
            Some(EnrollmentAction::EnrollRecoveryAndTpm2) => {
                enroll::enroll_recovery()
                    .await
                    .context("enrolling recovery + TPM2")?;
            }
            Some(EnrollmentAction::EnrollTpm2Only) => {
                // If the recovery key is already enrolled but TPM2 is
                // missing, don't run the full enroll_recovery (which
                // would generate a *new* recovery key and overwrite
                // the user's existing one). Fall back to the
                // standalone TPM2 enrollment instead.
                enroll::enroll_tpm()
                    .await
                    .context("enrolling TPM2 (recovery already present)")?;
            }
            Some(EnrollmentAction::EnrollFingerprint) => {
                // Fingerprint enrollment is best-effort: fprintd may be
                // enabled by default even on systems without a reader, so a
                // failure here should not abort the whole setup chain.
                if let Err(e) = enroll::enroll_fingerprint().await {
                    prompts
                        .say(&format!(
                            "⚠ Fingerprint enrollment skipped ({}); continuing setup.",
                            e
                        ))
                        .await;
                }
            }
            Some(EnrollmentAction::EnrollFido2) => {
                enroll::enroll_fido2().await.context("enrolling FIDO2")?;
            }
            None => {}
        }
    }

    prompts
        .say("✓ Setup complete. Run `ks hardware report` to verify.")
        .await;
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
    use super::probe::{
        BootStage, HardwareReport, LuksVolume, MachineState, SecureBootState, SlotMap, SlotState,
        TpmDeviceState, VolumeRole,
    };
    use super::*;
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
    fn plan_blocks_when_secure_boot_disabled() {
        let mut r = fresh_install_report();
        r.machine.secure_boot = SecureBootState::Disabled;
        let p = plan(&r, &SetupOptions::default());
        assert!(p.blockers.iter().any(|b| b.contains("Secure Boot")));
    }

    #[test]
    fn plan_blocks_when_secure_boot_setup_mode() {
        let mut r = fresh_install_report();
        r.machine.secure_boot = SecureBootState::SetupMode;
        let p = plan(&r, &SetupOptions::default());
        assert!(p.blockers.iter().any(|b| b.contains("Secure Boot")));
    }

    #[test]
    fn plan_blocks_when_secure_boot_unknown() {
        let mut r = fresh_install_report();
        r.machine.secure_boot = SecureBootState::Unknown;
        let p = plan(&r, &SetupOptions::default());
        assert!(p.blockers.iter().any(|b| b.contains("Secure Boot")));
    }

    #[test]
    fn plan_does_not_block_when_secure_boot_enrolled() {
        // Verify the happy path: Enrolled does NOT trigger the blocker.
        let r = fresh_install_report(); // uses SecureBootState::Enrolled
        let p = plan(&r, &SetupOptions::default());
        assert!(p.blockers.is_empty());
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

    #[test]
    fn action_for_step_preserves_existing_recovery_key() {
        let step = SetupStep::EnrollRecoveryAndTpm2 {
            volume_id: "root".into(),
            already_recovery: true,
            already_tpm2: false,
        };
        assert_eq!(
            action_for_step(&step).expect("valid step"),
            Some(EnrollmentAction::EnrollTpm2Only)
        );
    }

    #[test]
    fn action_for_step_uses_full_recovery_flow_when_recovery_missing() {
        let step = SetupStep::EnrollRecoveryAndTpm2 {
            volume_id: "root".into(),
            already_recovery: false,
            already_tpm2: false,
        };
        assert_eq!(
            action_for_step(&step).expect("valid step"),
            Some(EnrollmentAction::EnrollRecoveryAndTpm2)
        );
    }
}
