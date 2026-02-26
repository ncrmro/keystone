use std::path::PathBuf;

use crate::config::{AppConfig, KeystoneRepo};
use crate::nix;
use crate::repo;
use crate::screens::build::BuildScreen;
use crate::screens::host_detail::HostDetailScreen;
use crate::screens::hosts::HostsScreen;
use crate::screens::welcome::WelcomeScreen;

/// Represents the different screens/views in the TUI.
pub enum AppScreen {
    Welcome(WelcomeScreen),
    Hosts(HostsScreen),
    HostDetail(HostDetailScreen),
    Build(BuildScreen),
}

/// Application state for the Keystone TUI.
pub struct App {
    pub should_quit: bool,
    pub config: AppConfig,
    pub current_screen: AppScreen,
    /// Index of the currently active repo in config.repos
    pub active_repo_index: Option<usize>,
}

impl App {
    pub async fn new() -> Self {
        let mut config = AppConfig::load().await.unwrap_or_else(|e| {
            eprintln!("Failed to load config: {:?}", e);
            AppConfig::default()
        });

        // Discover repos on disk and merge any that aren't in config
        if let Ok(discovered) = repo::discover_repos().await {
            for repo in discovered {
                if !config.repos.iter().any(|r| r.path == repo.path) {
                    config.repos.push(repo);
                }
            }
        }

        let (current_screen, active_repo_index) = if config.repos.is_empty() {
            (AppScreen::Welcome(WelcomeScreen::new()), None)
        } else {
            // Use the first repo as default
            let repo = &config.repos[0];
            match Self::load_hosts_screen(repo).await {
                Ok(screen) => (AppScreen::Hosts(screen), Some(0)),
                Err(_e) => {
                    // Failed to parse flake, show hosts screen with empty hosts
                    let screen = HostsScreen::new(repo.name.clone(), Vec::new());
                    (AppScreen::Hosts(screen), Some(0))
                }
            }
        };

        Self {
            should_quit: false,
            config,
            current_screen,
            active_repo_index,
        }
    }

    /// Load the hosts screen for a given repo.
    pub async fn load_hosts_screen(repo: &KeystoneRepo) -> anyhow::Result<HostsScreen> {
        let flake_info = nix::parse_flake(&repo.path).await?;
        Ok(HostsScreen::new(repo.name.clone(), flake_info.hosts))
    }

    /// Transition to the hosts screen for a repo.
    pub async fn go_to_hosts(&mut self, repo_index: usize) {
        if let Some(repo) = self.config.repos.get(repo_index) {
            match Self::load_hosts_screen(repo).await {
                Ok(screen) => {
                    self.current_screen = AppScreen::Hosts(screen);
                    self.active_repo_index = Some(repo_index);
                }
                Err(e) => {
                    eprintln!("Failed to load hosts: {:?}", e);
                }
            }
        }
    }

    /// Get the path of the currently active repo.
    pub fn active_repo_path(&self) -> Option<PathBuf> {
        self.active_repo_index
            .and_then(|i| self.config.repos.get(i))
            .map(|r| r.path.clone())
    }

    pub async fn save_config(&self) {
        if let Err(e) = self.config.save().await {
            eprintln!("Failed to save config: {:?}", e);
        }
    }
}
