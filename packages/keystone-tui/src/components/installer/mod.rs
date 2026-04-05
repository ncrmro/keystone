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
    style::{Modifier, Style},
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
    /// Channel for receiving async USB scan results.
    usb_rx: Option<tokio::sync::mpsc::UnboundedReceiver<Vec<UsbTarget>>>,
    /// Whether a USB scan is currently running.
    scanning: bool,
}

impl Default for InstallerScreen {
    fn default() -> Self {
        Self::new()
    }
}

impl InstallerScreen {
    pub fn new() -> Self {
        let mut screen = Self {
            phase: Phase::Configure,
            profile: InstallProfile::Server,
            usb_targets: Vec::new(),
            selected_target: 0,
            output_lines: Vec::new(),
            usb_rx: None,
            scanning: false,
        };
        screen.spawn_usb_scan();
        screen
    }

    fn toggle_profile(&mut self) {
        self.profile = match self.profile {
            InstallProfile::Desktop => InstallProfile::Server,
            InstallProfile::Server => InstallProfile::Desktop,
        };
    }

    fn spawn_usb_scan(&mut self) {
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
        self.usb_rx = Some(rx);
        self.scanning = true;
        tokio::spawn(async move {
            let targets = match crate::disk::discover_disks().await {
                Ok(disks) => disks
                    .into_iter()
                    .filter(|d| d.transport == "usb")
                    .map(|d| UsbTarget {
                        path: d.by_id_path,
                        model: d.model,
                        size: d.size,
                    })
                    .collect(),
                Err(_) => Vec::new(),
            };
            let _ = tx.send(targets);
        });
    }

    fn poll_usb(&mut self) {
        if let Some(ref mut rx) = self.usb_rx {
            if let Ok(targets) = rx.try_recv() {
                self.usb_targets = targets;
                self.selected_target = 0;
                self.scanning = false;
            }
        }
    }
}

