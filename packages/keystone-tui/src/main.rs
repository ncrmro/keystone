//! Keystone TUI
//!
//! Terminal user interface for Keystone NixOS infrastructure configuration
//! and management. Handles repo setup, secrets, key enrollment, host
//! configuration, building, and git operations.

use std::io;

use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::prelude::*;

mod app;
mod config;
mod nix;
mod repo;
mod screens;
mod ui;

use app::{App, AppScreen};
use nix::HostInfo;

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
    let mut app = App::new().await;

    let result = run_app(&mut terminal, &mut app).await;

    restore_terminal(&mut terminal)?;

    app.save_config().await;

    result
}

/// Actions that require mutating app-level state (screen transitions).
enum AppAction {
    WelcomeAction(screens::welcome::WelcomeAction),
    GoToHostDetail(HostInfo),
    GoToHosts,
    StartBuild(String),
}

/// Main application loop.
async fn run_app(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
) -> Result<()> {
    loop {
        // Poll build screen for new output before rendering
        if let AppScreen::Build(ref mut build) = app.current_screen {
            build.poll();
        }

        terminal.draw(|frame| {
            let area = frame.area();
            match &mut app.current_screen {
                AppScreen::Welcome(welcome_screen) => {
                    welcome_screen.render(frame, area);
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
            }
        })?;

        if event::poll(std::time::Duration::from_millis(100))? {
            match event::read()? {
                Event::Key(key) => {
                    // Only handle key press events, not release
                    if key.kind != KeyEventKind::Press {
                        continue;
                    }

                    let action = match &mut app.current_screen {
                        AppScreen::Welcome(ref mut welcome) => {
                            handle_welcome_input(welcome, key, &mut app.should_quit)
                        }
                        AppScreen::Hosts(ref mut hosts) => {
                            handle_hosts_input(hosts, key, &mut app.should_quit)
                        }
                        AppScreen::HostDetail(ref mut detail) => {
                            handle_host_detail_input(detail, key, &mut app.should_quit)
                        }
                        AppScreen::Build(ref mut build) => {
                            handle_build_input(build, key, &mut app.should_quit)
                        }
                    };

                    if let Some(action) = action {
                        handle_action(app, action).await;
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

/// Handle input for the welcome screen.
fn handle_welcome_input(
    welcome: &mut screens::welcome::WelcomeScreen,
    key: crossterm::event::KeyEvent,
    should_quit: &mut bool,
) -> Option<AppAction> {
    use screens::welcome::WelcomeState;

    let in_input_state = matches!(
        welcome.state(),
        WelcomeState::InputGitUrl | WelcomeState::InputRepoName
    );

    if in_input_state {
        match key.code {
            KeyCode::Enter => {
                return Some(AppAction::WelcomeAction(welcome.confirm()));
            }
            KeyCode::Esc => {
                welcome.cancel();
            }
            _ => {
                welcome.handle_text_input(key);
            }
        }
    } else {
        match key.code {
            KeyCode::Char('q') => {
                if *welcome.state() == WelcomeState::SelectAction {
                    *should_quit = true;
                }
            }
            KeyCode::Esc => {
                if *welcome.state() == WelcomeState::SelectAction {
                    *should_quit = true;
                } else {
                    welcome.cancel();
                }
            }
            KeyCode::Up | KeyCode::Char('k') => {
                welcome.previous();
            }
            KeyCode::Down | KeyCode::Char('j') => {
                welcome.next();
            }
            KeyCode::Enter => {
                return Some(AppAction::WelcomeAction(welcome.confirm()));
            }
            _ => {}
        }
    }
    None
}

/// Handle input for the hosts screen.
fn handle_hosts_input(
    hosts: &mut screens::hosts::HostsScreen,
    key: crossterm::event::KeyEvent,
    should_quit: &mut bool,
) -> Option<AppAction> {
    match key.code {
        KeyCode::Char('q') | KeyCode::Esc => {
            *should_quit = true;
            None
        }
        KeyCode::Up | KeyCode::Char('k') => {
            hosts.previous();
            None
        }
        KeyCode::Down | KeyCode::Char('j') => {
            hosts.next();
            None
        }
        KeyCode::Enter => {
            if let Some(host) = hosts.selected_host() {
                Some(AppAction::GoToHostDetail(host.clone()))
            } else {
                None
            }
        }
        _ => None,
    }
}

/// Handle input for the host detail screen.
fn handle_host_detail_input(
    detail: &mut screens::host_detail::HostDetailScreen,
    key: crossterm::event::KeyEvent,
    should_quit: &mut bool,
) -> Option<AppAction> {
    match key.code {
        KeyCode::Char('q') => {
            *should_quit = true;
            None
        }
        KeyCode::Esc => Some(AppAction::GoToHosts),
        KeyCode::Char('b') => {
            let host_name = detail.host().name.clone();
            Some(AppAction::StartBuild(host_name))
        }
        _ => None,
    }
}

/// Handle input for the build screen.
fn handle_build_input(
    build: &mut screens::build::BuildScreen,
    key: crossterm::event::KeyEvent,
    should_quit: &mut bool,
) -> Option<AppAction> {
    match key.code {
        KeyCode::Char('q') => {
            if build.is_finished() {
                *should_quit = true;
            }
            None
        }
        KeyCode::Esc => {
            if build.is_finished() {
                Some(AppAction::GoToHosts)
            } else {
                build.cancel();
                None
            }
        }
        KeyCode::Up | KeyCode::Char('k') => {
            build.scroll_up();
            None
        }
        KeyCode::Down | KeyCode::Char('j') => {
            build.scroll_down();
            None
        }
        _ => None,
    }
}

/// Handle actions that require mutating app state.
async fn handle_action(app: &mut App, action: AppAction) {
    match action {
        AppAction::WelcomeAction(wa) => {
            handle_welcome_action(app, wa).await;
        }
        AppAction::GoToHostDetail(host) => {
            app.current_screen =
                AppScreen::HostDetail(screens::host_detail::HostDetailScreen::new(host));
        }
        AppAction::GoToHosts => {
            // Re-load the hosts screen from the active repo
            app.go_to_hosts(app.active_repo_index.unwrap_or(0)).await;
        }
        AppAction::StartBuild(host_name) => {
            if let Some(repo_path) = app.active_repo_path() {
                app.current_screen = AppScreen::Build(screens::build::BuildScreen::new(
                    host_name, repo_path,
                ));
            }
        }
    }
}

/// Handle actions from the welcome screen.
async fn handle_welcome_action(app: &mut App, action: screens::welcome::WelcomeAction) {
    use screens::welcome::WelcomeAction;

    match action {
        WelcomeAction::ImportRepo { name, git_url } => {
            if let AppScreen::Welcome(ref mut welcome) = app.current_screen {
                match repo::import_repo(name.clone(), git_url).await {
                    Ok(repo) => {
                        app.config.repos.push(repo);
                        welcome.set_success(format!("Repository '{}' imported successfully!", name));
                    }
                    Err(e) => {
                        welcome.set_error(format!("Failed to import repository: {}", e));
                    }
                }
            }
        }
        WelcomeAction::CreateRepo { name } => {
            if let AppScreen::Welcome(ref mut welcome) = app.current_screen {
                match repo::create_new_repo(name.clone()).await {
                    Ok(repo) => {
                        app.config.repos.push(repo);
                        welcome.set_success(format!("Repository '{}' created successfully!", name));
                    }
                    Err(e) => {
                        welcome.set_error(format!("Failed to create repository: {}", e));
                    }
                }
            }
        }
        WelcomeAction::Complete => {
            // User completed the welcome flow - transition to hosts screen
            // Use the most recently added repo (last in list)
            let repo_index = app.config.repos.len().saturating_sub(1);
            app.go_to_hosts(repo_index).await;
        }
        WelcomeAction::None => {}
    }
}
