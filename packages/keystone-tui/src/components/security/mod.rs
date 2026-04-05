//! Security component — hardware security enrollment.

pub mod secure_boot;
pub mod tpm;
pub mod yubikey;

use crate::action::{Action, Screen};
use crate::component::Component;
use crossterm::event::{Event, KeyCode, KeyEventKind};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Style, Stylize},
    text::Text,
    widgets::Paragraph,
    Frame,
};

#[derive(Default)]
pub struct SecurityScreen;

impl SecurityScreen {
    pub fn new() -> Self {
        Self
    }
}

impl Component for SecurityScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(match key.code {
                KeyCode::Char('q') | KeyCode::Esc => Some(Action::Quit),
                KeyCode::Char('1') => Some(Action::NavigateTo(Screen::Hosts)),
                KeyCode::Char('2') => Some(Action::NavigateTo(Screen::Services)),
                KeyCode::Char('3') => Some(Action::NavigateTo(Screen::Secrets)),
                _ => None,
            });
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        let columns = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Length(14), Constraint::Min(20)])
            .split(area);

        crate::widgets::sidebar::render(frame, columns[0], 3);

        let text = Paragraph::new(Text::styled(
            "Security enrollment — coming soon",
            Style::default().bold().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(text, columns[1]);
        Ok(())
    }
}
