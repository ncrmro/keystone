use crate::modules::config::{Config, BackendConfig};
use crate::modules::backend::{Backend, claude::ClaudeCodeBackend, gemini::GeminiBackend, ollama::OllamaBackend};
use crate::modules::runner::AgentRunner;
use crate::modules::git;
use anyhow::{Context, Result};

pub async fn run(job_name: String) -> Result<()> {
    // 1. Load config
    let config_path = std::path::Path::new(".keystone/jobs.toml");
    let config = Config::load(config_path).await?;
    
    // 2. Find job
    let job = config.jobs.iter().find(|j| j.name == job_name)
        .context(format!("Job {} not found", job_name))?;
        
    // 3. Check for builtin jobs
    if job.script == "builtin:sync" {
        git::sync().await?;
        return Ok(());
    }
    
    // 4. Init Backend
    let backend_name = job.backend.as_deref().unwrap_or(&config.global.backend);
    
    let backend: Box<dyn Backend> = match backend_name {
        "claude-code" => {
            let binary_path = if let Some(backends) = &config.backends {
                if let Some(BackendConfig::ClaudeCode { binary_path }) = backends.get("claude-code") {
                    binary_path.clone()
                } else { None }
            } else { None };
            Box::new(ClaudeCodeBackend::new(binary_path))
        },
        "gemini" => {
            let binary_path = if let Some(backends) = &config.backends {
                if let Some(BackendConfig::Gemini { binary_path }) = backends.get("gemini") {
                    binary_path.clone()
                } else { None }
            } else { None };
            Box::new(GeminiBackend::new(binary_path))
        },
        "ollama" => {
             let (base_url, model) = if let Some(backends) = &config.backends {
                if let Some(BackendConfig::Ollama { base_url, model }) = backends.get("ollama") {
                    (base_url.clone(), model.clone())
                } else { 
                    ("http://localhost:11434".to_string(), "llama3".to_string())
                }
            } else { 
                ("http://localhost:11434".to_string(), "llama3".to_string())
            };
            Box::new(OllamaBackend::new(base_url, model))
        },
        _ => anyhow::bail!("Unsupported backend: {}", backend_name),
    };
    
    // 5. Run Job
    let runner = AgentRunner::new(backend);
    let result = runner.run_job(job).await?;
    
    println!("Job Result:\n{}", result);
    
    Ok(())
}