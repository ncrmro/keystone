//! `ks update` command — pull, lock, build, push, deploy.

use anyhow::{Context, Result};
use serde::Serialize;
use std::path::{Path, PathBuf};

use crate::{cmd, repo};

#[derive(Debug, Serialize)]
pub struct UpdateResult {
    pub hosts: Vec<String>,
    pub dev: bool,
    pub mode: String,
}

async fn repo_checkout_candidates(repo_root: &Path, key: &str) -> Vec<PathBuf> {
    let home = home::home_dir().unwrap_or_default();
    let repo_name = key.rsplit('/').next().unwrap_or(key);
    vec![
        home.join(".keystone").join("repos").join(key),
        repo_root.join(".repos").join(repo_name),
        repo_root.join(".submodules").join(repo_name),
        repo_root.join(repo_name),
    ]
}

// Run `git pull --ff-only` after self-healing missing upstream tracking.
// Repos bootstrapped with `git init` + `git remote add` + `git push` (no
// `-u`) end up on a branch with no `branch.<name>.remote/merge` — git
// pull then aborts with "There is no tracking information for the
// current branch" and ks would have to warn-and-continue, leaving the
// repo stale without telling the user why.
async fn git_pull_ff_with_upstream_repair(path: &Path, name: &str) -> Result<()> {
    let upstream = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(path)
        .args(["rev-parse", "--abbrev-ref", "@{upstream}"])
        .output()
        .await
        .context("Failed to query upstream")?;

    if !upstream.status.success() {
        let branch_out = tokio::process::Command::new("git")
            .args(["-C"])
            .arg(path)
            .args(["symbolic-ref", "--quiet", "--short", "HEAD"])
            .output()
            .await
            .context("Failed to read current branch")?;
        if !branch_out.status.success() {
            anyhow::bail!("{} is in detached HEAD state at {}", name, path.display());
        }
        let branch = String::from_utf8_lossy(&branch_out.stdout)
            .trim()
            .to_string();

        let _ = tokio::process::Command::new("git")
            .args(["-C"])
            .arg(path)
            .args(["fetch", "--quiet", "origin"])
            .status()
            .await;

        let remote_ref = format!("refs/remotes/origin/{}", branch);
        let has_remote = tokio::process::Command::new("git")
            .args(["-C"])
            .arg(path)
            .args(["rev-parse", "--quiet", "--verify", &remote_ref])
            .status()
            .await
            .map(|status| status.success())
            .unwrap_or(false);
        if !has_remote {
            anyhow::bail!(
                "{} branch '{}' has no upstream and origin/{} does not exist at {}",
                name,
                branch,
                branch,
                path.display()
            );
        }

        eprintln!("Configuring upstream for {}: {} -> origin/{}", name, branch, branch);
        let set_status = tokio::process::Command::new("git")
            .args(["-C"])
            .arg(path)
            .args([
                "branch",
                "--set-upstream-to",
                &format!("origin/{}", branch),
                &branch,
            ])
            .status()
            .await
            .context("Failed to configure upstream")?;
        if !set_status.success() {
            anyhow::bail!("Failed to configure upstream for {}", name);
        }
    }

    let pull_status = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(path)
        .args(["pull", "--ff-only"])
        .status()
        .await
        .context("Failed to run git pull")?;
    if !pull_status.success() {
        anyhow::bail!("git pull --ff-only failed for {}", name);
    }
    Ok(())
}

async fn pull_managed_repos(repo_root: &Path) -> Result<()> {
    let registry = repo::get_repos_registry(repo_root).await?;
    let obj = match registry.as_object() {
        Some(obj) => obj,
        None => return Ok(()),
    };

    for (key, value) in obj {
        let url = value
            .get("url")
            .and_then(|item| item.as_str())
            .unwrap_or("");
        if url.is_empty() {
            continue;
        }

        let candidates = repo_checkout_candidates(repo_root, key).await;
        let target = candidates
            .iter()
            .find(|candidate| candidate.join(".git").exists())
            .cloned()
            .unwrap_or_else(|| {
                home::home_dir()
                    .unwrap_or_default()
                    .join(".keystone")
                    .join("repos")
                    .join(key)
            });

        if target.join(".git").exists() {
            eprintln!("Pulling {}...", key);
            if let Err(err) = git_pull_ff_with_upstream_repair(&target, key).await {
                eprintln!("Warning: failed to pull {}: {}", key, err);
            }
        } else {
            eprintln!("Cloning {}...", key);
            if let Some(parent) = target.parent() {
                let _ = tokio::fs::create_dir_all(parent).await;
            }
            let status = tokio::process::Command::new("git")
                .args(["clone", url])
                .arg(&target)
                .status()
                .await;
            if let Ok(status) = status {
                if !status.success() {
                    eprintln!("Warning: failed to clone {}", key);
                }
            }
        }
    }

    Ok(())
}

