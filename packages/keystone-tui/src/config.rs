use anyhow::{Context, Result};
use home::home_dir;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::fs;

const CONFIG_FILE_NAME: &str = "keystone.json";

/// Represents a managed Keystone repository.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KeystoneRepo {
    pub name: String,
    pub path: PathBuf,
}

/// Application configuration, stored in ~/.keystone/keystone.json.
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct AppConfig {
    pub repos: Vec<KeystoneRepo>,
}

impl AppConfig {
    /// Returns the path to the configuration file.
    fn config_file_path() -> Result<PathBuf> {
        let home_dir = home_dir().context("Failed to get home directory")?;
        let keystone_dir = home_dir.join(".keystone");
        Ok(keystone_dir.join(CONFIG_FILE_NAME))
    }

    /// Loads the application configuration from ~/.keystone/keystone.json.
    pub async fn load() -> Result<Self> {
        let config_path = Self::config_file_path()?;
        if !config_path.exists() {
            return Ok(Self::default());
        }

        let config_content = fs::read_to_string(&config_path).await.context(format!(
            "Failed to read config file: {}",
            config_path.display()
        ))?;
        serde_json::from_str(&config_content).context("Failed to deserialize keystone.json")
    }

    /// Saves the application configuration to ~/.keystone/keystone.json.
    pub async fn save(&self) -> Result<()> {
        let config_path = Self::config_file_path()?;
        let config_dir = config_path
            .parent()
            .context("Config path has no parent directory")?;

        fs::create_dir_all(config_dir).await.context(format!(
            "Failed to create config directory: {}",
            config_dir.display()
        ))?;

        let config_content =
            serde_json::to_string_pretty(self).context("Failed to serialize config to JSON")?;
        fs::write(&config_path, config_content)
            .await
            .context(format!(
                "Failed to write config file: {}",
                config_path.display()
            ))?;
        Ok(())
    }
}
