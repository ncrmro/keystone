use crate::modules::backend::Backend;
use crate::modules::config::JobConfig;
use crate::modules::context::ContextBuilder;
use crate::modules::trust::TrustManager;
use anyhow::{Context, Result};
use std::path::Path;
use tokio::process::Command;
use tracing::info;

pub struct AgentRunner {
    backend: Box<dyn Backend>,
}

impl AgentRunner {
    pub fn new(backend: Box<dyn Backend>) -> Self {
        Self { backend }
    }

    pub async fn run_job(&self, job: &JobConfig) -> Result<String> {
        info!("Running job: {}", job.name);

        // 1. Build Context
        let context = if let Some(mode) = job.context_mode {
            info!("Building context...");
            ContextBuilder::build(mode, job.context_lookback.as_deref()).await?
        } else {
            String::new()
        };

        // 2. Prepare Prompt
        let mut prompt_part = format!("Task: {}\n", job.name);

        // Handle Script Execution
        if !job.script.starts_with("builtin:") {
            let script_path = Path::new(&job.script);
            if script_path.exists() {
                // Check trust
                let trust = TrustManager::new().await?;
                if !trust.is_allowed(script_path).await? {
                    anyhow::bail!(
                        "Script {:?} is not allowed. Run 'keystone-notes allow {:?}' to approve it.",
                        script_path,
                        script_path
                    );
                }

                // Execute script and capture output
                info!("Executing script {:?}", script_path);
                let output = Command::new(script_path)
                    .output()
                    .await
                    .context(format!("Failed to execute script {:?}", script_path))?;

                if !output.status.success() {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    anyhow::bail!("Script execution failed: {}", stderr);
                }

                let script_output = String::from_utf8_lossy(&output.stdout).to_string();
                prompt_part.push_str("\nScript Output:\n");
                prompt_part.push_str(&script_output);
            } else {
                // Treat as literal prompt? Or error if it looks like a file path?
                // For safety, if it contains slash, it's a file.
                if job.script.contains('/') {
                    anyhow::bail!("Script file {:?} not found", script_path);
                }
                prompt_part.push_str("\nInstruction: ");
                prompt_part.push_str(&job.script);
            }
        } else {
            prompt_part.push_str("\nInstruction: ");
            prompt_part.push_str(&job.script);
        }

        let full_prompt = format!("{}\n\nContext:\n{}", prompt_part, context);

        // 3. Call Backend
        info!("Calling backend...");
        let result = self.backend.generate(&full_prompt).await?;

        // 4. Handle Output
        if let Some(output_path_template) = &job.output_path {
            let now = chrono::Local::now();
            let output_path = now.format(output_path_template).to_string();
            let path = Path::new(&output_path);

            if let Some(parent) = path.parent() {
                tokio::fs::create_dir_all(parent).await?;
            }

            let mode = job
                .output_mode
                .unwrap_or(crate::modules::config::OutputMode::Overwrite);

            match mode {
                crate::modules::config::OutputMode::Overwrite => {
                    info!("Writing result to {:?}", path);
                    tokio::fs::write(path, &result).await?;
                }
                crate::modules::config::OutputMode::Append => {
                    info!("Appending result to {:?}", path);
                    use tokio::io::AsyncWriteExt;
                    let mut file = tokio::fs::OpenOptions::new()
                        .create(true)
                        .append(true)
                        .open(path)
                        .await?;
                    file.write_all(b"\n").await?;
                    file.write_all(result.as_bytes()).await?;
                }
            }
        }

        Ok(result)
    }
}