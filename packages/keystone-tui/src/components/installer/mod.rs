//! Installer component — build ISOs, detect USB targets, burn media.
//!
//! This is the sidebar "Installer" section. It orchestrates:
//! 1. Selecting a host to build an ISO for
//! 2. Choosing an install profile (desktop or server+terminal)
//! 3. Building the ISO via nix
//! 4. Detecting removable USB devices and writing the ISO
//!
//! The ISO bakes in:
//! - The user's SSH public keys (for remote access during install)
//! - The host's NixOS configuration (flake.nix + hosts/<name>/)
//! - NetworkManager for wired+wireless connectivity
//! - The keystone-tui installer which runs disko + nixos-install
//!
//! Future:
//! - WiFi setup screen during install
//! - Airgapped mode (pre-fetch all derivations)

use crossterm::event::{Event, KeyCode, KeyEventKind};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame,
};

use crate::action::{Action, Screen};
use crate::component::Component;

/// Install profile — what gets included in the ISO.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallProfile {
    /// Full desktop: operating-system + desktop + terminal modules.
    Desktop,
    /// Headless: operating-system + terminal modules only.
    Server,
}

impl InstallProfile {
    fn label(&self) -> &'static str {
        match self {
            InstallProfile::Desktop => "Desktop (full Hyprland desktop)",
            InstallProfile::Server => "Server (headless + terminal)",
        }
    }
}

/// A detected USB device suitable for writing an ISO.
#[derive(Debug, Clone)]
pub struct UsbTarget {
    pub path: String,
    pub model: String,
    pub size: String,
}

/// The installer screen's internal phase.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Phase {
    /// Select install profile and review options.
    Configure,
    /// ISO is building.
    Building,
    /// ISO built — select USB target or save to ~/Downloads.
    SelectTarget,
    /// Writing ISO to USB.
    Writing,
    /// Done.
    Done,
    /// Error.
    Failed(String),
}

pub struct InstallerScreen {
    phase: Phase,
    profile: InstallProfile,
    usb_targets: Vec<UsbTarget>,
    selected_target: usize,
    output_lines: Vec<String>,
}

impl Default for InstallerScreen {
    fn default() -> Self {
        Self::new()
    }
}

impl InstallerScreen {
    pub fn new() -> Self {
        Self {
            phase: Phase::Configure,
            profile: InstallProfile::Desktop,
            usb_targets: Vec::new(),
            selected_target: 0,
            output_lines: Vec::new(),
        }
    }

    fn toggle_profile(&mut self) {
        self.profile = match self.profile {
            InstallProfile::Desktop => InstallProfile::Server,
            InstallProfile::Server => InstallProfile::Desktop,
        };
    }
}

impl Component for InstallerScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(match self.phase {
                Phase::Configure => match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => Some(Action::Quit),
                    KeyCode::Tab | KeyCode::Up | KeyCode::Down => {
                        self.toggle_profile();
                        None
                    }
                    // Sidebar navigation
                    KeyCode::Char('1') => Some(Action::NavigateTo(Screen::Hosts)),
                    KeyCode::Char('2') => Some(Action::NavigateTo(Screen::Services)),
                    KeyCode::Char('3') => Some(Action::NavigateTo(Screen::Secrets)),
                    KeyCode::Char('4') => Some(Action::NavigateTo(Screen::Security)),
                    // TODO: Enter to start build
                    _ => None,
                },
                Phase::Building => match key.code {
                    KeyCode::Char('q') => Some(Action::Quit),
                    _ => None,
                },
                Phase::SelectTarget => match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => Some(Action::Quit),
                    KeyCode::Up | KeyCode::Char('k') => {
                        if self.selected_target > 0 {
                            self.selected_target -= 1;
                        }
                        None
                    }
                    KeyCode::Down | KeyCode::Char('j') => {
                        if self.selected_target + 1 < self.usb_targets.len() {
                            self.selected_target += 1;
                        }
                        None
                    }
                    _ => None,
                },
                Phase::Writing => None,
                Phase::Done | Phase::Failed(_) => match key.code {
                    KeyCode::Char('q') => Some(Action::Quit),
                    KeyCode::Esc => Some(Action::GoBack),
                    _ => None,
                },
            });
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        let help = match self.phase {
            Phase::Configure => "1-5: sections • Tab: toggle profile • Enter: build • q: quit",
            Phase::Building | Phase::Writing => "building...",
            Phase::SelectTarget => "↑/↓: select • Enter: write ISO • r: refresh • Esc: back",
            Phase::Done | Phase::Failed(_) => "Esc: back • q: quit",
        };

        let shell =
            crate::widgets::shell::render_shell(frame, area, "Installer", "", 4, help, None);

        let content = shell.content;
        match &self.phase {
            Phase::Configure => self.render_configure(frame, content, content),
            Phase::Building | Phase::Writing => self.render_building(frame, content),
            Phase::SelectTarget => {
                let panels = Layout::default()
                    .direction(Direction::Horizontal)
                    .constraints([Constraint::Percentage(50), Constraint::Min(20)])
                    .split(content);
                self.render_select_target(frame, panels[0], panels[1]);
            }
            Phase::Done => self.render_done(frame, content),
            Phase::Failed(msg) => self.render_failed(frame, content, msg.clone()),
        }

        Ok(())
    }
}

