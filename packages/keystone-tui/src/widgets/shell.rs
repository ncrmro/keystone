//! Shell layout — shared header, sidebar, and help bar for all dashboard screens.
//!
//! Provides a consistent frame so switching between sidebar sections
//! produces no layout shift.

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

/// Layout regions returned by `render_shell`.
pub struct ShellAreas {
    /// The main content area (right of sidebar).
    pub content: Rect,
}

/// Render the shared shell: header, sidebar, help bar.
///
/// Returns the content `Rect` that the active component should render into.
pub fn render_shell(
    frame: &mut Frame,
    area: Rect,
    title: &str,
    subtitle: &str,
    active_sidebar: usize,
    help_text: &str,
    warning: Option<&str>,
) -> ShellAreas {
    let t = crate::theme::default();
    let warning_height: u16 = if warning.is_some() { 1 } else { 0 };

    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(2),              // Header
            Constraint::Length(warning_height), // Warning (0 if none)
            Constraint::Min(5),                 // Sidebar + content
            Constraint::Length(1),              // Help bar
        ])
        .split(area);

    // Header
    let header_line = Line::from(vec![
        Span::styled(title, t.title_style()),
        Span::raw("  "),
        Span::styled(subtitle, t.inactive_style()),
    ]);
    let header = Paragraph::new(header_line)
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
    frame.render_widget(header, rows[0]);

    // Warning banner
    if let Some(msg) = warning {
        let warning_widget = Paragraph::new(Line::from(vec![
            Span::styled(" Warning: ", t.warning_label_style()),
            Span::styled(format!(" {}", msg), t.warning_style()),
        ]));
        frame.render_widget(warning_widget, rows[1]);
    }

    // Sidebar + content columns
    let columns = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Length(14), Constraint::Min(20)])
        .split(rows[2]);

    super::sidebar::render(frame, columns[0], active_sidebar);

    // Help bar
    let help = Paragraph::new(Line::from(Span::styled(help_text, t.inactive_style())))
        .alignment(Alignment::Center);
    frame.render_widget(help, rows[3]);

    ShellAreas {
        content: columns[1],
    }
}
