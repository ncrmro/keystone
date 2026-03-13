use std::path::PathBuf;

use crate::config::{AppConfig, KeystoneRepo};
use crate::nix;
use crate::repo;
use crate::screens::build::BuildScreen;
use crate::screens::create_config::CreateConfigScreen;
use crate::screens::host_detail::HostDetailScreen;
use crate::screens::hosts::HostsScreen;
use crate::screens::install::InstallScreen;
use crate::screens::welcome::WelcomeScreen;
use crate::system;

/// Represents the different screens/views in the TUI.
pub enum AppScreen {
    Welcome(WelcomeScreen),
    CreateConfig(CreateConfigScreen),
    Hosts(HostsScreen),
    HostDetail(HostDetailScreen),
    Build(BuildScreen),
    Install(InstallScreen),
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

    /// Load the hosts screen for a given repo with live dashboard polling.
    pub async fn load_hosts_screen(repo: &KeystoneRepo) -> anyhow::Result<HostsScreen> {
        let flake_info = nix::parse_flake(&repo.path).await?;

        // Build initial host statuses with local hostname detection
        let statuses = system::match_hosts_to_peers(&flake_info.hosts, None);
        let mut screen = HostsScreen::new_with_statuses(repo.name.clone(), statuses);

        // Start background polling for metrics and tailscale
        let rx = system::spawn_dashboard_poller();
        screen.set_channel(rx);

        Ok(screen)
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

    /// Create an App with a given config, starting on the Welcome screen.
    /// Skips filesystem operations (no `discover_repos`, no `AppConfig::load`).
    pub fn new_with_config(config: AppConfig) -> Self {
        let has_repos = !config.repos.is_empty();
        let current_screen = if has_repos {
            // Start on hosts with empty hosts list (no flake parsing)
            let name = config.repos[0].name.clone();
            AppScreen::Hosts(HostsScreen::new(name, Vec::new()))
        } else {
            AppScreen::Welcome(WelcomeScreen::new())
        };

        Self {
            should_quit: false,
            config,
            current_screen,
            active_repo_index: if has_repos { Some(0) } else { None },
        }
    }

    /// Create an App in installer mode — starts on the InstallScreen with
    /// pre-baked config from an ISO. Skips repo discovery and Welcome flow.
    pub fn new_for_installer(installer_config: crate::screens::install::InstallerConfig) -> Self {
        Self {
            should_quit: false,
            config: AppConfig::default(),
            current_screen: AppScreen::Install(InstallScreen::new(installer_config)),
            active_repo_index: None,
        }
    }

    /// Create a minimal App for testing — starts on Welcome with empty config.
    pub fn new_for_test() -> Self {
        Self::new_with_config(AppConfig::default())
    }

    pub async fn save_config(&self) {
        if let Err(e) = self.config.save().await {
            eprintln!("Failed to save config: {:?}", e);
        }
    }
}