impl InstallerScreen {
    fn render_configure(&self, frame: &mut Frame, area: Rect, _unused: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(8), // Description
                Constraint::Length(1), // Spacer
                Constraint::Length(4), // Profile select
                Constraint::Length(1), // Spacer
                Constraint::Length(5), // Options
                Constraint::Min(0),    // Spacer
            ])
            .split(area);

        // Description text at top
        let desc = Paragraph::new(vec![
            Line::from(""),
            Line::from(Span::styled(
                " The installer builds a bootable ISO with your NixOS config baked in.",
                Style::default(),
            )),
            Line::from(Span::styled(
                " The ISO includes your SSH keys, NetworkManager for WiFi + wired,",
                Style::default(),
            )),
            Line::from(Span::styled(
                " the Keystone TUI installer, disko, and ZFS/SecureBoot/TPM tools.",
                Style::default(),
            )),
            Line::from(""),
            Line::from(Span::styled(
                " Boot from USB → TUI runs disko → nixos-install → reboot → first-boot setup.",
                Style::default().fg(Color::DarkGray),
            )),
        ]);
        frame.render_widget(desc, chunks[0]);

        // Profile selection — render both options, highlight active
        let desktop_style = if self.profile == InstallProfile::Desktop {
            Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(Color::DarkGray)
        };
        let server_style = if self.profile == InstallProfile::Server {
            Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(Color::DarkGray)
        };

        let profile_widget = Paragraph::new(vec![
            Line::from(Span::styled(
                format!("  {}", InstallProfile::Desktop.label()),
                desktop_style,
            )),
            Line::from(Span::styled(
                format!("  {}", InstallProfile::Server.label()),
                server_style,
            )),
        ])
        .block(
            Block::default()
                .title(" Install Profile (Tab to switch) ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        );
        frame.render_widget(profile_widget, chunks[2]);

        // Options summary
        let options = Paragraph::new(vec![
            Line::from(vec![
                Span::styled("  SSH keys   ", Style::default().fg(Color::DarkGray)),
                Span::styled("from ~/.ssh/ + GitHub", Style::default()),
            ]),
            Line::from(vec![
                Span::styled("  Network    ", Style::default().fg(Color::DarkGray)),
                Span::styled("NetworkManager (wired + WiFi)", Style::default()),
            ]),
            Line::from(vec![
                Span::styled("  Airgapped  ", Style::default().fg(Color::DarkGray)),
                Span::styled("not yet supported", Style::default().fg(Color::DarkGray)),
            ]),
        ])
        .block(
            Block::default()
                .title(" Options ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        );
        frame.render_widget(options, chunks[4]);
    }

    fn render_building(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(1),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Building ISO...",
            Style::default().bold().yellow(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        let output: Vec<Line> = self
            .output_lines
            .iter()
            .map(|l| Line::from(l.as_str()))
            .collect();
        let log = Paragraph::new(output)
            .block(Block::default().borders(Borders::ALL))
            .wrap(ratatui::widgets::Wrap { trim: false });
        frame.render_widget(log, chunks[1]);
    }

    fn render_select_target(&self, frame: &mut Frame, main: Rect, info: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(2),
            ])
            .split(main);

        let title = Paragraph::new(Text::styled(
            "Select USB Target",
            Style::default().bold().yellow(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        if self.usb_targets.is_empty() {
            let msg = Paragraph::new(Text::styled(
                "No removable USB devices detected.\n\nInsert a USB drive and press 'r' to refresh.",
                Style::default().fg(Color::DarkGray),
            ))
            .alignment(Alignment::Center);
            frame.render_widget(msg, chunks[1]);
        } else {
            let items: Vec<ListItem> = self
                .usb_targets
                .iter()
                .enumerate()
                .map(|(i, t)| {
                    let style = if i == self.selected_target {
                        Style::default()
                            .fg(Color::Green)
                            .add_modifier(Modifier::BOLD)
                    } else {
                        Style::default()
                    };
                    ListItem::new(vec![
                        Line::from(Span::styled(format!(" {}", t.model), style)),
                        Line::from(Span::styled(
                            format!("   {} — {}", t.path, t.size),
                            Style::default().fg(Color::DarkGray),
                        )),
                    ])
                })
                .collect();

            let list = List::new(items).block(
                Block::default()
                    .title(" USB Devices ")
                    .borders(Borders::ALL),
            );
            frame.render_widget(list, chunks[1]);
        }

        let help = Paragraph::new(Text::styled(
            "↑/↓: select • Enter: write ISO • r: refresh • Esc: back",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);

        // Info panel
        let warning = Paragraph::new(vec![
            Line::from(Span::styled(
                " WARNING",
                Style::default().fg(Color::Red).bold(),
            )),
            Line::from(""),
            Line::from(Span::styled(
                " Writing the ISO will ERASE all data",
                Style::default().fg(Color::Red),
            )),
            Line::from(Span::styled(
                " on the selected USB device.",
                Style::default().fg(Color::Red),
            )),
        ]);
        frame.render_widget(warning, info);
    }

    fn render_done(&self, frame: &mut Frame, area: Rect) {
        let msg = Paragraph::new(Text::styled(
            "ISO written successfully!\n\nRemove the USB drive and boot the target machine from it.",
            Style::default().fg(Color::Green),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(msg, area);
    }

    fn render_failed(&self, frame: &mut Frame, area: Rect, msg: String) {
        let text = Paragraph::new(Text::styled(
            format!("Failed: {}", msg),
            Style::default().fg(Color::Red),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(text, area);
    }
}
