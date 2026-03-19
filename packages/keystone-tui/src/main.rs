//! Keystone TUI
//!
//! Terminal user interface for Keystone NixOS infrastructure configuration
//! and management. Handles repo setup, secrets, key enrollment, host
//! configuration, building, and git operations.

#![allow(dead_code)]

use std::io;

use anyhow::Result;
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
mod system;
mod template;
mod ui;

use app::{App, AppScreen};
use input::{dispatch_key, handle_action, AppAction};
use screens::first_boot::FirstBootConfig;
use screens::install::InstallerConfig;

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

/// Main application loop. Generic over backend so tests can use TestBackend.
async fn run_app<B: Backend>(terminal: &mut Terminal<B>, app: &mut App) -> Result<()> {
    loop {
        // Poll active screens for async updates before rendering
        match &mut app.current_screen {
            AppScreen::Build(ref mut build) => build.poll(),
            AppScreen::Iso(ref mut iso) => iso.poll(),
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
