//! Keystone TUI
//!
//! Terminal user interface for Keystone NixOS infrastructure configuration
//! and management. Handles repo setup, secrets, key enrollment, host
//! configuration, building, and git operations.

#![allow(dead_code)]

use std::io;

use anyhow::Result;
use clap::Parser;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::prelude::*;

mod app;
mod config;
mod disk;
mod github;
mod input;
mod nix;
mod repo;
mod screens;
mod ssh_keys;
mod system;
mod template;
mod ui;

use app::{App, AppScreen};
use input::{dispatch_key, handle_action, AppAction};
use screens::first_boot::FirstBootConfig;
use screens::install::InstallerConfig;

/// Keystone TUI — NixOS infrastructure configuration and management.
#[derive(Parser)]
#[command(name = "keystone-tui", version, about)]
struct Cli {
    /// Generate config from JSON on stdin instead of launching the TUI.
    ///
    /// Expects a JSON object with fields: hostname, machine_type ("server"|"workstation"|"laptop"),
    /// storage_type ("zfs"|"ext4"), username, password, and optionally: disk_device, github_username,
    /// time_zone, state_version.
    #[arg(long)]
    json: bool,

    /// Render a single screen to stdout as ANSI and exit. No alternate screen, no raw mode.
    /// Useful for capturing screenshots with vhs or piping to ansi-to-image tools.
    ///
    /// Available screens: welcome, create-config, hosts, install
    #[arg(long, value_name = "SCREEN")]
    screenshot: Option<String>,
}

/// Set up the terminal for TUI rendering.
fn setup_terminal() -> Result<Terminal<CrosstermBackend<io::Stdout>>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let terminal = Terminal::new(backend)?;
    Ok(terminal)
}

/// Restore the terminal to its original state.
fn restore_terminal(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) -> Result<()> {
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    if cli.json {
        return run_json_mode().await;
    }

    if let Some(ref screen_name) = cli.screenshot {
        return run_screenshot_mode(screen_name).await;
    }

    // Set up panic hook to restore terminal on panic
    let original_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |panic_info| {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture);
        original_hook(panic_info);
    }));

    let mut terminal = setup_terminal()?;

    // Priority detection:
    // 1. Installer mode: pre-baked ISO with config at /etc/keystone/install-config/
    // 2. First-boot mode: freshly installed system with .first-boot-pending marker
    // 3. Normal mode: repo management dashboard
    let mut app = if let Some(installer_config) = InstallerConfig::detect() {
        App::new_for_installer(installer_config)
    } else if let Some(first_boot_config) = FirstBootConfig::detect() {
        App::new_for_first_boot(first_boot_config)
    } else {
        App::new().await
    };

    let result = run_app(&mut terminal, &mut app).await;

    restore_terminal(&mut terminal)?;

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
            let screen = screens::welcome::WelcomeScreen::new();
            terminal.draw(|frame| {
                screen.render(frame, frame.area());
            })?;
        }
        "create-config" => {
            let screen = screens::create_config::CreateConfigScreen::new("my-config".to_string());
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
                        screens::hosts::HostsScreen::new("keystone".to_string(), hosts);
                    terminal.draw(|frame| {
                        screen.render(frame, frame.area());
                    })?;
                }
                _ => {
                    // No repos found, show empty hosts
                    let mut screen =
                        screens::hosts::HostsScreen::new("keystone".to_string(), Vec::new());
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

        terminal.draw(|frame| {
            let area = frame.area();
            match &mut app.current_screen {
                AppScreen::Welcome(welcome_screen) => {
                    welcome_screen.render(frame, area);
                }
                AppScreen::CreateConfig(create_config_screen) => {
                    create_config_screen.render(frame, area);
                }
                AppScreen::Hosts(hosts_screen) => {
                    hosts_screen.render(frame, area);
                }
                AppScreen::HostDetail(detail_screen) => {
                    detail_screen.render(frame, area);
                }
                AppScreen::Build(build_screen) => {
                    build_screen.render(frame, area);
                }
                AppScreen::Iso(iso_screen) => {
                    iso_screen.render(frame, area);
                }
                AppScreen::Deploy(deploy_screen) => {
                    deploy_screen.render(frame, area);
                }
                AppScreen::Install(install_screen) => {
                    install_screen.render(frame, area);
                }
                AppScreen::FirstBoot(first_boot_screen) => {
                    first_boot_screen.render(frame, area);
                }
            }
        })?;

        if event::poll(std::time::Duration::from_millis(100))? {
            match event::read()? {
                Event::Key(key) => {
                    if let Some(action) = dispatch_key(app, key) {
                        match action {
                            AppAction::Quit => {
                                app.should_quit = true;
                            }
                            other => {
                                handle_action(app, other).await;
                            }
                        }
                    }
                }
                Event::Resize(_width, _height) => {}
                Event::Mouse(_mouse_event) => {}
                _ => {}
            }
        }

        if app.should_quit {
            break;
        }
    }

    Ok(())
}
