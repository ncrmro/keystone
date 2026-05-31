//! `ks hardware setup` — one-shot LUKS enrollment orchestrator.
//!
//! Given a freshly installed machine, do everything: detect the
//! hardware, enroll a strong human fallback, enroll TPM2, replace the
//! default LUKS password, enroll a FIDO2 device if one is plugged in, and
//! enroll a fingerprint if a reader is present.
//!
//! Layered fallback (in the final state):
//!
//! - **FIDO2**: YubiKey HMAC, preferred human fallback when present.
//! - **Recovery key** (slot 1): 8-word paper key, high-entropy fallback.
//! - **Password** (slot 0): user-chosen passphrase, manual fallback.
//! - **TPM2**: PCR-bound auto-unlock at boot (default ergonomic path).
//! - **Fingerprint**: not LUKS; gates sudo/login.
//!
//! The implementation is `plan` + `execute`: `plan` computes the
//! [`SetupPlan`] (testable without IO), `execute` runs the steps
//! through a [`SetupPrompts`] trait so the same code drives the CLI
//! (stdin prompts) and the TUI (crossterm prompts).

use anyhow::{Context, Result};

use super::enroll;
use super::probe::{self, HardwareReport, LuksVolume, SecureBootState, Severity, WarningScope};
use crate::components::security::secure_boot;

/// CLI options that flow into [`plan`] and [`execute`].
#[derive(Debug, Clone, Default)]
pub struct SetupOptions {
    pub dry_run: bool,
    pub secure_boot_status: Option<secure_boot::Status>,
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
    /// Generate Keystone Secure Boot keys in the installed system so a later
    /// firmware enrollment can happen without shelling out to `sbctl`
    /// manually.
    PrepareSecureBootKeys,
    /// Enroll Secure Boot keys while the firmware is in Setup Mode. This is
    /// the behind-the-scenes `sbctl` step that lets TPM setup continue after
    /// the next boot.
    EnrollSecureBootKeys,
    /// The setup flow has done all it can from Linux userspace and now needs
    /// the user to change firmware state before continuing.
    PauseForSecureBoot { reason: String },
    /// Secure Boot enrollment has been staged and a reboot is now required
    /// before TPM-bound unlock can continue.
    RebootAndResume { reason: String },
    /// Slot 0 currently accepts "keystone" — rotate it after stronger
    /// fallback methods are available.
    RotateDefaultPassword { volume_id: String },
    /// Enroll the plugged-in FIDO2 device against this volume.
    EnrollFido2 {
        volume_id: String,
        device_label: String,
    },
    /// Generate a paper recovery key for this volume.
    EnrollRecoveryKey { volume_id: String },
    /// Enroll TPM2 automatic unlock against this volume.
    EnrollTpm2 { volume_id: String },
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
            Self::PrepareSecureBootKeys => "Generate Secure Boot keys".into(),
            Self::EnrollSecureBootKeys => "Enroll Secure Boot keys".into(),
            Self::PauseForSecureBoot { reason } => {
                format!("Pause for firmware action: {}", reason)
            }
            Self::RebootAndResume { reason } => format!("Reboot and re-run setup: {}", reason),
            Self::RotateDefaultPassword { volume_id } => {
                format!("Rotate default password on `{}`", volume_id)
            }
            Self::EnrollFido2 {
                volume_id,
                device_label,
            } => {
                format!(
                    "Enroll FIDO2 hardware key ({}) on `{}`",
                    device_label, volume_id
                )
            }
            Self::EnrollRecoveryKey { volume_id } => {
                format!("Generate recovery key for `{}`", volume_id)
            }
            Self::EnrollTpm2 { volume_id } => {
                format!("Enroll TPM2 automatic unlock on `{}`", volume_id)
            }
            Self::EnrollFingerprint => "Enroll fingerprint for login/sudo".into(),
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
    ProvisionSecureBoot,
    RotatePassword,
    EnrollFido2,
    EnrollRecoveryKey,
    EnrollTpm2,
    EnrollFingerprint,
}

