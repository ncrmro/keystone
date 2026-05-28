//! `ks hardware` — hardware-credential management.
//!
//! Two concerns share this namespace because both gate access to data at
//! rest on the same physical machine:
//!
//! - **LUKS unlock** (`report`, `setup`, `disks`, `enroll`, `rotate`,
//!   `remove`) — credentials that decrypt the root disk and any
//!   additional LUKS-protected zvols holding ZFS pool keys.
//! - **Identity** (`key`) — hardware-backed SSH and agenix identities
//!   (YubiKey FIDO2 SSH keys, age-yubikey recipients). Inherited from
//!   the legacy `ks hardware-key` surface.

pub mod enroll;
pub mod key;
pub mod probe;
pub mod report;
pub mod setup;

use anyhow::Result;
use std::path::Path;

use crate::cli::{DisksCommand, FdeCommand, HardwareCommand};
use crate::cmd::approve;

/// Dispatch `ks hardware <subcommand>`.
pub async fn execute(command: HardwareCommand, flake: Option<&Path>) -> Result<()> {
    maybe_execute_via_approval(&command)?;

    match command {
        HardwareCommand::Report {
            json,
            pre_install,
            post_install,
            write_status_file,
            disk,
        } => report::execute(json, pre_install, post_install, write_status_file, disk).await,
        HardwareCommand::Setup { dry_run } => {
            setup::execute_cli(setup::SetupOptions {
                dry_run,
                secure_boot_status: None,
            })
            .await
        }
        HardwareCommand::Disks { id, command } => disks_dispatch(id, command).await,
        HardwareCommand::Enroll { method, disk } => {
            let m: probe::Method = method.parse().map_err(anyhow::Error::msg)?;
            enroll::execute(m, disk).await
        }
        HardwareCommand::Rotate { method: _, disk: _ } => {
            anyhow::bail!("ks hardware rotate: not yet implemented (v1.2)")
        }
        HardwareCommand::Remove { method: _, disk: _ } => {
            anyhow::bail!("ks hardware remove: not yet implemented (v1.2)")
        }
        HardwareCommand::Key { command } => key::execute(command, flake).await,
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ApprovalRequest {
    reason: &'static str,
    status_line: &'static str,
    argv: Vec<String>,
}

fn maybe_execute_via_approval(command: &HardwareCommand) -> Result<()> {
    if already_elevated() {
        return Ok(());
    }

    let Some(request) = approval_request_for_command(command) else {
        return Ok(());
    };

    println!("{}", request.status_line);
    approve::execute_quiet(request.reason, &request.argv)
}

fn already_elevated() -> bool {
    std::env::var_os("KS_APPROVE_EXECUTING").is_some()
        ||
        // SAFETY: geteuid() is always available on Linux and has no side effects.
        unsafe { libc::geteuid() == 0 }
}

fn approval_request_for_command(command: &HardwareCommand) -> Option<ApprovalRequest> {
    match command {
        HardwareCommand::Setup { dry_run: false } => Some(ApprovalRequest {
            reason: "Configure hardware-backed disk enrollment and unlock methods.",
            status_line: "Requesting approval to configure hardware-backed disk unlock...",
            argv: vec!["ks".into(), "hardware".into(), "setup".into()],
        }),
        HardwareCommand::Setup { dry_run: true } => Some(ApprovalRequest {
            reason: "Inspect the planned hardware enrollment flow on this host.",
            status_line: "Requesting approval to inspect the hardware enrollment plan...",
            argv: vec![
                "ks".into(),
                "hardware".into(),
                "setup".into(),
                "--dry-run".into(),
            ],
        }),
        HardwareCommand::Enroll { method, disk } => {
            approval_request_for_enroll(method, disk.as_deref())
        }
        HardwareCommand::Disks {
            id: Some(id),
            command:
                Some(DisksCommand::Fde {
                    command: FdeCommand::Enroll { method },
                }),
        } => approval_request_for_enroll(method, Some(id.as_str())),
        _ => None,
    }
}

fn approval_request_for_enroll(method: &str, disk: Option<&str>) -> Option<ApprovalRequest> {
    let method = method.parse::<probe::Method>().ok()?;
    let mut argv = vec!["ks".into(), "hardware".into(), "enroll".into()];

    let (reason, status_line, canonical_method) = match method {
        probe::Method::Password => {
            if !matches!(disk, None | Some("root")) {
                return None;
            }
            (
                "Rotate the disk unlock password on this host.",
                "Requesting approval to rotate the disk unlock password...",
                "password",
            )
        }
        probe::Method::Recovery => {
            if !matches!(disk, None | Some("root")) {
                return None;
            }
            (
                "Generate a recovery key and enroll TPM-backed disk unlock on this host.",
                "Requesting approval to generate a recovery key and enroll TPM-backed disk unlock...",
                "recovery",
            )
        }
        probe::Method::Tpm2 => {
            if !matches!(disk, None | Some("root")) {
                return None;
            }
            (
                "Enroll or re-bind TPM-backed disk unlock on this host.",
                "Requesting approval to enroll TPM-backed disk unlock...",
                "tpm2",
            )
        }
        probe::Method::Fido2 => {
            if !matches!(disk, None | Some("root")) {
                return None;
            }
            (
                "Enroll a FIDO2 hardware key for disk unlock.",
                "Requesting approval to enroll a hardware key for disk unlock...",
                "fido2",
            )
        }
        probe::Method::Fingerprint => (
            "Enroll a fingerprint for sudo and login on this host.",
            "Requesting approval to enroll a fingerprint for sudo and login...",
            "fingerprint",
        ),
    };

    argv.push(canonical_method.into());
    Some(ApprovalRequest {
        reason,
        status_line,
        argv,
    })
}

/// `ks hardware disks [<id> [fde <verb> [args]]]`.
///
/// v1.1 RC scope:
///
/// - `ks hardware disks` lists detected LUKS volumes from the live probe.
/// - `ks hardware disks <id> fde report` is supported and equivalent to
///   `ks hardware report --disk=<id>`.
/// - `ks hardware disks <id> fde enroll <method>` is supported and
///   equivalent to `ks hardware enroll <method> --disk=<id>` (root only).
/// - `ks hardware disks <id> fde rotate <method>` and `remove <method>`
///   return an explicit "v1.2" error — these verbs are tracked but the
///   per-slot rotate/remove logic is not yet implemented.
async fn disks_dispatch(
    id: Option<String>,
    command: Option<crate::cli::DisksCommand>,
) -> Result<()> {
    let Some(id) = id else {
        // List all detected LUKS volumes.
        let report = probe::probe().await;
        if report.volumes.is_empty() {
            println!("No LUKS volumes detected.");
            println!("Keystone expects {} after install.", probe::ROOT_CREDSTORE);
            return Ok(());
        }
        for v in &report.volumes {
            println!("{:<14}  {}", v.id, v.device.display());
        }
        return Ok(());
    };

    match command {
        None => {
            // `ks hardware disks <id>` → focused report on this volume.
            report::execute(false, false, false, None, Some(id)).await
        }
        Some(DisksCommand::Fde { command: fde }) => match fde {
            FdeCommand::Report { json } => {
                report::execute(json, false, false, None, Some(id)).await
            }
            FdeCommand::Enroll { method } => {
                let m: probe::Method = method.parse().map_err(anyhow::Error::msg)?;
                enroll::execute(m, Some(id)).await
            }
            FdeCommand::Rotate { method: _ } => {
                anyhow::bail!(
                    "ks hardware disks {} fde rotate: not yet implemented (v1.2)",
                    id
                )
            }
            FdeCommand::Remove { method: _ } => {
                anyhow::bail!(
                    "ks hardware disks {} fde remove: not yet implemented (v1.2)",
                    id
                )
            }
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn setup_requires_approval_with_and_without_dry_run() {
        let setup = approval_request_for_command(&HardwareCommand::Setup { dry_run: false })
            .expect("setup should require approval");
        assert_eq!(setup.argv, vec!["ks", "hardware", "setup"]);
        assert_eq!(
            setup.status_line,
            "Requesting approval to configure hardware-backed disk unlock..."
        );

        let dry_run = approval_request_for_command(&HardwareCommand::Setup { dry_run: true })
            .expect("setup --dry-run should require approval");
        assert_eq!(dry_run.argv, vec!["ks", "hardware", "setup", "--dry-run"]);
        assert_eq!(
            dry_run.status_line,
            "Requesting approval to inspect the hardware enrollment plan..."
        );
    }

    #[test]
    fn enroll_root_disk_commands_canonicalize_to_exact_allowlist_shape() {
        let request = approval_request_for_command(&HardwareCommand::Enroll {
            method: "tpm".into(),
            disk: Some("root".into()),
        })
        .expect("root-disk enroll should require approval");
        assert_eq!(request.argv, vec!["ks", "hardware", "enroll", "tpm2"]);
        assert_eq!(
            request.status_line,
            "Requesting approval to enroll TPM-backed disk unlock..."
        );
    }

    #[test]
    fn nested_enroll_commands_canonicalize_to_sugar_form() {
        let request = approval_request_for_command(&HardwareCommand::Disks {
            id: Some("root".into()),
            command: Some(DisksCommand::Fde {
                command: FdeCommand::Enroll {
                    method: "fido2".into(),
                },
            }),
        })
        .expect("nested root-disk enroll should require approval");
        assert_eq!(request.argv, vec!["ks", "hardware", "enroll", "fido2"]);
    }

    #[test]
    fn non_root_disk_enrolls_do_not_match_the_allowlist() {
        let request = approval_request_for_command(&HardwareCommand::Enroll {
            method: "recovery".into(),
            disk: Some("data".into()),
        });
        assert!(request.is_none());
    }

    #[test]
    fn report_stays_outside_the_approval_broker() {
        let request = approval_request_for_command(&HardwareCommand::Report {
            json: false,
            pre_install: false,
            post_install: false,
            write_status_file: None,
            disk: None,
        });
        assert!(request.is_none());
    }
}
