//! Hosts screen - displays NixOS configurations from the flake.

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Text},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
    Frame,
};

use crate::nix::HostInfo;

/// Screen for viewing and managing hosts in a Keystone repo.
pub struct HostsScreen {
    /// Name of the current repository.
    repo_name: String,
    /// List of host info from nixosConfigurations.
    hosts: Vec<HostInfo>,
    /// Currently selected host index.
    list_state: ListState,
}

impl HostsScreen {
    pub fn new(repo_name: String, hosts: Vec<HostInfo>) -> Self {
        let mut list_state = ListState::default();
        if !hosts.is_empty() {
            list_state.select(Some(0));
        }
        Self {
            repo_name,
            hosts,
            list_state,
        }
    }

    pub fn hosts(&self) -> &[HostInfo] {
        &self.hosts
    }

    pub fn selected_host(&self) -> Option<&HostInfo> {
        self.list_state.selected().and_then(|i| self.hosts.get(i))
    }

    pub fn next(&mut self) {
        if self.hosts.is_empty() {
            return;
        }
        let i = match self.list_state.selected() {
            Some(i) => (i + 1) % self.hosts.len(),
            None => 0,
        };
        self.list_state.select(Some(i));
    }

    pub fn previous(&mut self) {
        if self.hosts.is_empty() {
            return;
        }
        let i = match self.list_state.selected() {
            Some(i) => {
                if i == 0 {
                    self.hosts.len() - 1
                } else {
                    i - 1
                }
            }
            None => 0,
        };
        self.list_state.select(Some(i));
    }

    pub fn render(&mut self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),   // Hosts list
                Constraint::Length(3), // Help
            ])
            .split(area);

        // Title with repo name
        let title = Paragraph::new(Text::styled(
            format!("Hosts - {}", self.repo_name),
            Style::default().bold().yellow(),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // Hosts list
        if self.hosts.is_empty() {
            let empty_msg = Paragraph::new(Text::styled(
                "No hosts found in flake.nix\n\nPress 'a' to add a new host",
                Style::default().fg(Color::DarkGray),
            ))
            .alignment(Alignment::Center);
            frame.render_widget(empty_msg, chunks[1]);
        } else {
            let items: Vec<ListItem> = self
                .hosts
                .iter()
                .map(|host| {
                    let system_suffix = host
                        .system
                        .as_deref()
                        .map(|s| format!("  ({})", s))
                        .unwrap_or_default();
                    ListItem::new(Line::from(format!("  {}{}", host.name, system_suffix)))
                })
                .collect();

            let list = List::new(items)
                .block(Block::default().borders(Borders::NONE))
                .highlight_style(
                    Style::default()
                        .fg(Color::Green)
                        .add_modifier(Modifier::BOLD),
                )
                .highlight_symbol("> ");

            frame.render_stateful_widget(list, chunks[1], &mut self.list_state);
        }

        // Help text
        let help_text = if self.hosts.is_empty() {
            "a: add host • q: quit"
        } else {
            "↑/↓: navigate • Enter: details • a: add host • q: quit"
        };
        let help = Paragraph::new(Text::styled(
            help_text,
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}
