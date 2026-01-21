use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use anyhow::{Context, Result};
use tokio::fs;

#[derive(Debug, Deserialize, Serialize)]
pub struct Config {
    pub global: GlobalConfig,
    pub backends: Option<HashMap<String, BackendConfig>>,
    #[serde(default)]
    pub jobs: Vec<JobConfig>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct GlobalConfig {
    pub backend: String,
    pub model: Option<String>,
    #[serde(default)]
    pub use_mcp: bool,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(tag = "type")]
pub enum BackendConfig {
    #[serde(rename = "claude-code")]
    ClaudeCode { binary_path: Option<String> },
    #[serde(rename = "ollama")]
    Ollama { base_url: String, model: String },
    #[serde(rename = "gemini")]
    Gemini { binary_path: Option<String> },
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct JobConfig {
    pub name: String,
    pub schedule: String,
    pub script: String,
    pub backend: Option<String>,
    pub context_mode: Option<ContextMode>,
    pub context_lookback: Option<String>,
    pub output_path: Option<String>,
    pub output_mode: Option<OutputMode>,
}

#[derive(Debug, Deserialize, Serialize, Clone, Copy)]
#[serde(rename_all = "lowercase")]
pub enum ContextMode {
    Diff,
    Files,
}

#[derive(Debug, Deserialize, Serialize, Clone, Copy)]
#[serde(rename_all = "lowercase")]
pub enum OutputMode {
    Overwrite,
    Append,
}

impl Config {
    pub async fn load(path: impl AsRef<Path>) -> Result<Self> {
        let content = fs::read_to_string(path.as_ref())
            .await
            .context(format!("Failed to read config file at {:?}", path.as_ref()))?;
        
        let config: Config = toml::from_str(&content)
            .context("Failed to parse config file")?;
            
        Ok(config)
    }
}
