//! Input handling and action dispatch for the Keystone TUI.
//!
//! This module contains all key event handling and action dispatch logic,
//! extracted from main.rs to make it testable.

use crossterm::event::{KeyCode, KeyEvent, KeyEventKind};

use crate::app::{App, AppScreen};
use crate::nix::HostInfo;
use crate::screens;

/// Actions that require mutating app-level state (screen transitions).
#[derive(Debug)]
pub enum AppAction {
    WelcomeAction(screens::welcome::WelcomeAction),
    GoToHostDetail(HostInfo),
    GoToHosts,
    StartBuild(String),
    Quit,
}

/// Dispatch a key event to the appropriate handler based on the current screen.
/// Returns `Some(AppAction)` if the key produced an action, or `None` if it was consumed silently.
pub fn dispatch_key(app: &mut App, key: KeyEvent) -> Option<AppAction> {
    // Only handle key press events, not release
    if key.kind != KeyEventKind::Press {
        return None;
    }

    match &mut app.current_screen {
        AppScreen::Welcome(ref mut welcome) => handle_welcome_input(welcome, key),
        AppScreen::Hosts(ref mut hosts) => handle_hosts_input(hosts, key),
        AppScreen::HostDetail(ref mut detail) => handle_host_detail_input(detail, key),
        AppScreen::Build(ref mut build) => handle_build_input(build, key),
    }
}

