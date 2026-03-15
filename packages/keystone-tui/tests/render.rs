//! Render snapshot tests using ratatui TestBackend + insta.
//!
//! These tests render each screen to an in-memory buffer and snapshot
//! the output, ensuring the UI doesn't regress.

use ratatui::{backend::TestBackend, Terminal};

use keystone_tui::nix::HostInfo;
use keystone_tui::screens::build::{BuildMessage, BuildResult, BuildScreen};
use keystone_tui::screens::host_detail::HostDetailScreen;
use keystone_tui::screens::hosts::HostsScreen;
use keystone_tui::screens::welcome::WelcomeScreen;

use tokio::sync::mpsc;

/// Render a screen to a string using TestBackend.
fn render_to_string<F>(width: u16, height: u16, mut render_fn: F) -> String
where
    F: FnMut(&mut ratatui::Frame),
{
    let backend = TestBackend::new(width, height);
    let mut terminal = Terminal::new(backend).unwrap();
    terminal
        .draw(|frame| {
            render_fn(frame);
        })
        .unwrap();

    // Convert the buffer to a string representation
    let backend = terminal.backend();
    let buffer = backend.buffer();
    let mut output = String::new();
    for y in 0..buffer.area.height {
        for x in 0..buffer.area.width {
            let cell = &buffer[(x, y)];
            output.push_str(cell.symbol());
        }
        output.push('\n');
    }
    output
}

#[test]
fn test_render_welcome_screen() {
    let screen = WelcomeScreen::new();
    let output = render_to_string(60, 20, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

#[test]
fn test_render_hosts_list() {
    let hosts = vec![
        HostInfo {
            name: "laptop".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec!["operating-system".to_string()],
            config_files: vec![],
        },
        HostInfo {
            name: "server".to_string(),
            system: Some("x86_64-linux".to_string()),
            keystone_modules: vec!["operating-system".to_string()],
            config_files: vec![],
        },
    ];
    let mut screen = HostsScreen::new("my-infra".to_string(), hosts);
    let output = render_to_string(60, 15, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

#[test]
fn test_render_host_detail() {
    let host = HostInfo {
        name: "workstation".to_string(),
        system: Some("x86_64-linux".to_string()),
        keystone_modules: vec!["operating-system".to_string(), "desktop".to_string()],
        config_files: vec![
            "./configuration.nix".to_string(),
            "./hardware.nix".to_string(),
        ],
    };
    let screen = HostDetailScreen::new(host);
    let output = render_to_string(60, 18, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

#[test]
fn test_render_empty_hosts() {
    let mut screen = HostsScreen::new("empty-repo".to_string(), Vec::new());
    let output = render_to_string(60, 15, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}

#[test]
fn test_render_build_screen_with_output() {
    let (tx, rx) = mpsc::unbounded_channel();
    let mut screen = BuildScreen::new_with_channel("test-host".to_string(), rx);

    tx.send(BuildMessage::Output(
        "$ nixos-rebuild build --flake .#test-host".to_string(),
    ))
    .unwrap();
    tx.send(BuildMessage::Output(String::new())).unwrap();
    tx.send(BuildMessage::Output(
        "building '/nix/store/...'".to_string(),
    ))
    .unwrap();
    tx.send(BuildMessage::Finished(BuildResult::Success))
        .unwrap();
    screen.poll();

    let output = render_to_string(60, 15, |frame| {
        let area = frame.area();
        screen.render(frame, area);
    });
    insta::assert_snapshot!(output);
}
