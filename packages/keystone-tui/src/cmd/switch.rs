//! `ks switch` command — deploy current local state without pull/lock/push.
//!
//! Mirrors the shell `cmd_switch` / `deploy_unlocked_current_state` functions.

use std::path::Path;

use anyhow::{Context, Result};
use serde::Serialize;

use crate::repo;

/// Result of a switch operation.
#[derive(Debug, Serialize)]
pub struct SwitchResult {
    /// Hosts that were deployed.
    pub hosts: Vec<String>,
    /// Deployment mode (switch or boot).
    pub mode: String,
    /// Store paths that were built and deployed.
    pub store_paths: Vec<String>,
}

/// Build and deploy the current unlocked state to the given hosts.
async fn deploy_unlocked(repo_root: &Path, mode: &str, hosts: &[String]) -> Result<SwitchResult> {
    let override_args = repo::local_override_args(repo_root).await?;

    // Build all targets
    let mut build_targets = Vec::new();
    for h in hosts {
        build_targets.push(format!(
            "{}#nixosConfigurations.{}.config.system.build.toplevel",
            repo_root.display(),
            h
        ));
    }

    eprintln!("Building current unlocked state: {}...", hosts.join(", "));

    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("build").arg("--no-link").arg("--print-out-paths");
    for target in &build_targets {
        cmd.arg(target);
    }
    for arg in &override_args {
        cmd.arg(arg);
    }
    cmd.current_dir(repo_root);

    let output = cmd.output().await.context("Failed to run nix build")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("Build failed:\n{}", stderr);
    }

    let paths: Vec<String> = String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter(|l| !l.is_empty())
        .map(|l| l.to_string())
        .collect();

    if paths.len() != hosts.len() {
        anyhow::bail!(
            "nix build returned {} path(s) for {} target host(s).",
            paths.len(),
            hosts.len()
        );
    }

    // Deploy each host sequentially
    let current_hostname = hostname::get()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let hosts_nix = repo_root.join("hosts.nix");

    for (i, host) in hosts.iter().enumerate() {
        let store_path = &paths[i];

        // Get the host's hostname from hosts.nix
        let host_hostname_output = tokio::process::Command::new("nix")
            .args(["eval", "-f"])
            .arg(&hosts_nix)
            .arg(format!("{}.hostname", host))
            .arg("--raw")
            .output()
            .await;

        let host_hostname = host_hostname_output
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_default();

        if host_hostname == current_hostname {
            // Local deploy
            eprintln!("Deploying {} locally ({} mode)...", host, mode);
            let status = tokio::process::Command::new("sudo")
                .args([
                    "nix-env",
                    "--profile",
                    "/nix/var/nix/profiles/system",
                    "--set",
                ])
                .arg(store_path)
                .status()
                .await
                .context("Failed to set system profile")?;

            if !status.success() {
                anyhow::bail!("Failed to set system profile for {}", host);
            }

            let switch_cmd = format!("{}/bin/switch-to-configuration", store_path);
            let status = tokio::process::Command::new("sudo")
                .arg(&switch_cmd)
                .arg(mode)
                .status()
                .await
                .context("Failed to switch configuration")?;

            if !status.success() {
                anyhow::bail!("Failed to {} for {}", mode, host);
            }
        } else {
            // Remote deploy — get ssh target
            let ssh_output = tokio::process::Command::new("nix")
                .args(["eval", "-f"])
                .arg(&hosts_nix)
                .arg(format!("{}.sshTarget", host))
                .arg("--raw")
                .output()
                .await;

            let ssh_target = ssh_output
                .ok()
                .filter(|o| o.status.success())
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                .unwrap_or_default();

            if ssh_target.is_empty() {
                anyhow::bail!("{} has no sshTarget, cannot deploy remotely.", host);
            }

            eprintln!("Deploying {} remotely to {}...", host, ssh_target);

            // Copy closure to remote
            let status = tokio::process::Command::new("nix")
                .args(["copy", "--to"])
                .arg(format!("ssh://root@{}", ssh_target))
                .arg(store_path)
                .status()
                .await
                .context("Failed to copy closure to remote host")?;

            if !status.success() {
                eprintln!(
                    "Warning: nix copy to {} failed, attempting switch anyway",
                    ssh_target
                );
            }

            // Switch on remote
            let switch_cmd = format!("{}/bin/switch-to-configuration", store_path);
            let status = tokio::process::Command::new("ssh")
                .arg(format!("root@{}", ssh_target))
                .arg(format!(
                    "nix-env --profile /nix/var/nix/profiles/system --set {} && {}",
                    store_path, switch_cmd
                ))
                .arg(mode)
                .status()
                .await
                .context("Failed to switch on remote host")?;

            if !status.success() {
                anyhow::bail!("Failed to {} on remote host {}", mode, host);
            }
        }
    }

    eprintln!("Switch complete for: {}", hosts.join(", "));

    Ok(SwitchResult {
        hosts: hosts.to_vec(),
        mode: mode.to_string(),
        store_paths: paths,
    })
}

/// Execute the switch command.
pub async fn execute(hosts_arg: Option<&str>, boot: bool) -> Result<SwitchResult> {
    let repo_root = repo::find_repo()?;
    let hosts = repo::resolve_hosts(&repo_root, hosts_arg).await?;
    let mode = if boot { "boot" } else { "switch" };

    deploy_unlocked(&repo_root, mode, &hosts).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn switch_result_serialization() {
        let result = SwitchResult {
            hosts: vec!["laptop".to_string()],
            mode: "switch".to_string(),
            store_paths: vec!["/nix/store/xyz-system".to_string()],
        };
        let json = serde_json::to_value(&result).unwrap();
        assert_eq!(json["hosts"][0], "laptop");
        assert_eq!(json["mode"], "switch");
    }
}
