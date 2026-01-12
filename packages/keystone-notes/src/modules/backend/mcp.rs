use anyhow::{Context, Result};
use tokio::process::Command;
use std::process::Stdio;
use tokio::io::AsyncWriteExt;

pub struct MCPClient {
    binary_path: String,
    args: Vec<String>,
}

impl MCPClient {
    pub fn new(binary_path: String, args: Vec<String>) -> Self {
        Self { binary_path, args }
    }

    pub async fn call(&self, input: &str) -> Result<String> {
        let mut child = Command::new(&self.binary_path)
            .args(&self.args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped()) // Capture stderr too?
            .spawn()
            .context(format!("Failed to spawn {}", self.binary_path))?;

        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(input.as_bytes()).await?;
        }

        let output = child.wait_with_output().await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            anyhow::bail!("Process failed with {}: {}", output.status, stderr);
        }

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        Ok(stdout)
    }
}
