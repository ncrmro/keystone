use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use chrono::{DateTime, Utc};
use sha2::{Sha256, Digest};
use tokio::fs;
use anyhow::{Context, Result};

#[derive(Debug, Deserialize, Serialize, Default)]
pub struct TrustStore {
    pub scripts: HashMap<String, TrustEntry>, // Key: Absolute Path
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct TrustEntry {
    pub hash: String, // SHA-256
    pub allowed_at: DateTime<Utc>,
}

pub struct TrustManager {
    store_path: PathBuf,
    store: TrustStore,
}

impl TrustManager {
    pub async fn new() -> Result<Self> {
        let home = dirs::home_dir().context("Could not find home directory")?;
        let store_path = home.join(".local/share/keystone/script_allowlist.json");
        
        let store = if store_path.exists() {
            let content = fs::read_to_string(&store_path).await?;
            serde_json::from_str(&content).unwrap_or_default()
        } else {
            TrustStore::default()
        };

        Ok(Self {
            store_path,
            store,
        })
    }

    pub async fn with_path(store_path: PathBuf) -> Result<Self> {
        let store = if store_path.exists() {
            let content = fs::read_to_string(&store_path).await?;
            serde_json::from_str(&content).unwrap_or_default()
        } else {
            TrustStore::default()
        };

        Ok(Self {
            store_path,
            store,
        })
    }

    pub async fn is_allowed(&self, script_path: &Path) -> Result<bool> {
        let abs_path = if script_path.is_absolute() {
            script_path.to_path_buf()
        } else {
            script_path.canonicalize().context("Failed to canonicalize script path")?
        };
        
        let path_str = abs_path.to_string_lossy().to_string();

        if let Some(entry) = self.store.scripts.get(&path_str) {
            let current_hash = Self::hash_file(&abs_path).await?;
            Ok(current_hash == entry.hash)
        } else {
            Ok(false)
        }
    }

    pub async fn approve(&mut self, script_path: &Path) -> Result<()> {
        let abs_path = if script_path.is_absolute() {
            script_path.to_path_buf()
        } else {
            script_path.canonicalize().context("Failed to canonicalize script path")?
        };
        
        let path_str = abs_path.to_string_lossy().to_string();
        let hash = Self::hash_file(&abs_path).await?;

        self.store.scripts.insert(path_str, TrustEntry {
            hash,
            allowed_at: Utc::now(),
        });

        self.save().await?;
        Ok(())
    }

    async fn save(&self) -> Result<()> {
        if let Some(parent) = self.store_path.parent() {
            fs::create_dir_all(parent).await?;
        }
        let content = serde_json::to_string_pretty(&self.store)?;
        fs::write(&self.store_path, content).await?;
        Ok(())
    }

    async fn hash_file(path: &Path) -> Result<String> {
        let content = fs::read(path).await?;
        let mut hasher = Sha256::new();
        hasher.update(&content);
        let result = hasher.finalize();
        Ok(hex::encode(result))
    }
}
