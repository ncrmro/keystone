use anyhow::{Context, Result};
use chrono::Local;
use std::path::Path;
use tokio::fs;
use tokio::process::Command;

pub async fn run() -> Result<()> {
    // 1. Calculate path: current_dir/daily/YYYY-MM-DD.md
    let now = Local::now();
    let filename = format!("{}.md", now.format("%Y-%m-%d"));
    let daily_dir = Path::new("daily");
    let file_path = daily_dir.join(&filename);
    
    // 2. Ensure daily/ exists
    if !daily_dir.exists() {
        fs::create_dir_all(daily_dir).await.context("Failed to create daily directory")?;
    }
    
    // 3. Create file if not exists
    if !file_path.exists() {
        let title = format!("# Daily Note: {}\n\n", now.format("%Y-%m-%d"));
        fs::write(&file_path, title).await.context("Failed to create daily note")?;
    }
    
    // 4. Open in EDITOR
    let editor = std::env::var("EDITOR").unwrap_or_else(|_| "nano".to_string());
    
    // Check if EDITOR string has arguments (e.g. "code --wait")
    let parts: Vec<&str> = editor.split_whitespace().collect();
    let (cmd, args) = parts.split_first().unwrap();

    let mut command = Command::new(cmd);
    command.args(args);
    command.arg(&file_path);

    // We need to inherit stdio for interactive editor
    command.stdin(std::process::Stdio::inherit())
           .stdout(std::process::Stdio::inherit())
           .stderr(std::process::Stdio::inherit());

    let status = command.status() 
        .await
        .context(format!("Failed to launch editor {}", editor))?;
        
    if !status.success() {
        anyhow::bail!("Editor exited with error");
    }
    
    Ok(())
}