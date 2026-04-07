//! `ks build` command — build home-manager profiles or full NixOS systems.
//!
//! Mirrors the shell `cmd_build` function from ks.sh.

use std::path::Path;

use anyhow::{Context, Result};
use serde::Serialize;

use crate::repo;

/// Result of a build operation.
#[derive(Debug, Serialize)]
pub struct BuildResult {
    /// Hosts that were built.
    pub hosts: Vec<String>,
    /// Whether this was a full system (lock) build.
    pub lock: bool,
    /// Store paths produced by the build.
    pub store_paths: Vec<String>,
}

/// Run `nix build` for the given hosts and return store paths.
async fn run_nix_build(
    repo_root: &Path,
    hosts: &[String],
    override_args: &[String],
) -> Result<Vec<String>> {
    let build_targets: Vec<String> = hosts
        .iter()
        .map(|h| {
            format!(
                "{}#nixosConfigurations.{}.config.system.build.toplevel",
                repo_root.display(),
                h
            )
        })
        .collect();

    if build_targets.is_empty() {
        anyhow::bail!("No build targets resolved.");
    }

    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("build").arg("--no-link").arg("--print-out-paths");
    for target in &build_targets {
        cmd.arg(target);
    }
    for arg in override_args {
        cmd.arg(arg);
    }
    cmd.current_dir(repo_root);

    let output = cmd.output().await.context("Failed to run nix build")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("Build failed:\n{}", stderr);
    }

    Ok(String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter(|l| !l.is_empty())
        .map(|l| l.to_string())
        .collect())
}

/// Build home-manager profiles for the given hosts (default mode).
async fn build_home_manager(repo_root: &Path, hosts: &[String]) -> Result<BuildResult> {
    let override_args = repo::local_override_args(repo_root).await?;

    eprintln!("Building home-manager profiles: {}...", hosts.join(", "));

    let paths = run_nix_build(repo_root, hosts, &override_args).await?;

    eprintln!("Build complete for: {}", hosts.join(", "));

    Ok(BuildResult {
        hosts: hosts.to_vec(),
        lock: false,
        store_paths: paths,
    })
}

/// Lock flake inputs from the registry.
async fn lock_flake_inputs(repo_root: &Path, registry: &serde_json::Value) -> Result<()> {
    let obj = match registry.as_object() {
        Some(o) => o,
        None => return Ok(()),
    };

    let inputs: Vec<&str> = obj
        .values()
        .filter_map(|v| v.get("flakeInput").and_then(|fi| fi.as_str()))
        .filter(|s| !s.is_empty() && *s != "null")
        .collect();

    if inputs.is_empty() {
        return Ok(());
    }

    eprintln!("Locking flake inputs...");
    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("flake").arg("update");
    for input in &inputs {
        cmd.arg(input);
    }
    cmd.arg("--flake").arg(repo_root);
    let output = cmd.output().await.context("Failed to lock flake inputs")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("Flake lock failed:\n{}", stderr);
    }
    Ok(())
}

/// Commit flake.lock if it has changed.
async fn commit_flake_lock(repo_root: &Path) -> Result<()> {
    let lock_status = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(repo_root)
        .args(["diff", "--quiet", "flake.lock"])
        .status()
        .await;

    if let Ok(status) = lock_status {
        if !status.success() {
            eprintln!("Committing flake.lock...");
            let _ = tokio::process::Command::new("git")
                .args(["-C"])
                .arg(repo_root)
                .args(["add", "flake.lock"])
                .status()
                .await;
            let _ = tokio::process::Command::new("git")
                .args(["-C"])
                .arg(repo_root)
                .args(["commit", "-m", "chore: relock keystone + agenix-secrets"])
                .status()
                .await;
        }
    }
    Ok(())
}

/// Build full NixOS system closures with lock workflow.
async fn build_locked(repo_root: &Path, hosts: &[String]) -> Result<BuildResult> {
    let registry = repo::get_repos_registry(repo_root).await?;
    let override_args = repo::local_override_args(repo_root).await?;

    lock_flake_inputs(repo_root, &registry).await?;

    // Build full system closures
    let paths = run_nix_build(repo_root, hosts, &override_args).await?;

    commit_flake_lock(repo_root).await?;

    eprintln!("Lock + build complete for: {}", hosts.join(", "));

    Ok(BuildResult {
        hosts: hosts.to_vec(),
        lock: true,
        store_paths: paths,
    })
}

/// Execute the build command.
pub async fn execute(hosts_arg: Option<&str>, lock: bool) -> Result<BuildResult> {
    let repo_root = repo::find_repo()?;
    let hosts = repo::resolve_hosts(&repo_root, hosts_arg).await?;

    if lock {
        build_locked(&repo_root, &hosts).await
    } else {
        build_home_manager(&repo_root, &hosts).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_result_serialization() {
        let result = BuildResult {
            hosts: vec!["workstation".to_string()],
            lock: false,
            store_paths: vec!["/nix/store/abc-system".to_string()],
        };
        let json = serde_json::to_value(&result).unwrap();
        assert_eq!(json["hosts"][0], "workstation");
        assert_eq!(json["lock"], false);
        assert_eq!(json["store_paths"][0], "/nix/store/abc-system");
    }
}
