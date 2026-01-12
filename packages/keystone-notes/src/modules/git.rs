use anyhow::{Context, Result};
use tokio::process::Command;
use tracing::info;

pub struct GitWrapper;

impl GitWrapper {
    async fn run(args: &[&str]) -> Result<String> {
        let output = Command::new("git")
            .args(args)
            .output()
            .await
            .context(format!("Failed to run git {:?}", args))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            // If status is non-zero, we usually want to fail.
            // git status --porcelain returns 0 even if clean.
            // git diff returns 1 if differences found? No, git diff returns 0.
            // git diff --exit-code returns 1 if diff found.
            // Here we assume standard porcelain commands.
            anyhow::bail!("Git command failed: {:?} - {}", args, stderr);
        }
        
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    }

    pub async fn has_changes() -> Result<bool> {
        // git status --porcelain
        let output = Self::run(&["status", "--porcelain"]).await?;
        Ok(!output.is_empty())
    }
}

pub async fn sync() -> Result<()> {
    info!("Starting git sync...");
    
    // 1. Stash changes (if any)
    let has_local_changes = GitWrapper::has_changes().await?;
    let mut stashed = false;
    
    if has_local_changes {
        info!("Stashing local changes...");
        GitWrapper::run(&["stash"]).await?;
        stashed = true;
    }

    // 2. Pull --rebase
    info!("Pulling changes...");
    match GitWrapper::run(&["pull", "--rebase"]).await {
        Ok(_) => {},
        Err(e) => {
            if stashed {
                info!("Pull failed, popping stash...");
                let _ = GitWrapper::run(&["stash", "pop"]).await;
            }
            return Err(e);
        }
    }

    // 3. Pop stash
    if stashed {
        info!("Popping stash...");
        // pop can fail if conflicts, but we try
        GitWrapper::run(&["stash", "pop"]).await?;
    }

    // 4. Add .
    info!("Adding changes...");
    GitWrapper::run(&["add", "."]).await?;

    // Check if there are changes to commit
    if GitWrapper::has_changes().await? {
        // 5. Commit
        info!("Committing...");
        let msg = format!("Auto-sync: {}", chrono::Local::now().format("%Y-%m-%d %H:%M:%S"));
        GitWrapper::run(&["commit", "-m", &msg]).await?;

        // 6. Push
        info!("Pushing...");
        GitWrapper::run(&["push"]).await?;
    } else {
        info!("No changes to commit.");
    }

    info!("Sync complete.");
    Ok(())
}