fn action_for_step(step: &SetupStep) -> Result<Option<EnrollmentAction>> {
    match step {
        SetupStep::PrepareSecureBootKeys | SetupStep::EnrollSecureBootKeys => {
            Ok(Some(EnrollmentAction::ProvisionSecureBoot))
        }
        SetupStep::PauseForSecureBoot { .. } | SetupStep::RebootAndResume { .. } => Ok(None),
        SetupStep::RotateDefaultPassword { volume_id } => {
            require_root_volume(volume_id)?;
            Ok(Some(EnrollmentAction::RotatePassword))
        }
        SetupStep::EnrollFido2 { volume_id, .. } => {
            require_root_volume(volume_id)?;
            Ok(Some(EnrollmentAction::EnrollFido2))
        }
        SetupStep::EnrollRecoveryKey { volume_id } => {
            require_root_volume(volume_id)?;
            Ok(Some(EnrollmentAction::EnrollRecoveryKey))
        }
        SetupStep::EnrollTpm2 { volume_id } => {
            require_root_volume(volume_id)?;
            Ok(Some(EnrollmentAction::EnrollTpm2))
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

    steps.extend(plan_secure_boot(
        report.machine.secure_boot,
        _opts.secure_boot_status.clone(),
    ));

    if matches!(
        report.machine.secure_boot,
        SecureBootState::NotSupported | SecureBootState::Unknown
    ) {
        blockers.push(format!(
            "Secure Boot is unavailable for `ks hardware setup` (current state: {:?}). \
             TPM PCR-7 binding requires a visible UEFI Secure Boot state. Resolve the \
             firmware issue or use the per-method enrollment commands instead.",
            report.machine.secure_boot
        ));
    }

    // Per-volume steps. Establish a durable human fallback before TPM
    // auto-unlock, then rotate the default installer password.
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

fn plan_secure_boot(
    state: SecureBootState,
    sb_status: Option<secure_boot::Status>,
) -> Vec<SetupStep> {
    use secure_boot::Status as SbStatus;

    let mut steps = Vec::new();
    match state {
        SecureBootState::Enrolled => {}
        SecureBootState::SetupMode => {
            steps.push(SetupStep::EnrollSecureBootKeys);
            steps.push(SetupStep::RebootAndResume {
                reason: "Secure Boot keys will be active after reboot. Re-run `ks hardware setup` to continue TPM enrollment.".into(),
            });
        }
        SecureBootState::Disabled => match sb_status.unwrap_or(SbStatus::Unknown) {
            SbStatus::SetupMode => {
                steps.push(SetupStep::EnrollSecureBootKeys);
                steps.push(SetupStep::RebootAndResume {
                    reason: "Secure Boot keys were enrolled in Setup Mode. Reboot, enable Secure Boot if your firmware leaves it off, and re-run `ks hardware setup`.".into(),
                });
            }
            SbStatus::KeysGenerated => {
                steps.push(SetupStep::PauseForSecureBoot {
                    reason: "Secure Boot keys already exist. Reboot into firmware, enable Secure Boot or Setup Mode, then re-run `ks hardware setup`.".into(),
                });
            }
            SbStatus::Enrolled => {
                steps.push(SetupStep::RebootAndResume {
                    reason: "Secure Boot keys are already staged. Reboot and re-run `ks hardware setup` if the firmware has not picked them up yet.".into(),
                });
            }
            SbStatus::NotInSetupMode | SbStatus::Unknown => {
                steps.push(SetupStep::PrepareSecureBootKeys);
                steps.push(SetupStep::PauseForSecureBoot {
                    reason: "Enter firmware, enable Secure Boot or Setup Mode, then re-run `ks hardware setup` to enroll the generated keys and continue TPM enrollment.".into(),
                });
            }
        },
        SecureBootState::NotSupported | SecureBootState::Unknown => {}
    }
    steps
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
    let mut strong_fallback_planned = false;

    if !v.slots.fido2.enrolled {
        if let Some(dev) = fido2_devices.first() {
            steps.push(SetupStep::EnrollFido2 {
                volume_id: v.id.clone(),
                device_label: dev.label.clone(),
            });
            strong_fallback_planned = true;
        }
    }

    let strong_fallback_exists = v.slots.fido2.enrolled || v.slots.recovery.enrolled;
    if !strong_fallback_exists && !strong_fallback_planned {
        steps.push(SetupStep::EnrollRecoveryKey {
            volume_id: v.id.clone(),
        });
        strong_fallback_planned = true;
    }

    if !v.slots.tpm2.enrolled {
        if tpm_available && (strong_fallback_exists || strong_fallback_planned) {
            steps.push(SetupStep::EnrollTpm2 {
                volume_id: v.id.clone(),
            });
        } else if tpm_available {
            steps.push(SetupStep::Skip {
                reason: format!(
                    "TPM2 automatic unlock on `{}` needs a FIDO2 or recovery fallback first",
                    v.id
                ),
            });
        } else {
            steps.push(SetupStep::Skip {
                reason: format!(
                    "no TPM2 device on this host — skipping TPM2 automatic unlock on `{}`",
                    v.id
                ),
            });
        }
    }

    if v.slots.password.is_default {
        steps.push(SetupStep::RotateDefaultPassword {
            volume_id: v.id.clone(),
        });
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
        for line in setup_model_lines() {
            prompts.say(line).await;
        }
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
        if let SetupStep::PauseForSecureBoot { reason } = step {
            prompts.say(reason).await;
            prompts
                .say("Secure Boot work paused. Re-run `ks hardware setup` after the firmware change.")
                .await;
            return Ok(());
        }
        if let SetupStep::RebootAndResume { reason } = step {
            prompts.say(reason).await;
            prompts
                .say("Secure Boot work staged. Reboot now, then re-run `ks hardware setup` to continue.")
                .await;
            return Ok(());
        }
        match action_for_step(step)? {
            Some(EnrollmentAction::ProvisionSecureBoot) => {
                let result = secure_boot::provision()
                    .await
                    .context("provisioning Secure Boot")?;
                if !result.trim().is_empty() {
                    prompts.say(&result).await;
                }
            }
            Some(EnrollmentAction::RotatePassword) => {
                enroll::enroll_password()
                    .await
                    .context("rotating default password")?;
            }
            Some(EnrollmentAction::EnrollRecoveryKey) => {
                enroll::enroll_recovery_key()
                    .await
                    .context("enrolling recovery key")?;
            }
            Some(EnrollmentAction::EnrollTpm2) => {
                enroll::enroll_tpm()
                    .await
                    .context("enrolling TPM2 automatic unlock")?;
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
        for line in setup_model_lines() {
            println!("{}", line);
        }
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

fn setup_model_lines() -> &'static [&'static str] {
    &[
        "Unlock model:",
        "  FIDO2/YubiKey is the preferred human fallback when present.",
        "  Recovery keys are high-entropy and reliable, but hard to type and store.",
        "  Passwords are manual fallback; use a host-unique passphrase, not your login password.",
        "  TPM2 provides automatic full-disk unlock after Secure Boot is active.",
        "  Fingerprints are for login/sudo convenience, not disk unlock.",
        "",
    ]
}

/// Top-level CLI entry for `ks hardware setup`.
pub async fn execute_cli(opts: SetupOptions) -> Result<()> {
    let report = probe::probe().await;
    let secure_boot_status = if matches!(report.machine.secure_boot, SecureBootState::Enrolled) {
        opts.secure_boot_status.clone()
    } else {
        Some(secure_boot::check_status().await)
    };
    execute(
        &report,
        SetupOptions {
            secure_boot_status,
            ..opts
        },
        &CliPrompts,
    )
    .await
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::probe::{
        BootStage, Fido2Device, HardwareReport, LuksVolume, MachineState, SecureBootState, SlotMap,
        SlotState, TpmDeviceState, VolumeRole,
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
    fn plan_for_fresh_install_starts_with_recovery_fallback() {
        let p = plan(&fresh_install_report(), &SetupOptions::default());
        assert!(matches!(
            p.steps[0],
            SetupStep::EnrollRecoveryKey { ref volume_id } if volume_id == "root"
        ));
    }

    #[test]
    fn plan_includes_tpm2_after_recovery() {
        let p = plan(&fresh_install_report(), &SetupOptions::default());
        let recovery = p
            .steps
            .iter()
            .position(|s| matches!(s, SetupStep::EnrollRecoveryKey { .. }))
            .expect("recovery step");
        let tpm = p
            .steps
            .iter()
            .position(|s| matches!(s, SetupStep::EnrollTpm2 { .. }))
            .expect("TPM2 step");
        assert!(recovery < tpm);
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
    fn plan_skips_recovery_and_tpm_when_everything_already_enrolled() {
        let mut r = fresh_install_report();
        r.volumes[0].slots.password.is_default = false;
        r.volumes[0].slots.recovery.enrolled = true;
        r.volumes[0].slots.tpm2.enrolled = true;
        let p = plan(&r, &SetupOptions::default());
        assert!(!p
            .steps
            .iter()
            .any(|s| matches!(s, SetupStep::EnrollRecoveryKey { .. })));
        assert!(!p
            .steps
            .iter()
            .any(|s| matches!(s, SetupStep::EnrollTpm2 { .. })));
    }

    #[test]
    fn plan_blocks_when_secure_boot_disabled() {
        let mut r = fresh_install_report();
        r.machine.secure_boot = SecureBootState::Disabled;
        let p = plan(
            &r,
            &SetupOptions {
                secure_boot_status: Some(secure_boot::Status::Unknown),
                ..SetupOptions::default()
            },
        );
        assert!(p.steps.contains(&SetupStep::PrepareSecureBootKeys));
        assert!(p
            .steps
            .iter()
            .any(|s| matches!(s, SetupStep::PauseForSecureBoot { .. })));
    }

    #[test]
    fn plan_blocks_when_secure_boot_setup_mode() {
        let mut r = fresh_install_report();
        r.machine.secure_boot = SecureBootState::SetupMode;
        let p = plan(&r, &SetupOptions::default());
        assert!(p.steps.contains(&SetupStep::EnrollSecureBootKeys));
        assert!(p
            .steps
            .iter()
            .any(|s| matches!(s, SetupStep::RebootAndResume { .. })));
    }

    #[test]
    fn plan_blocks_when_secure_boot_unknown() {
        let mut r = fresh_install_report();
        r.machine.secure_boot = SecureBootState::Unknown;
        let p = plan(&r, &SetupOptions::default());
        assert!(p.blockers.iter().any(|b| b.contains("Secure Boot")));
    }

    #[test]
    fn plan_skips_key_generation_when_secure_boot_keys_already_exist() {
        let mut r = fresh_install_report();
        r.machine.secure_boot = SecureBootState::Disabled;
        let p = plan(
            &r,
            &SetupOptions {
                secure_boot_status: Some(secure_boot::Status::KeysGenerated),
                ..SetupOptions::default()
            },
        );
        assert!(!p.steps.contains(&SetupStep::PrepareSecureBootKeys));
        assert!(p
            .steps
            .iter()
            .any(|s| matches!(s, SetupStep::PauseForSecureBoot { .. })));
    }

    #[test]
    fn plan_blocks_when_secure_boot_not_supported() {
        let mut r = fresh_install_report();
        r.machine.secure_boot = SecureBootState::NotSupported;
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
    fn plan_enrolls_fido2_before_tpm_when_device_is_plugged_in() {
        let mut r = fresh_install_report();
        r.machine.fido2_devices = vec![Fido2Device {
            path: "/dev/hidraw0".into(),
            label: "Yubico YubiKey OTP+FIDO+CCID".into(),
        }];
        let p = plan(&r, &SetupOptions::default());
        let fido = p
            .steps
            .iter()
            .position(|s| matches!(s, SetupStep::EnrollFido2 { .. }))
            .expect("FIDO2 step");
        let tpm = p
            .steps
            .iter()
            .position(|s| matches!(s, SetupStep::EnrollTpm2 { .. }))
            .expect("TPM2 step");
        assert!(fido < tpm);
        assert!(!p
            .steps
            .iter()
            .any(|s| matches!(s, SetupStep::EnrollRecoveryKey { .. })));
    }

    #[test]
    fn plan_uses_existing_recovery_before_tpm() {
        let mut r = fresh_install_report();
        r.volumes[0].slots.recovery.enrolled = true;
        let p = plan(&r, &SetupOptions::default());
        assert!(!p
            .steps
            .iter()
            .any(|s| matches!(s, SetupStep::EnrollRecoveryKey { .. })));
        assert!(p
            .steps
            .iter()
            .any(|s| matches!(s, SetupStep::EnrollTpm2 { .. })));
    }

    #[test]
    fn plan_rotates_default_password_after_tpm() {
        let p = plan(&fresh_install_report(), &SetupOptions::default());
        let tpm = p
            .steps
            .iter()
            .position(|s| matches!(s, SetupStep::EnrollTpm2 { .. }))
            .expect("TPM2 step");
        let password = p
            .steps
            .iter()
            .position(|s| matches!(s, SetupStep::RotateDefaultPassword { .. }))
            .expect("password step");
        assert!(tpm < password);
    }

    #[test]
    fn action_for_recovery_step_generates_recovery_key_only() {
        let step = SetupStep::EnrollRecoveryKey {
            volume_id: "root".into(),
        };
        assert_eq!(
            action_for_step(&step).expect("valid step"),
            Some(EnrollmentAction::EnrollRecoveryKey)
        );
    }

    #[test]
    fn action_for_tpm_step_enrolls_tpm_only() {
        let step = SetupStep::EnrollTpm2 {
            volume_id: "root".into(),
        };
        assert_eq!(
            action_for_step(&step).expect("valid step"),
            Some(EnrollmentAction::EnrollTpm2)
        );
    }
}