impl Component for InstallerScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        self.poll_usb();

        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(match self.phase {
                Phase::Configure => match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => Some(Action::Quit),
                    KeyCode::Tab => {
                        self.toggle_profile();
                        None
                    }
                    KeyCode::Char('r') => {
                        self.spawn_usb_scan();
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
            Phase::Configure => {
                "1-5: sections • Tab: profile • r: rescan USB • Enter: build • q: quit"
            }
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
        let t = crate::theme::default();

        let usb_height = if self.usb_targets.is_empty() {
            3
        } else {
            (self.usb_targets.len() as u16 * 2 + 2).min(10)
        };

        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(5),          // Description
                Constraint::Length(1),          // Spacer
                Constraint::Length(4),          // Profile select
                Constraint::Length(1),          // Spacer
                Constraint::Length(5),          // Options
                Constraint::Length(1),          // Spacer
                Constraint::Length(usb_height), // USB targets
                Constraint::Min(0),             // Spacer
            ])
            .split(area);

        // Description text at top
        let desc = Paragraph::new(vec![
            Line::from(Span::styled(
                " Build a bootable ISO with your NixOS config, SSH keys, and installer.",
                Style::default(),
            )),
            Line::from(Span::styled(
                " Boot from USB → TUI runs disko → nixos-install → reboot → first-boot setup.",
                t.inactive_style(),
            )),
        ]);
        frame.render_widget(desc, chunks[0]);

        // Profile selection
        let desktop_style = if self.profile == InstallProfile::Desktop {
            t.active_style()
        } else {
            t.inactive_style()
        };
        let server_style = if self.profile == InstallProfile::Server {
            t.active_style()
        } else {
            t.inactive_style()
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
                .border_style(t.inactive_style()),
        );
        frame.render_widget(profile_widget, chunks[2]);

        // Options summary
        let options = Paragraph::new(vec![
            Line::from(vec![
                Span::styled("  SSH keys   ", t.inactive_style()),
                Span::styled("from ~/.ssh/ + GitHub", Style::default()),
            ]),
            Line::from(vec![
                Span::styled("  Network    ", t.inactive_style()),
                Span::styled("NetworkManager (wired + WiFi)", Style::default()),
            ]),
            Line::from(vec![
                Span::styled("  Airgapped  ", t.inactive_style()),
                Span::styled("not yet supported", t.inactive_style()),
            ]),
        ])
        .block(
            Block::default()
                .title(" Options ")
                .borders(Borders::ALL)
                .border_style(t.inactive_style()),
        );
        frame.render_widget(options, chunks[4]);

        // USB targets
        let usb_widget = if self.scanning {
            Paragraph::new(Line::from(Span::styled(
                "  Scanning for USB devices...",
                t.inactive_style(),
            )))
            .block(
                Block::default()
                    .title(" USB Devices ")
                    .borders(Borders::ALL)
                    .border_style(t.inactive_style()),
            )
        } else if self.usb_targets.is_empty() {
            Paragraph::new(Line::from(Span::styled(
                "  No USB devices detected (r to rescan)",
                t.inactive_style(),
            )))
            .block(
                Block::default()
                    .title(" USB Devices ")
                    .borders(Borders::ALL)
                    .border_style(t.inactive_style()),
            )
        } else {
            let lines: Vec<Line> = self
                .usb_targets
                .iter()
                .flat_map(|usb| {
                    vec![
                        Line::from(Span::styled(
                            format!("  {} ({})", usb.model, usb.size),
                            Style::default(),
                        )),
                        Line::from(Span::styled(
                            format!("    {}", usb.path),
                            t.inactive_style(),
                        )),
                    ]
                })
                .collect();
            Paragraph::new(lines).block(
                Block::default()
                    .title(format!(" USB Devices ({}) ", self.usb_targets.len()))
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(t.active)),
            )
        };
        frame.render_widget(usb_widget, chunks[6]);
    }

    fn render_building(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(1),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("Building ISO...", t.title_style()))
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
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(2),
            ])
            .split(main);

        let title = Paragraph::new(Text::styled("Select USB Target", t.title_style()))
            .alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        if self.usb_targets.is_empty() {
            let msg = Paragraph::new(Text::styled(
                "No removable USB devices detected.\n\nInsert a USB drive and press 'r' to refresh.",
                t.inactive_style(),
            ))
            .alignment(Alignment::Center);
            frame.render_widget(msg, chunks[1]);
        } else {
            let items: Vec<ListItem> = self
                .usb_targets
                .iter()
                .enumerate()
                .map(|(i, target)| {
                    let style = if i == self.selected_target {
                        t.active_style()
                    } else {
                        Style::default()
                    };
                    ListItem::new(vec![
                        Line::from(Span::styled(format!(" {}", target.model), style)),
                        Line::from(Span::styled(
                            format!("   {} — {}", target.path, target.size),
                            t.inactive_style(),
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
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);

        // Info panel
        let warning = Paragraph::new(vec![
            Line::from(Span::styled(
                " WARNING",
                t.error_style().add_modifier(Modifier::BOLD),
            )),
            Line::from(""),
            Line::from(Span::styled(
                " Writing the ISO will ERASE all data",
                t.error_style(),
            )),
            Line::from(Span::styled(
                " on the selected USB device.",
                t.error_style(),
            )),
        ]);
        frame.render_widget(warning, info);
    }

    fn render_done(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let msg = Paragraph::new(Text::styled(
            "ISO written successfully!\n\nRemove the USB drive and boot the target machine from it.",
            Style::default().fg(t.active),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(msg, area);
    }

    fn render_failed(&self, frame: &mut Frame, area: Rect, msg: String) {
        let t = crate::theme::default();
        let text = Paragraph::new(Text::styled(format!("Failed: {}", msg), t.error_style()))
            .alignment(Alignment::Center);
        frame.render_widget(text, area);
    }
}
