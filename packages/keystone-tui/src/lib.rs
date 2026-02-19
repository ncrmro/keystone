pub mod app;
pub mod config;
pub mod screens;

use anyhow::{Context, Result};
use home::home_dir;
use tokio::fs;

use crate::config::KeystoneRepo;

pub async fn import_repo(repo_name: String, git_url: String) -> Result<KeystoneRepo> {
    let home_dir = home_dir().context("Failed to get home directory")?;
    let repos_dir = home_dir.join(".keystone").join("repos");
    fs::create_dir_all(&repos_dir)
        .await
        .context("Failed to create ~/.keystone/repos directory")?;

    let target_path = repos_dir.join(&repo_name);

    if target_path.exists() {
        anyhow::bail!(
            "Repository directory already exists: {}",
            target_path.display()
        );
    }

    // git2::Repository::clone does not have an async version, so we run it in a tokio blocking thread.
    let repo_path = tokio::task::spawn_blocking(move || {
        git2::Repository::clone(&git_url, &target_path)
            .map(|repo| repo.path().to_path_buf()) // This returns the .git path, not the worktree path.
            .context(format!("Failed to clone repository from {}", git_url))
    })
    .await
    .context("Failed to spawn blocking task for git clone")??;

    // The repo_path returned by git2::Repository::clone().path() is the path to the .git directory.
    // We want the worktree path, which is the parent of the .git directory.
    let actual_repo_path = repo_path
        .parent()
        .context("Cloned repository path has no parent directory")?
        .to_path_buf();

    Ok(KeystoneRepo {
        name: repo_name,
        path: actual_repo_path,
    })
}

pub async fn create_new_repo(repo_name: String) -> Result<KeystoneRepo> {
    let home_dir = home_dir().context("Failed to get home directory")?;
    let repos_dir = home_dir.join(".keystone").join("repos");
    fs::create_dir_all(&repos_dir)
        .await
        .context("Failed to create ~/.keystone/repos directory")?;

    let target_path = repos_dir.join(&repo_name);

    if target_path.exists() {
        anyhow::bail!(
            "Repository directory already exists: {}",
            target_path.display()
        );
    }

    // Create the directory for the new flake
    fs::create_dir(&target_path).await.context(format!(
        "Failed to create directory for new repo: {}",
        target_path.display()
    ))?;

    // Execute 'nix flake init -t github:ncrmro/keystone'
    let output = tokio::process::Command::new("nix")
        .arg("flake")
        .arg("init")
        .arg("-t")
        .arg("github:ncrmro/keystone")
        .current_dir(&target_path) // Run the command in the newly created directory
        .output()
        .await
        .context("Failed to execute nix flake init command")?;

    if !output.status.success() {
        anyhow::bail!(
            "nix flake init failed: {}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }

    Ok(KeystoneRepo {
        name: repo_name.clone(), // Clone since we used it for path creation
        path: target_path,
    })
}
