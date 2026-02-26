//! Host detail screen - displays configuration summary for a single host.

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Style, Stylize},
    text::{Line, Span, Text},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

use crate::nix::HostInfo;

/// Screen displaying details about a single NixOS host configuration.
pub struct HostDetailScreen {
    /// The host info being displayed.
    host: HostInfo,
}

impl HostDetailScreen {
    pub fn new(host: HostInfo) -> Self {
        Self { host }
    }

    pub fn host(&self) -> &HostInfo {
        &self.host
    }

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),   // Details
                Constraint::Length(3), // Help
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled(
            format!("Host: {}", self.host.name),
            Style::default().bold().yellow(),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // Details
        let mut lines: Vec<Line> = Vec::new();
        lines.push(Line::from(""));

        // System
        let system_value = self.host.system.as_deref().unwrap_or("unknown");
        lines.push(Line::from(vec![
            Span::styled("  System:     ", Style::default().fg(Color::DarkGray)),
            Span::styled(system_value, Style::default().fg(Color::White)),
        ]));

        lines.push(Line::from(""));

        // Keystone modules
        if self.host.keystone_modules.is_empty() {
            lines.push(Line::from(vec![
                Span::styled("  Modules:    ", Style::default().fg(Color::DarkGray)),
                Span::styled("(none)", Style::default().fg(Color::DarkGray)),
            ]));
        } else {
            for (i, module) in self.host.keystone_modules.iter().enumerate() {
                let label = if i == 0 { "  Modules:    " } else { "              " };
                lines.push(Line::from(vec![
                    Span::styled(label, Style::default().fg(Color::DarkGray)),
                    Span::styled(module.as_str(), Style::default().fg(Color::Green)),
                ]));
            }
        }

        lines.push(Line::from(""));

        // Config files
        if self.host.config_files.is_empty() {
            lines.push(Line::from(vec![
                Span::styled("  Config:     ", Style::default().fg(Color::DarkGray)),
                Span::styled("(none)", Style::default().fg(Color::DarkGray)),
            ]));
        } else {
            for (i, path) in self.host.config_files.iter().enumerate() {
                let label = if i == 0 { "  Config:     " } else { "              " };
                lines.push(Line::from(vec![
                    Span::styled(label, Style::default().fg(Color::DarkGray)),
                    Span::styled(path.as_str(), Style::default().fg(Color::Cyan)),
                ]));
            }
        }

        let details = Paragraph::new(lines)
            .block(Block::default().borders(Borders::NONE));
        frame.render_widget(details, chunks[1]);

        // Help text
        let help = Paragraph::new(Text::styled(
            "b: build • Esc: back • q: quit",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}
