//! `ks update` command — pull, lock, build, push, deploy.
//!
//! Mirrors the shell `cmd_update` function from ks.sh.

use std::path::Path;

use anyhow::{Context, Result};
use serde::Serialize;

use crate::repo;

/// Result of an update operation.
#[derive(Debug, Serialize)]
pub struct UpdateResult {
    /// Hosts that were updated.
    pub hosts: Vec<String>,
    /// Whether this was a dev (unlocked) update.
    pub dev: bool,
    /// Deployment mode (switch or boot).
    pub mode: String,
}

/// Pull managed repos from the registry.
async fn pull_managed_repos(repo_root: &Path) -> Result<()> {
    let registry = repo::get_repos_registry(repo_root).await?;
    let obj = match registry.as_object() {
        Some(o) => o,
        None => return Ok(()),
    };

    for (key, value) in obj {
        let url = value.get("url").and_then(|v| v.as_str()).unwrap_or("");
        if url.is_empty() {
            continue;
        }

        let home = home::home_dir().unwrap_or_default();
        let repo_name = key.rsplit('/').next().unwrap_or(key);

        // Find existing checkout
        let candidates = [
            home.join(".keystone").join("repos").join(key),
            repo_root.join(".repos").join(repo_name),
            repo_root.join(".submodules").join(repo_name),
            repo_root.join(repo_name),
        ];

        let target = candidates
            .iter()
            .find(|p| p.join(".git").exists())
            .cloned()
            .unwrap_or_else(|| home.join(".keystone").join("repos").join(key));

        if target.join(".git").exists() {
            eprintln!("Pulling {}...", key);
            let output = tokio::process::Command::new("git")
                .args(["-C"])
                .arg(&target)
                .args(["pull", "--ff-only"])
                .output()
                .await;
            match output {
                Ok(o) if !o.status.success() => {
                    let stderr = String::from_utf8_lossy(&o.stderr);
                    eprintln!("Warning: failed to pull {}: {}", key, stderr.trim());
                }
                Err(e) => eprintln!("Warning: failed to pull {}: {}", key, e),
                _ => {}
            }
        } else {
            eprintln!("Cloning {}...", key);
            let parent = target.parent().unwrap_or(Path::new("."));
            let _ = tokio::fs::create_dir_all(parent).await;
            let output = tokio::process::Command::new("git")
                .args(["clone", url])
                .arg(&target)
                .output()
                .await;
            match output {
                Ok(o) if !o.status.success() => {
                    let stderr = String::from_utf8_lossy(&o.stderr);
                    eprintln!("Warning: failed to clone {}: {}", key, stderr.trim());
                }
                Err(e) => eprintln!("Warning: failed to clone {}: {}", key, e),
                _ => {}
            }
        }
    }

    Ok(())
}

/// Verify that a repo is clean and on a branch (lock-ready).
async fn verify_repo_lock_ready(path: &Path, name: &str) -> Result<()> {
    if !path.is_dir() {
        return Ok(());
    }

    // Check for uncommitted changes
    let status = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(path)
        .args(["diff", "--quiet"])
        .status()
        .await
        .context("Failed to check git diff")?;

    if !status.success() {
        anyhow::bail!("{} has uncommitted changes at {}", name, path.display());
    }

    // Check for uncommitted staged changes
    let status = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(path)
        .args(["diff", "--cached", "--quiet"])
        .status()
        .await
        .context("Failed to check git staged changes")?;

    if !status.success() {
        anyhow::bail!(
            "{} has staged uncommitted changes at {}",
            name,
            path.display()
        );
    }

    // Check for detached HEAD
    let output = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(path)
        .args(["symbolic-ref", "--quiet", "--short", "HEAD"])
        .output()
        .await
        .context("Failed to check HEAD state")?;

    if !output.status.success() {
        anyhow::bail!("{} is in detached HEAD state at {}", name, path.display());
    }

    Ok(())
}

/// Execute the dev-mode update (deploy current unlocked checkout).
async fn update_dev(_repo_root: &Path, mode: &str, hosts: &[String]) -> Result<UpdateResult> {
    crate::cmd::switch::execute(Some(&hosts.join(",")), mode == "boot").await?;

    Ok(UpdateResult {
        hosts: hosts.to_vec(),
        dev: true,
        mode: mode.to_string(),
    })
}

