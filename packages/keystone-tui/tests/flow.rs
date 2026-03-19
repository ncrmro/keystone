//! Multi-screen flow integration tests.
//!
//! These tests exercise screen transitions using dispatch_key + handle_action,
//! verifying that the TUI navigates correctly between screens.

use crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyEventState, KeyModifiers};

use keystone_tui::app::{App, AppScreen};
use keystone_tui::input::{dispatch_key, handle_action, AppAction};
use keystone_tui::nix::HostInfo;
use keystone_tui::screens::hosts::HostsScreen;

/// Helper to create a key press event.
fn key(code: KeyCode) -> KeyEvent {
    KeyEvent {
        code,
        modifiers: KeyModifiers::NONE,
        kind: KeyEventKind::Press,
        state: KeyEventState::NONE,
    }
}

#[test]
fn test_welcome_to_hosts_flow() {
    let mut app = App::new_for_test();

    // Start on Welcome
    assert!(matches!(app.current_screen, AppScreen::Welcome(_)));

    // Simulate the welcome flow completing (set_success + confirm)
    if let AppScreen::Welcome(ref mut welcome) = app.current_screen {
        welcome.set_success("Repo imported!".to_string());
    }

    // Press Enter to acknowledge success
    let action = dispatch_key(&mut app, key(KeyCode::Enter));
    // This should return WelcomeAction(Complete) which transitions to hosts
    assert!(matches!(action, Some(AppAction::WelcomeAction(_))));
}

#[test]
fn test_hosts_to_detail_and_back() {
    let hosts = vec![
        HostInfo {
            name: "laptop".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec![],
            config_files: vec![],
        },
        HostInfo {
            name: "server".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
        },
    ];

    let mut app = App::new_for_test();
    app.current_screen = AppScreen::Hosts(HostsScreen::new("test-repo".to_string(), hosts));

    // Press Enter to go to host detail
    let action = dispatch_key(&mut app, key(KeyCode::Enter));
    match action {
        Some(AppAction::GoToHostDetail(host)) => {
            assert_eq!(host.name, "laptop");
            // Manually transition (in real app, handle_action does this)
            app.current_screen = AppScreen::HostDetail(
                keystone_tui::screens::host_detail::HostDetailScreen::new(host),
            );
        }
        other => panic!("Expected GoToHostDetail, got {:?}", other),
    }

    assert!(matches!(app.current_screen, AppScreen::HostDetail(_)));

    // Press Esc to go back to hosts
    let action = dispatch_key(&mut app, key(KeyCode::Esc));
    assert!(matches!(action, Some(AppAction::GoToHosts)));
}

#[test]
fn test_navigate_hosts_then_select_second() {
    let hosts = vec![
        HostInfo {
            name: "alpha".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
        },
        HostInfo {
            name: "beta".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
        },
    ];

    let mut app = App::new_for_test();
    app.current_screen = AppScreen::Hosts(HostsScreen::new("repo".to_string(), hosts));

    // Navigate down
    let action = dispatch_key(&mut app, key(KeyCode::Down));
    assert!(action.is_none()); // Navigation doesn't produce an action

    // Press Enter on second host
    let action = dispatch_key(&mut app, key(KeyCode::Enter));
    match action {
        Some(AppAction::GoToHostDetail(host)) => {
            assert_eq!(host.name, "beta");
        }
        other => panic!("Expected GoToHostDetail(beta), got {:?}", other),
    }
}

#[test]
fn test_quit_from_any_screen() {
    // Quit from Welcome
    let mut app = App::new_for_test();
    let action = dispatch_key(&mut app, key(KeyCode::Char('q')));
    assert!(matches!(action, Some(AppAction::Quit)));

    // Quit from Hosts
    let mut app = App::new_for_test();
    app.current_screen = AppScreen::Hosts(HostsScreen::new("repo".to_string(), vec![]));
    let action = dispatch_key(&mut app, key(KeyCode::Char('q')));
    assert!(matches!(action, Some(AppAction::Quit)));

    // Quit from HostDetail
    let mut app = App::new_for_test();
    app.current_screen = AppScreen::HostDetail(
        keystone_tui::screens::host_detail::HostDetailScreen::new(HostInfo {
            name: "host".to_string(),
            system: None,
            keystone_modules: vec![],
            config_files: vec![],
        }),
    );
    let action = dispatch_key(&mut app, key(KeyCode::Char('q')));
    assert!(matches!(action, Some(AppAction::Quit)));
}

#[tokio::test]
async fn test_handle_action_quit_sets_flag() {
    let mut app = App::new_for_test();
    assert!(!app.should_quit);
    handle_action(&mut app, AppAction::Quit).await;
    assert!(app.should_quit);
}

#[tokio::test]
async fn test_handle_action_go_to_host_detail() {
    let mut app = App::new_for_test();
    let host = HostInfo {
        name: "target-host".to_string(),
        system: Some("aarch64-linux".to_string()),
        keystone_modules: vec!["operating-system".to_string()],
        config_files: vec![],
    };

    handle_action(&mut app, AppAction::GoToHostDetail(host)).await;
    assert!(matches!(app.current_screen, AppScreen::HostDetail(_)));

    if let AppScreen::HostDetail(ref detail) = app.current_screen {
        assert_eq!(detail.host().name, "target-host");
    }
}
