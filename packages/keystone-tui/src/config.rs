use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::fs;

const CONFIG_FILE_NAME: &str = "config.toml";

/// Represents a managed Keystone repository.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KeystoneRepo {
    pub path: PathBuf,
}

/// Application configuration stored at `~/.keystone/config.toml`.
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct AppConfig {
    pub repos: Vec<KeystoneRepo>,
}

impl AppConfig {
    /// Returns the path to the configuration file (`~/.keystone/config.toml`).
    fn config_file_path() -> Result<PathBuf> {
        let home = dirs::home_dir().context("Failed to determine home directory")?;
        Ok(home.join(".keystone").join(CONFIG_FILE_NAME))
    }

    /// Loads the application configuration from `~/.keystone/`.
    pub async fn load() -> Result<Self> {
        let config_path = Self::config_file_path()?;
        match fs::read_to_string(&config_path).await {
            Ok(content) => toml::from_str(&content).context("Failed to deserialize config.toml"),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(e) => Err(anyhow::anyhow!(
                "Failed to read config file {}: {}",
                config_path.display(),
                e
            )),
        }
    }

    /// Saves the application configuration to `~/.keystone/`.
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
            toml::to_string_pretty(self).context("Failed to serialize config to TOML")?;
        fs::write(&config_path, config_content)
            .await
            .context(format!(
                "Failed to write config file: {}",
                config_path.display()
            ))?;
        Ok(())
    }
}