async fn verify_repo_lock_ready(path: &Path, name: &str) -> Result<()> {
    if !path.is_dir() {
        return Ok(());
    }

    let diff_status = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(path)
        .args(["diff", "--quiet"])
        .status()
        .await
        .context("Failed to check git diff")?;
    if !diff_status.success() {
        anyhow::bail!("{} has uncommitted changes at {}", name, path.display());
    }

    let staged_status = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(path)
        .args(["diff", "--cached", "--quiet"])
        .status()
        .await
        .context("Failed to check git staged changes")?;
    if !staged_status.success() {
        anyhow::bail!(
            "{} has staged uncommitted changes at {}",
            name,
            path.display()
        );
    }

    let head_state = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(path)
        .args(["symbolic-ref", "--quiet", "--short", "HEAD"])
        .output()
        .await
        .context("Failed to check HEAD state")?;
    if !head_state.status.success() {
        anyhow::bail!("{} is in detached HEAD state at {}", name, path.display());
    }

    Ok(())
}

async fn verify_all_repos_lock_ready(repo_root: &Path) -> Result<()> {
    let registry = repo::get_repos_registry(repo_root).await?;
    let obj = match registry.as_object() {
        Some(obj) => obj,
        None => return Ok(()),
    };

    for (key, _value) in obj {
        let candidates = repo_checkout_candidates(repo_root, key).await;
        if let Some(path) = candidates.iter().find(|candidate| candidate.is_dir()) {
            verify_repo_lock_ready(path, key).await?;
        }
    }

    Ok(())
}

async fn update_dev(repo_root: &Path, mode: &str, hosts: &[String]) -> Result<UpdateResult> {
    cmd::switch::execute(Some(&hosts.join(",")), mode == "boot", Some(repo_root)).await?;

    Ok(UpdateResult {
        hosts: hosts.to_vec(),
        dev: true,
        mode: mode.to_string(),
    })
}

async fn update_locked(repo_root: &Path, mode: &str, hosts: &[String]) -> Result<UpdateResult> {
    // Cache sudo credentials immediately — before any pull, lock, or build —
    // so the user is not interrupted after a long build phase.
    let _sudo_guard = cmd::switch::ensure_sudo(repo_root, hosts).await?;

    if let Err(err) = git_pull_ff_with_upstream_repair(repo_root, "nixos-config").await {
        eprintln!("Warning: failed to pull nixos-config: {}", err);
    }

    pull_managed_repos(repo_root).await?;
    verify_all_repos_lock_ready(repo_root).await?;

    let deploy_session = cmd::switch::prepare_deploy_session(repo_root, hosts).await?;
    let build_result =
        cmd::build::execute(Some(&hosts.join(",")), true, None, false, Some(repo_root)).await?;
    cmd::switch::deploy_paths_with_session(
        repo_root,
        &deploy_session,
        mode,
        hosts,
        &build_result.store_paths,
    )
    .await?;

    let push_status = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(repo_root)
        .arg("push")
        .status()
        .await;
    if let Ok(status) = push_status {
        if !status.success() {
            eprintln!("Warning: failed to push nixos-config");
        }
    }

    Ok(UpdateResult {
        hosts: hosts.to_vec(),
        dev: false,
        mode: mode.to_string(),
    })
}

pub async fn execute(
    hosts_arg: Option<&str>,
    dev: bool,
    boot: bool,
    pull_only: bool,
    flake_override: Option<&std::path::Path>,
) -> Result<UpdateResult> {
    let repo_root = repo::find_repo(flake_override)?;
    let hosts = repo::resolve_hosts(&repo_root, hosts_arg).await?;
    let mode = if boot { "boot" } else { "switch" };

    if pull_only {
        pull_managed_repos(&repo_root).await?;
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
