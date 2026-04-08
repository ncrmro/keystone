//! `ks switch` command — deploy current local state without pull/lock/push.

use anyhow::{Context, Result};
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use crate::{cmd::ssh::SshSessionManager, repo};

#[derive(Debug, Serialize)]
pub struct SwitchResult {
    pub hosts: Vec<String>,
    pub mode: String,
    pub store_paths: Vec<String>,
}

pub struct DeploySession {
    local_hosts: BTreeSet<String>,
    remote_targets: BTreeMap<String, String>,
    ssh: SshSessionManager,
}

async fn build_targets(repo_root: &Path, hosts: &[String]) -> Result<Vec<String>> {
    let override_args = repo::local_override_args(repo_root).await?;
    let build_targets: Vec<String> = hosts
        .iter()
        .map(|host| {
            format!(
                "{}#nixosConfigurations.{}.config.system.build.toplevel",
                repo_root.display(),
                host,
            )
        })
        .collect();

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
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect();

    if paths.len() != hosts.len() {
        anyhow::bail!(
            "nix build returned {} path(s) for {} target host(s).",
            paths.len(),
            hosts.len()
        );
    }

    Ok(paths)
}

async fn deploy_local(host: &str, mode: &str, store_path: &str) -> Result<()> {
    eprintln!("Deploying {} locally ({} mode)...", host, mode);

    let set_status = tokio::process::Command::new("sudo")
        .args([
            "nix-env",
            "--profile",
            "/nix/var/nix/profiles/system",
            "--set",
        ])
        .arg(store_path)
        .status()
        .await
        .context("Failed to set local system profile")?;
    if !set_status.success() {
        anyhow::bail!("Failed to set system profile for {}", host);
    }

    let switch_cmd = format!("{}/bin/switch-to-configuration", store_path);
    let switch_status = tokio::process::Command::new("sudo")
        .arg(&switch_cmd)
        .arg(mode)
        .status()
        .await
        .context("Failed to switch local configuration")?;
    if !switch_status.success() {
        anyhow::bail!("Failed to {} for {}", mode, host);
    }

    Ok(())
}

async fn deploy_remote(
    ssh: &SshSessionManager,
    host: &str,
    mode: &str,
    store_path: &str,
    ssh_target: &str,
) -> Result<()> {
    eprintln!("Deploying {} remotely to {}...", host, ssh_target);

    let mut copy_cmd = tokio::process::Command::new("nix");
    copy_cmd
        .args(["copy", "--to"])
        .arg(format!("ssh://root@{}", ssh_target))
        .arg(store_path);
    ssh.configure_nix_copy_command(&mut copy_cmd, ssh_target);

    let copy_status = copy_cmd
        .status()
        .await
        .context("Failed to copy closure to remote host")?;
    if !copy_status.success() {
        eprintln!(
            "Warning: nix copy to {} failed, attempting switch anyway",
            ssh_target
        );
    }

    let switch_cmd = format!("{}/bin/switch-to-configuration", store_path);
    let mut remote_cmd = tokio::process::Command::new("ssh");
    ssh.configure_ssh_command(&mut remote_cmd, ssh_target);
    let remote_status = remote_cmd
        .arg(format!("root@{}", ssh_target))
        .arg(format!(
            "nix-env --profile /nix/var/nix/profiles/system --set {} && {} {}",
            store_path, switch_cmd, mode
        ))
        .status()
        .await
        .context("Failed to switch remote configuration")?;
    if !remote_status.success() {
        anyhow::bail!("Failed to {} on remote host {}", mode, host);
    }

    Ok(())
}

pub async fn prepare_deploy_session(repo_root: &Path, hosts: &[String]) -> Result<DeploySession> {
    let current_hostname = hostname::get()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let hosts_nix = repo_root.join("hosts.nix");
    let mut local_hosts = BTreeSet::new();
    let mut remote_targets = BTreeMap::new();
    let mut ssh = SshSessionManager::new();

    for host in hosts {
        let host_info = repo::host_info(&hosts_nix, host).await?;
        if host_info.hostname == current_hostname {
            local_hosts.insert(host.clone());
            continue;
        }

        let ssh_target = repo::resolve_ssh_target(repo_root, host, &host_info)
            .await?
            .ok_or_else(|| anyhow::anyhow!("{} has no sshTarget, cannot deploy remotely.", host))?;

        let mut resolved = ssh_target.clone();
        if let Some(fallback_ip) = host_info
            .fallback_ip
            .as_deref()
            .filter(|value| !value.is_empty())
        {
            if !ssh.ssh_test(&ssh_target).await? {
                resolved = fallback_ip.to_string();
                eprintln!(
                    "Tailscale unavailable for {}, using LAN: {}",
                    host, fallback_ip
                );
            }
        }

        ssh.open_master(&resolved).await?;
        remote_targets.insert(host.clone(), resolved);
    }

    Ok(DeploySession {
        local_hosts,
        remote_targets,
        ssh,
    })
}

pub async fn deploy_paths_with_session(
    _repo_root: &Path,
    session: &DeploySession,
    mode: &str,
    hosts: &[String],
    store_paths: &[String],
) -> Result<()> {
    for (host, store_path) in hosts.iter().zip(store_paths.iter()) {
        if session.local_hosts.contains(host) {
            deploy_local(host, mode, store_path).await?;
            continue;
        }

        let ssh_target = session.remote_targets.get(host).ok_or_else(|| {
            anyhow::anyhow!("{} is not available in the prepared deploy session.", host)
        })?;
        deploy_remote(&session.ssh, host, mode, store_path, ssh_target).await?;
    }

    Ok(())
}

pub async fn deploy_paths(
    repo_root: &Path,
    mode: &str,
    hosts: &[String],
    store_paths: &[String],
) -> Result<()> {
    let session = prepare_deploy_session(repo_root, hosts).await?;
    deploy_paths_with_session(repo_root, &session, mode, hosts, store_paths).await
}

pub async fn execute(hosts_arg: Option<&str>, boot: bool) -> Result<SwitchResult> {
    let repo_root = repo::find_repo()?;
    let hosts = repo::resolve_hosts(&repo_root, hosts_arg).await?;
    let mode = if boot { "boot" } else { "switch" };
    let session = prepare_deploy_session(&repo_root, &hosts).await?;
    let store_paths = build_targets(&repo_root, &hosts).await?;

    deploy_paths_with_session(&repo_root, &session, mode, &hosts, &store_paths).await?;

    Ok(SwitchResult {
        hosts,
        mode: mode.to_string(),
        store_paths,
    })
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

    #[test]
    fn deploy_session_tracks_local_and_remote_hosts() {
        let session = DeploySession {
            local_hosts: ["local".to_string()].into_iter().collect(),
            remote_targets: [("remote".to_string(), "tail.example.ts.net".to_string())]
                .into_iter()
                .collect(),
            ssh: SshSessionManager::new(),
        };

        assert!(session.local_hosts.contains("local"));
        assert_eq!(
            session.remote_targets.get("remote"),
            Some(&"tail.example.ts.net".to_string())
        );
    }
}