/// Handle input for the welcome screen.
pub fn handle_welcome_input(
    welcome: &mut screens::welcome::WelcomeScreen,
    key: KeyEvent,
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
                    return Some(AppAction::Quit);
                }
            }
            KeyCode::Esc => {
                if *welcome.state() == WelcomeState::SelectAction {
                    return Some(AppAction::Quit);
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
pub fn handle_hosts_input(
    hosts: &mut screens::hosts::HostsScreen,
    key: KeyEvent,
) -> Option<AppAction> {
    match key.code {
        KeyCode::Char('q') | KeyCode::Esc => Some(AppAction::Quit),
        KeyCode::Up | KeyCode::Char('k') => {
            hosts.previous();
            None
        }
        KeyCode::Down | KeyCode::Char('j') => {
            hosts.next();
            None
        }
        KeyCode::Enter => hosts
            .selected_host()
            .map(|host| AppAction::GoToHostDetail(host.clone())),
        _ => None,
    }
}

/// Handle input for the host detail screen.
pub fn handle_host_detail_input(
    _detail: &mut screens::host_detail::HostDetailScreen,
    key: KeyEvent,
) -> Option<AppAction> {
    match key.code {
        KeyCode::Char('q') => Some(AppAction::Quit),
        KeyCode::Esc => Some(AppAction::GoToHosts),
        KeyCode::Char('b') => {
            let host_name = _detail.host().name.clone();
            Some(AppAction::StartBuild(host_name))
        }
        _ => None,
    }
}

/// Handle input for the build screen.
pub fn handle_build_input(
    build: &mut screens::build::BuildScreen,
    key: KeyEvent,
) -> Option<AppAction> {
    match key.code {
        KeyCode::Char('q') => {
            if build.is_finished() {
                Some(AppAction::Quit)
            } else {
                None
            }
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
pub async fn handle_action(app: &mut App, action: AppAction) {
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
                app.current_screen =
                    AppScreen::Build(screens::build::BuildScreen::new(host_name, repo_path));
            }
        }
        AppAction::Quit => {
            app.should_quit = true;
        }
    }
}

/// Handle actions from the welcome screen.
async fn handle_welcome_action(app: &mut App, action: screens::welcome::WelcomeAction) {
    use screens::welcome::WelcomeAction;

    match action {
        WelcomeAction::ImportRepo { name, git_url } => {
            if let AppScreen::Welcome(ref mut welcome) = app.current_screen {
                match crate::repo::import_repo(name.clone(), git_url).await {
                    Ok(repo) => {
                        app.config.repos.push(repo);
                        welcome
                            .set_success(format!("Repository '{}' imported successfully!", name));
                    }
                    Err(e) => {
                        welcome.set_error(format!("Failed to import repository: {}", e));
                    }
                }
            }
        }
        WelcomeAction::CreateRepo { name } => {
            if let AppScreen::Welcome(ref mut welcome) = app.current_screen {
                match crate::repo::create_new_repo(name.clone()).await {
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
            let repo_index = app.config.repos.len().saturating_sub(1);
            app.go_to_hosts(repo_index).await;
        }
        WelcomeAction::None => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyEventState, KeyModifiers};

    /// Helper to create a key press event.
    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent {
            code,
            modifiers: KeyModifiers::NONE,
            kind: KeyEventKind::Press,
            state: KeyEventState::NONE,
        }
    }

    /// Helper to create a key release event.
    fn key_release(code: KeyCode) -> KeyEvent {
        KeyEvent {
            code,
            modifiers: KeyModifiers::NONE,
            kind: KeyEventKind::Release,
            state: KeyEventState::NONE,
        }
    }

    #[test]
    fn test_key_release_events_are_ignored() {
        let mut app = App::new_for_test();
        let result = dispatch_key(&mut app, key_release(KeyCode::Char('q')));
        assert!(result.is_none());
    }

    #[test]
    fn test_q_quits_from_welcome_select() {
        let mut app = App::new_for_test();
        let action = dispatch_key(&mut app, key(KeyCode::Char('q')));
        assert!(matches!(action, Some(AppAction::Quit)));
    }

    #[test]
    fn test_esc_quits_from_welcome_select() {
        let mut app = App::new_for_test();
        let action = dispatch_key(&mut app, key(KeyCode::Esc));
        assert!(matches!(action, Some(AppAction::Quit)));
    }

    #[test]
    fn test_q_quits_from_hosts() {
        let hosts = vec![HostInfo {
            name: "test-host".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec![],
            config_files: vec![],
        }];
        let mut app = App::new_for_test();
        app.current_screen = AppScreen::Hosts(screens::hosts::HostsScreen::new(
            "test-repo".to_string(),
            hosts,
        ));

        let action = dispatch_key(&mut app, key(KeyCode::Char('q')));
        assert!(matches!(action, Some(AppAction::Quit)));
    }

    #[test]
    fn test_enter_selects_host() {
        let hosts = vec![HostInfo {
            name: "my-host".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec![],
            config_files: vec![],
        }];
        let mut app = App::new_for_test();
        app.current_screen = AppScreen::Hosts(screens::hosts::HostsScreen::new(
            "test-repo".to_string(),
            hosts,
        ));

        let action = dispatch_key(&mut app, key(KeyCode::Enter));
        assert!(matches!(action, Some(AppAction::GoToHostDetail(_))));
    }

    #[test]
    fn test_b_starts_build_from_detail() {
        let host = HostInfo {
            name: "build-host".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec![],
            config_files: vec![],
        };
        let mut app = App::new_for_test();
        app.current_screen =
            AppScreen::HostDetail(screens::host_detail::HostDetailScreen::new(host));

        let action = dispatch_key(&mut app, key(KeyCode::Char('b')));
        match action {
            Some(AppAction::StartBuild(name)) => assert_eq!(name, "build-host"),
            other => panic!("Expected StartBuild, got {:?}", other),
        }
    }

    #[test]
    fn test_esc_goes_to_hosts_from_detail() {
        let host = HostInfo {
            name: "test-host".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
        };
        let mut app = App::new_for_test();
        app.current_screen =
            AppScreen::HostDetail(screens::host_detail::HostDetailScreen::new(host));

        let action = dispatch_key(&mut app, key(KeyCode::Esc));
        assert!(matches!(action, Some(AppAction::GoToHosts)));
    }

    #[test]
    fn test_q_quits_from_host_detail() {
        let host = HostInfo {
            name: "test-host".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
        };
        let mut app = App::new_for_test();
        app.current_screen =
            AppScreen::HostDetail(screens::host_detail::HostDetailScreen::new(host));

        let action = dispatch_key(&mut app, key(KeyCode::Char('q')));
        assert!(matches!(action, Some(AppAction::Quit)));
    }
}
