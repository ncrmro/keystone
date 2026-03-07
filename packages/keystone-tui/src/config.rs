use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct TemplateConfig {
    pub hostname: String,
    pub host_id: String,
    pub state_version: String,
    pub time_zone: Option<String>,
    pub storage: StorageConfig,
    #[serde(default = "default_true")]
    pub secure_boot: Option<bool>,
    #[serde(default = "default_true")]
    pub tpm: Option<bool>,
    #[serde(default)]
    pub remote_unlock: Option<RemoteUnlockConfig>,
    pub users: HashMap<String, UserConfig>,
}

fn default_true() -> Option<bool> {
    Some(true)
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct StorageConfig {
    #[serde(rename = "type")]
    pub storage_type: StorageType,
    pub devices: Vec<String>,
    #[serde(default)]
    pub mode: Option<StorageMode>,
    #[serde(default = "default_swap_size")]
    pub swap_size: Option<String>,
    #[serde(default)]
    pub hibernate: Option<bool>,
}

fn default_swap_size() -> Option<String> {
    Some("16G".to_string())
}

#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum StorageType {
    Zfs,
    Ext4,
}

#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum StorageMode {
    Single,
    Mirror,
    Stripe,
    Raidz1,
    Raidz2,
    Raidz3,
}

impl Default for StorageMode {
    fn default() -> Self {
        Self::Single
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct RemoteUnlockConfig {
    pub enable: bool,
    pub authorized_keys: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UserConfig {
    pub full_name: String,
    pub email: Option<String>,
    #[serde(flatten)]
    pub auth: UserAuth,
    #[serde(default)]
    pub authorized_keys: Vec<String>,
    #[serde(default = "default_extra_groups")]
    pub extra_groups: Vec<String>,
    #[serde(default = "default_true")]
    pub terminal: Option<bool>,
    #[serde(default)]
    pub desktop: Option<DesktopConfig>,
}

fn default_extra_groups() -> Vec<String> {
    vec!["wheel".to_string()]
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub enum UserAuth {
    InitialPassword(String),
    HashedPassword(String),
}

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct DesktopConfig {
    pub enable: bool,
    #[serde(default)]
    pub hyprland: Option<HyprlandConfig>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct HyprlandConfig {
    #[serde(default = "default_modifier_key")]
    pub modifier_key: String,
}

fn default_modifier_key() -> String {
    "SUPER".to_string()
}

impl Default for HyprlandConfig {
    fn default() -> Self {
        Self {
            modifier_key: default_modifier_key(),
        }
    }
}
