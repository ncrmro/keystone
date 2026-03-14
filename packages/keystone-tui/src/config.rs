use anyhow::{Context, Result};
use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::fs;

const CONFIG_FILE_NAME: &str = "config.toml";

/// Represents a managed Keystone repository.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KeystoneRepo {
    pub path: PathBuf,
}

/// Application configuration, stored in XDG config directory.
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct AppConfig {
    pub repos: Vec<KeystoneRepo>,
}

impl AppConfig {
    /// Returns the path to the configuration file.
    fn config_file_path() -> Result<PathBuf> {
        let project_dirs = ProjectDirs::from("com", "Keystone", "KeystoneTUI")
            .context("Failed to get project directories")?;
        let config_dir = project_dirs.config_dir();
        Ok(config_dir.join(CONFIG_FILE_NAME))
    }

    /// Loads the application configuration from the XDG config directory.
    pub async fn load() -> Result<Self> {
        let config_path = Self::config_file_path()?;
        if !config_path.exists() {
            return Ok(Self::default());
        }

        let config_content = fs::read_to_string(&config_path).await.context(format!(
            "Failed to read config file: {}",
            config_path.display()
        ))?;
        toml::from_str(&config_content).context("Failed to deserialize config.toml")
    }

    /// Saves the application configuration to the XDG config directory.
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
