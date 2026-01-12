use crate::modules::config::Config;
use crate::modules::systemd::SystemdManager;
use anyhow::{Context, Result};
use std::path::PathBuf;

pub async fn run(config_path: PathBuf) -> Result<()> {
    // 1. Locate config file
    let config_file = if config_path.is_dir() {
        config_path.join(".keystone/jobs.toml")
    } else {
        config_path
    };

    if !config_file.exists() {
        anyhow::bail!("Config file not found at {:?}", config_file);
    }

    // 2. Load config
    let config = Config::load(&config_file).await?;
    
    // 3. Init SystemdManager
    let systemd = SystemdManager::new()?;
    
    // 4. Get current executable path
    let current_exe = std::env::current_exe()?;
    let current_exe_str = current_exe.to_str().context("Invalid path for current executable")?;

    // 5. Install each job
    for job in config.jobs {
        println!("Installing job: {} ({})", job.name, job.schedule);
        systemd.install_job(&job, current_exe_str).await?;
        systemd.reload_and_enable(&job.name).await?;
    }
    
    println!("All jobs installed successfully.");
    Ok(())
}