/// Verify all repos in the registry are lock-ready.
async fn verify_all_repos_lock_ready(repo_root: &Path) -> Result<()> {
    let registry = repo::get_repos_registry(repo_root).await?;
    let obj = match registry.as_object() {
        Some(o) => o,
        None => return Ok(()),
    };

    let home = home::home_dir().unwrap_or_default();
    for (key, _value) in obj {
        let repo_name = key.rsplit('/').next().unwrap_or(key);
        let candidates = [
            home.join(".keystone").join("repos").join(key),
            repo_root.join(".repos").join(repo_name),
            repo_root.join(".submodules").join(repo_name),
            repo_root.join(repo_name),
        ];
        if let Some(path) = candidates.iter().find(|p| p.is_dir()) {
            verify_repo_lock_ready(path, key).await?;
        }
    }
    Ok(())
}

/// Deploy a built system closure to a local host.
async fn deploy_local(host: &str, mode: &str, store_path: &str) -> Result<()> {
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
        .context("Failed to run nix-env --set")?;

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

    Ok(())
}

/// Execute the full lock-mode update (pull, verify, lock, build, deploy).
async fn update_locked(repo_root: &Path, mode: &str, hosts: &[String]) -> Result<UpdateResult> {
    // Step 1: Pull nixos-config
    eprintln!("Pulling nixos-config...");
    let _ = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(repo_root)
        .args(["pull", "--ff-only"])
        .status()
        .await;

    // Step 2: Pull all managed repos
    pull_managed_repos(repo_root).await?;

    // Step 3: Verify repos are lock-ready
    verify_all_repos_lock_ready(repo_root).await?;

    // Step 4: Build with lock
    let build_result = crate::cmd::build::execute(Some(&hosts.join(",")), true).await?;

    // Step 5: Deploy each local host
    let current_hostname = hostname::get()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let hosts_nix = repo_root.join("hosts.nix");

    for (i, host) in hosts.iter().enumerate() {
        if i >= build_result.store_paths.len() {
            break;
        }
        let store_path = &build_result.store_paths[i];
        let host_hostname = resolve_host_hostname(&hosts_nix, host).await;

        if host_hostname == current_hostname {
            deploy_local(host, mode, store_path).await?;
        }
    }

    // Step 6: Push nixos-config
    eprintln!("Pushing nixos-config...");
    let _ = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(repo_root)
        .arg("push")
        .status()
        .await;

    eprintln!("Update complete for: {}", hosts.join(", "));

    Ok(UpdateResult {
        hosts: hosts.to_vec(),
        dev: false,
        mode: mode.to_string(),
    })
}

/// Resolve a host's hostname from hosts.nix.
async fn resolve_host_hostname(hosts_nix: &Path, host: &str) -> String {
    let output = tokio::process::Command::new("nix")
        .args(["eval", "-f"])
        .arg(hosts_nix)
        .arg(format!("{}.hostname", host))
        .arg("--raw")
        .output()
        .await;

    output
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

/// Execute the update command.
pub async fn execute(
    hosts_arg: Option<&str>,
    dev: bool,
    boot: bool,
    pull_only: bool,
) -> Result<UpdateResult> {
    let repo_root = repo::find_repo()?;
    let hosts = repo::resolve_hosts(&repo_root, hosts_arg).await?;
    let mode = if boot { "boot" } else { "switch" };

    if pull_only {
        pull_managed_repos(&repo_root).await?;
        eprintln!("Pull complete.");
        return Ok(UpdateResult {
            hosts,
            dev: true,
            mode: "pull".to_string(),
        });
    }

    if dev {
        update_dev(&repo_root, mode, &hosts).await
    } else {
        update_locked(&repo_root, mode, &hosts).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn update_result_serialization() {
        let result = UpdateResult {
            hosts: vec!["ocean".to_string()],
            dev: false,
            mode: "switch".to_string(),
        };
        let json = serde_json::to_value(&result).unwrap();
        assert_eq!(json["hosts"][0], "ocean");
        assert_eq!(json["dev"], false);
        assert_eq!(json["mode"], "switch");
    }
}
