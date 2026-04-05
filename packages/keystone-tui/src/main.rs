//! Keystone TUI
//!
//! Terminal user interface for Keystone NixOS infrastructure configuration
//! and management. Handles repo setup, secrets, key enrollment, host
//! configuration, building, and git operations.

#![allow(dead_code)]
#![warn(clippy::correctness)]
#![warn(clippy::suspicious)]
#![warn(clippy::complexity)]
#![warn(clippy::perf)]
#![warn(clippy::style)]
#![warn(clippy::cognitive_complexity)]

use std::io;

use anyhow::{anyhow, Result};
use clap::Parser;
use crossterm::event;
use ratatui::prelude::*;

mod action;
mod app;
mod cli;
pub mod cmd;
mod component;
mod components;
mod config;
mod disk;
mod github;
mod nix;
mod repo;
mod ssh_keys;
mod system;
mod template;
mod theme;
mod tui;
mod widgets;

use app::{App, AppScreen};
use cli::{Cli, Command};
use components::first_boot::FirstBootConfig;
use components::install::InstallerConfig;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LaunchMode {
    Auto,
    InstallOnly,
}
#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Route subcommands
    if let Some(command) = cli.command {
        return match command {
            Command::Template {
                github_username,
                output,
                json,
            } => run_template_command(github_username, output, json).await,
        };
    }

    // Legacy --json flag (compat alias for `template --json`)
    if cli.json {
        return run_json_mode().await;
    }
    let launch_mode = if cli.install {
        LaunchMode::InstallOnly
    } else {
        LaunchMode::Auto
    };

    if let Some(ref screen_name) = cli.screenshot {
        return run_screenshot_mode(screen_name).await;
    }

    tui::install_panic_hook();
    let mut terminal = tui::setup()?;

    // Priority detection:
    // 1. Installer mode: embedded install repo or legacy config bundle
    // 2. First-boot mode: freshly installed system with .first-boot-pending marker
    // 3. Normal mode: repo management dashboard
    let mut app = match launch_mode {
        LaunchMode::InstallOnly => {
            let installer_config = InstallerConfig::detect()?.ok_or_else(|| {
                anyhow!(
                    "Installer data not found at /etc/keystone/install-repo or /etc/keystone/install-config; cannot run --install mode"
                )
            })?;
            App::new_for_installer(installer_config)
        }
        LaunchMode::Auto => {
            if let Some(installer_config) = InstallerConfig::detect()? {
                App::new_for_installer(installer_config)
            } else if let Some(first_boot_config) = FirstBootConfig::detect() {
                App::new_for_first_boot(first_boot_config)
            } else {
                App::new().await
            }
        }
    };

    let result = run_app(&mut terminal, &mut app).await;

    tui::restore(&mut terminal)?;

    app.save_config().await;

    result
}

/// Render a single screen to stdout as ANSI and exit.
///
/// Does NOT enter alternate screen or raw mode — the output goes directly to stdout
/// so vhs, `ansi2image`, or terminal capture tools can record it.
async fn run_screenshot_mode(screen_name: &str) -> Result<()> {
    use crossterm::terminal::size;
    use ratatui::backend::CrosstermBackend;

    let _ = size().unwrap_or((120, 40));

    let backend = CrosstermBackend::new(io::stdout());
    let mut terminal = Terminal::new(backend)?;

    // Force a full-screen clear so ratatui writes every cell on the first draw.
    // Without this, ratatui only writes "changed" cells via cursor positioning,
    // which leaves sparse screens (like welcome) invisible to vhs/ttyd.
    terminal.clear()?;

    // Build the screen to render
    match screen_name {
        "welcome" => {
            let screen = components::welcome::WelcomeScreen::new();
            terminal.draw(|frame| {
                screen.render(frame, frame.area());
            })?;
        }
        "create-config" => {
            let screen = components::template::CreateConfigScreen::new("my-config".to_string());
            terminal.draw(|frame| {
                screen.render(frame, frame.area());
            })?;
        }
        "hosts" => {
            let app = App::new().await;
            match &app.current_screen {
                AppScreen::Hosts(hosts_screen) => {
                    // Need a mutable reference, so clone the data
                    let hosts: Vec<crate::nix::HostInfo> =
                        hosts_screen.hosts().into_iter().cloned().collect();
                    let mut screen =
                        components::hosts::HostsScreen::new("keystone".to_string(), hosts);
                    terminal.draw(|frame| {
                        screen.render(frame, frame.area());
                    })?;
                }
                _ => {
                    // No repos found, show empty hosts
                    let mut screen =
                        components::hosts::HostsScreen::new("keystone".to_string(), Vec::new());
                    terminal.draw(|frame| {
                        screen.render(frame, frame.area());
                    })?;
                }
            }
        }
        other => {
            anyhow::bail!(
                "Unknown screen '{}'. Available: welcome, create-config, hosts",
                other
            );
        }
    }

    // Move cursor below the rendered content so the shell prompt doesn't overwrite it
    println!();

    Ok(())
}

