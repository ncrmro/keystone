//! `ks doctor` command — system health diagnostics.
//!
//! Mirrors the shell `cmd_doctor` / `gather_system_state` functions from ks.sh.
//! Collects NixOS generation, failed units, disk usage, flake.lock age,
//! and produces a markdown report.

use std::path::Path;

use anyhow::{Context, Result};
use serde::Serialize;

use crate::repo;

/// A single diagnostic check result.
#[derive(Debug, Clone, Serialize)]
pub struct DiagnosticCheck {
    /// Short label for the check.
    pub name: String,
    /// Status: ok, warning, error, unknown.
    pub status: String,
    /// Human-readable detail.
    pub detail: String,
}

/// Full doctor report.
#[derive(Debug, Serialize)]
pub struct DoctorReport {
    /// Hostname of the machine.
    pub hostname: String,
    /// NixOS generation string (if available).
    pub nixos_generation: Option<String>,
    /// Individual diagnostic checks.
    pub checks: Vec<DiagnosticCheck>,
    /// Markdown-formatted report.
    pub markdown: String,
}

/// Collect the NixOS generation.
async fn collect_nixos_generation() -> Option<String> {
    let output = tokio::process::Command::new("nixos-version")
        .output()
        .await
        .ok()?;
    if output.status.success() {
        Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        None
    }
}

/// Collect failed systemd units.
async fn collect_failed_units() -> Vec<String> {
    let output = tokio::process::Command::new("systemctl")
        .args(["--failed", "--plain", "--no-legend", "--no-pager"])
        .output()
        .await;

    match output {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout)
            .lines()
            .filter_map(|line| {
                let trimmed = line.trim().trim_start_matches('●').trim();
                let unit = trimmed.split_whitespace().next()?;
                if unit.is_empty() {
                    None
                } else {
                    Some(unit.to_string())
                }
            })
            .collect(),
        _ => Vec::new(),
    }
}

/// Collect disk usage.
async fn collect_disk_usage() -> String {
    let output = tokio::process::Command::new("df").arg("-h").output().await;

    match output {
        Ok(o) if o.status.success() => {
            let text = String::from_utf8_lossy(&o.stdout);
            text.lines().take(20).collect::<Vec<_>>().join("\n")
        }
        _ => "unavailable".to_string(),
    }
}

/// Collect the age of flake.lock.
async fn collect_flake_lock_age(repo_root: &Path) -> String {
    let lock_path = repo_root.join("flake.lock");
    if !lock_path.is_file() {
        return "flake.lock not found".to_string();
    }

    let output = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(repo_root)
        .args(["log", "-1", "--format=%ar", "--", "flake.lock"])
        .output()
        .await;

    match output {
        Ok(o) if o.status.success() => {
            let age = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if age.is_empty() {
                "unknown".to_string()
            } else {
                format!("Last updated: {}", age)
            }
        }
        _ => "unknown".to_string(),
    }
}

/// Build a full doctor report.
pub async fn gather_report(repo_root: &Path) -> Result<DoctorReport> {
    let hostname = hostname::get()
        .context("Failed to get hostname")?
        .to_string_lossy()
        .to_string();

    let mut checks = Vec::new();
    let mut md = String::new();

    md.push_str("## System State\n\n");

    // NixOS generation
    let generation = collect_nixos_generation().await;
    if let Some(ref gen) = generation {
        md.push_str(&format!("**NixOS generation**: {}\n\n", gen));
    }

    // Failed systemd units
    md.push_str("### Failed systemd units\n");
    let failed_units = collect_failed_units().await;
    if failed_units.is_empty() {
        md.push_str("_None_\n");
        checks.push(DiagnosticCheck {
            name: "systemd-units".to_string(),
            status: "ok".to_string(),
            detail: "No failed units".to_string(),
        });
    } else {
        for unit in &failed_units {
            md.push_str(&format!("- {}\n", unit));
        }
        checks.push(DiagnosticCheck {
            name: "systemd-units".to_string(),
            status: "error".to_string(),
            detail: format!("{} failed unit(s)", failed_units.len()),
        });
    }
    md.push('\n');

    // Disk usage
    md.push_str("### Disk usage\n```\n");
    let disk_usage = collect_disk_usage().await;
    md.push_str(&disk_usage);
    md.push_str("\n```\n\n");

    checks.push(DiagnosticCheck {
        name: "disk-usage".to_string(),
        status: "ok".to_string(),
        detail: "Disk usage collected".to_string(),
    });

    // flake.lock age
    md.push_str("### flake.lock age\n");
    let lock_age = collect_flake_lock_age(repo_root).await;
    md.push_str(&format!("_{}_\n\n", lock_age));

    checks.push(DiagnosticCheck {
        name: "flake-lock-age".to_string(),
        status: "ok".to_string(),
        detail: lock_age,
    });

    Ok(DoctorReport {
        hostname,
        nixos_generation: generation,
        checks,
        markdown: md,
    })
}

/// Execute the doctor command.
pub async fn execute() -> Result<DoctorReport> {
    let repo_root = repo::find_repo()?;
    gather_report(&repo_root).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn doctor_report_serialization() {
        let report = DoctorReport {
            hostname: "test-host".to_string(),
            nixos_generation: Some("25.05.20260401.abc1234".to_string()),
            checks: vec![DiagnosticCheck {
                name: "systemd-units".to_string(),
                status: "ok".to_string(),
                detail: "No failed units".to_string(),
            }],
            markdown: "## System State\n".to_string(),
        };
        let json = serde_json::to_value(&report).unwrap();
        assert_eq!(json["hostname"], "test-host");
        assert_eq!(json["checks"][0]["status"], "ok");
    }

    #[test]
    fn diagnostic_check_fields() {
        let check = DiagnosticCheck {
            name: "test".to_string(),
            status: "warning".to_string(),
            detail: "some detail".to_string(),
        };
        assert_eq!(check.name, "test");
        assert_eq!(check.status, "warning");
    }
}
