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
        HardwareCommand::Setup {
            dry_run,
            non_interactive,
            allow_no_sb,
            new_passphrase,
        } => {
            setup::execute_cli(setup::SetupOptions {
                dry_run,
                non_interactive,
                allow_no_sb,
                new_passphrase,
            })
            .await
        }
        HardwareCommand::Disks { id: _, command: _ } => {
            anyhow::bail!("ks hardware disks: not yet implemented (v1.2 — see plan)")
        }
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