/// Non-interactive JSON mode: read config from stdin, generate files, print output path.
async fn run_json_mode() -> Result<()> {
    let input = io::read_to_string(io::stdin())?;
    let json: serde_json::Value = serde_json::from_str(&input)?;

    let hostname = json["hostname"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing 'hostname' field"))?
        .to_string();

    let machine_type = match json["machine_type"].as_str().unwrap_or("server") {
        "workstation" => template::MachineType::Workstation,
        "laptop" => template::MachineType::Laptop,
        _ => template::MachineType::Server,
    };

    let storage_type = match json["storage_type"].as_str().unwrap_or("zfs") {
        "ext4" => template::StorageType::Ext4,
        _ => template::StorageType::Zfs,
    };

    let username = json["username"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing 'username' field"))?
        .to_string();

    let password = json["password"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing 'password' field"))?
        .to_string();

    let disk_device = json["disk_device"].as_str().map(|s| s.to_string());
    let github_username = json["github_username"].as_str().map(|s| s.to_string());
    let time_zone = json["time_zone"].as_str().unwrap_or("UTC").to_string();
    let state_version = json["state_version"]
        .as_str()
        .unwrap_or("25.05")
        .to_string();

    // Fetch GitHub SSH keys if username provided
    let authorized_keys = if let Some(ref gh) = github_username {
        github::fetch_ssh_keys(gh).await.unwrap_or_default()
    } else {
        Vec::new()
    };

    // Also detect local SSH keys
    let mut all_keys = authorized_keys;
    all_keys.extend(ssh_keys::detect_local_ssh_keys());

    let repo = repo::create_new_repo_from_config(
        hostname.clone(),
        machine_type,
        hostname,
        storage_type,
        disk_device,
        username,
        password,
        github_username,
        all_keys,
        Some(time_zone),
        Some(state_version),
    )
    .await?;

    println!("{}", repo.path.display());
    Ok(())
}

/// Run the `template` subcommand.
async fn run_template_command(
    github_username: Option<String>,
    output: Option<String>,
    json: bool,
) -> Result<()> {
    let params = if json {
        // JSON mode: read params from stdin
        let input = io::read_to_string(io::stdin())?;
        let mut params: cmd::TemplateParams = serde_json::from_str(&input)?;
        if github_username.is_some() {
            params.github_username = github_username;
        }
        if output.is_some() {
            params.output = output;
        }
        params
    } else {
        // Interactive CLI mode
        let mut params = cmd::TemplateParams::from_interactive(github_username.as_deref())?;
        if let Some(ref gh) = github_username {
            params.github_username = Some(gh.clone());
        }
        if output.is_some() {
            params.output = output;
        }
        params
    };

    match cmd::run_template(params).await {
        Ok(result) => {
            if json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&cmd::JsonOutput::ok(&result))?
                );
            } else {
                println!("Config generated (v{}):", result.config_version);
                for file in &result.files {
                    println!("  {}/{}", result.output_dir.display(), file);
                }
            }
            Ok(())
        }
        Err(e) => {
            if json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&cmd::JsonError::new(e.to_string()))?
                );
                Ok(())
            } else {
                Err(e)
            }
        }
    }
}

/// Handle a global Action from a Component.
///
/// TODO: once all screens implement Component, this replaces handle_action entirely.
async fn handle_component_action(app: &mut App, action: crate::action::Action) {
    use crate::action::Action;
    match action {
        Action::Quit => app.should_quit = true,
        Action::NavigateTo(screen) => app.navigate_to(screen).await,
        Action::GoBack | Action::RefreshDashboard => {
            app.go_to_hosts(app.active_repo_index.unwrap_or(0)).await;
        }
        Action::Reboot => {
            let _ = std::process::Command::new("systemctl")
                .arg("reboot")
                .spawn();
        }
        Action::Tick | Action::Render => {}
    }
}

/// Handle pending async operations from Component screens.
async fn handle_pending_async(app: &mut App) {
    if let AppScreen::Welcome(ref mut welcome) = app.current_screen {
        if let Some((name, git_url)) = welcome.take_pending_import() {
            match crate::repo::import_repo(name.clone(), git_url).await {
                Ok(repo) => {
                    app.config.repos.push(repo);
                    welcome.set_success(format!("Imported repository: {}", name));
                }
                Err(e) => {
                    welcome.set_error(format!("Failed to import: {}", e));
                }
            }
        }
    }
}

/// Main application loop. Generic over backend so tests can use TestBackend.
async fn run_app<B: Backend>(terminal: &mut Terminal<B>, app: &mut App) -> Result<()> {
    loop {
        // Poll active screens for async updates before rendering
        match &mut app.current_screen {
            AppScreen::Build(ref mut build) => build.poll(),
            AppScreen::Iso(ref mut iso) => iso.poll(),
            AppScreen::Deploy(ref mut deploy) => deploy.poll(),
            AppScreen::Hosts(ref mut hosts) => hosts.poll(),
            AppScreen::Install(ref mut install) => install.poll(),
            AppScreen::FirstBoot(ref mut first_boot) => first_boot.poll(),
            _ => {}
        }

        // Draw: try Component trait first, fall back to legacy render
        terminal.draw(|frame| {
            let area = frame.area();
            if let Some(component) = app.current_screen.as_component_mut() {
                let _ = component.draw(frame, area);
            } else {
                // Unreachable — all screens implement Component.
                // Kept for exhaustiveness until we replace AppScreen with Box<dyn Component>.
                unreachable!("all screens implement Component")
            }
        })?;

        if event::poll(std::time::Duration::from_millis(100))? {
            let terminal_event = event::read()?;

            // All screens implement Component — dispatch via trait
            if let Some(component) = app.current_screen.as_component_mut() {
                if let Ok(Some(action)) = component.handle_events(&terminal_event) {
                    handle_component_action(app, action).await;
                }
            }

            handle_pending_async(app).await;
        }

        if app.should_quit {
            break;
        }
    }

    Ok(())
}
