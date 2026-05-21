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

use crate::cli::HardwareCommand;

/// Dispatch `ks hardware <subcommand>`.
pub async fn execute(command: HardwareCommand, flake: Option<&Path>) -> Result<()> {
    match command {
        HardwareCommand::Report {
            json,
            pre_install,
            post_install,
            write_status_file,
            disk,
        } => report::execute(json, pre_install, post_install, write_status_file, disk).await,
        HardwareCommand::Setup { dry_run } => {
            setup::execute_cli(setup::SetupOptions { dry_run }).await
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
    use crate::cli::{DisksCommand, FdeCommand};

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
