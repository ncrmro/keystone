//! ks
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

use anyhow::Result;
use clap::Parser;
use crossterm::event;
use ratatui::prelude::*;
use serde::Serialize;

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
use cli::{Cli, Command, HardwareKeyCommand};
use components::first_boot::FirstBootConfig;
use components::install::InstallerConfig;

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
            Command::Build {
                lock,
                user,
                all_users,
                hosts,
                json,
            } => run_build_command(hosts.as_deref(), lock, user.as_deref(), all_users, json).await,
            Command::Switch { boot, hosts, json } => {
                run_switch_command(hosts.as_deref(), boot, json).await
            }
            Command::Update {
                debug: _,
                dev,
                boot,
                pull,
                lock,
                user: _,
                all_users: _,
                hosts,
                json,
            } => {
                let dev_mode = dev && !lock;
                let pull_only = pull && dev_mode;
                run_update_command(hosts.as_deref(), dev_mode, boot, pull_only, json).await
            }
            Command::Approve(args) => run_approve_command(args).await,
            Command::Agents(args) => run_agents_command(args).await,
            Command::Docs { topic_or_path } => run_docs_command(topic_or_path).await,
            Command::Photos { command } => run_photos_command(command).await,
            Command::HardwareKey { command } => run_hardware_key_command(command).await,
            Command::Screenshots { command } => run_screenshots_command(command).await,
            Command::SyncAgentAssets => run_sync_agent_assets_command().await,
            Command::SyncHostKeys => run_sync_host_keys_command().await,
            Command::Grafana { args } => run_grafana_command(args).await,
            Command::Print { args } => run_print_command(args).await,
            Command::Agent(args) => run_agent_command(args).await,
            Command::Doctor(args) => run_doctor_command(args).await,
        };
    }

    if let Some(ref screen_name) = cli.screenshot {
        return run_screenshot_mode(screen_name).await;
    }

    tui::install_panic_hook();
    let mut terminal = tui::setup()?;

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

fn print_json_success<T: Serialize>(value: &T) -> Result<()> {
    println!(
        "{}",
        serde_json::to_string_pretty(&cmd::JsonOutput::ok(value))?
    );
    Ok(())
}

fn print_json_error(error: &anyhow::Error) -> Result<()> {
    println!(
        "{}",
        serde_json::to_string_pretty(&cmd::JsonError::new(error.to_string()))?
    );
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
                print_json_success(&result)
            } else {
                println!("Config generated (v{}):", result.config_version);
                for file in &result.files {
                    println!("  {}/{}", result.output_dir.display(), file);
                }
                Ok(())
            }
        }
        Err(e) => {
            if json {
                print_json_error(&e)
            } else {
                Err(e)
            }
        }
    }
}

/// Run the `build` subcommand.
async fn run_build_command(
    hosts: Option<&str>,
    lock: bool,
    user_filter: Option<&str>,
    all_users: bool,
    json: bool,
) -> Result<()> {
    match cmd::build::execute(hosts, lock, user_filter, all_users).await {
        Ok(result) => {
            if json {
                print_json_success(&result)
            } else {
                let mode = if result.lock {
                    "full system"
                } else {
                    "home-manager"
                };
                println!("Build complete ({}) for: {}", mode, result.hosts.join(", "));
                Ok(())
            }
        }
        Err(e) => {
            if json {
                print_json_error(&e)
            } else {
                Err(e)
            }
        }
    }
}

/// Run the `switch` subcommand.
async fn run_switch_command(hosts: Option<&str>, boot: bool, json: bool) -> Result<()> {
    match cmd::switch::execute(hosts, boot).await {
        Ok(result) => {
            if json {
                print_json_success(&result)
            } else {
                println!("Switch complete for: {}", result.hosts.join(", "));
                Ok(())
            }
        }
        Err(e) => {
            if json {
                print_json_error(&e)
            } else {
                Err(e)
            }
        }
    }
}

/// Run the `update` subcommand.
async fn run_update_command(
    hosts: Option<&str>,
    dev: bool,
    boot: bool,
    pull_only: bool,
    json: bool,
) -> Result<()> {
    match cmd::update::execute(hosts, dev, boot, pull_only).await {
        Ok(result) => {
            if json {
                print_json_success(&result)
            } else {
                let mode_label = if result.dev { "dev" } else { "lock" };
                println!(
                    "Update complete ({} mode) for: {}",
                    mode_label,
                    result.hosts.join(", ")
                );
                Ok(())
            }
        }
        Err(e) => {
            if json {
                print_json_error(&e)
            } else {
                Err(e)
            }
        }
    }
}

async fn run_docs_command(topic_or_path: Option<String>) -> Result<()> {
    cmd::docs::execute(topic_or_path.as_deref())
}

async fn run_photos_command(command: cmd::photos::PhotosCommand) -> Result<()> {
    cmd::photos::execute_command(command).await
}

async fn run_hardware_key_command(command: HardwareKeyCommand) -> Result<()> {
    match command {
        HardwareKeyCommand::Doctor { selector, json } => {
            match cmd::hardware_key::execute_doctor(selector.as_deref()).await {
                Ok(report) => {
                    if json {
                        print_json_success(&report)
                    } else {
                        cmd::hardware_key::render_doctor(&report)
                    }
                }
                Err(e) => {
                    if json {
                        print_json_error(&e)
                    } else {
                        Err(e)
                    }
                }
            }
        }
        HardwareKeyCommand::Secrets { json } => {
            match cmd::hardware_key::execute_secrets_todo().await {
                Ok(todo) => {
                    if json {
                        print_json_success(&todo)
                    } else {
                        cmd::hardware_key::render_secrets_todo(&todo)
                    }
                }
                Err(e) => {
                    if json {
                        print_json_error(&e)
                    } else {
                        Err(e)
                    }
                }
            }
        }
    }
}

async fn run_screenshots_command(command: cmd::screenshots::ScreenshotsCommand) -> Result<()> {
    cmd::screenshots::execute_command(command).await
}

async fn run_grafana_command(args: Vec<String>) -> Result<()> {
    cmd::grafana::execute(&args).await
}

async fn run_print_command(args: Vec<String>) -> Result<()> {
    cmd::print::execute(&args)
}

async fn run_approve_command(args: cli::ApproveArgs) -> Result<()> {
    cmd::approve::execute(&args.reason, &args.command)
}

async fn run_agents_command(args: cli::AgentsArgs) -> Result<()> {
    cmd::agents::execute(&args.action, &args.target, args.reason.as_deref())
}

async fn run_sync_agent_assets_command() -> Result<()> {
    cmd::sync_agent_assets::execute()
}

async fn run_sync_host_keys_command() -> Result<()> {
    let _ = cmd::sync_host_keys::execute().await?;
    Ok(())
}

async fn run_agent_command(args: cli::AgentArgs) -> Result<()> {
    cmd::agent::execute(args.local.as_deref(), &args.args).await
}

/// Run the `doctor` subcommand.
async fn run_doctor_command(args: cli::DoctorArgs) -> Result<()> {
    if !args.json {
        return cmd::doctor::render_and_maybe_launch(args.local.as_deref(), &args.args).await;
    }

    match cmd::doctor::execute().await {
        Ok(report) => print_json_success(&report),
        Err(e) => print_json_error(&e),
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
            AppScreen::Installer(ref mut installer) => installer.poll(),
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
