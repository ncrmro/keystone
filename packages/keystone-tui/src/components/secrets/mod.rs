//! Secrets component — agenix secret management.

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
pub struct SecretsScreen;

impl SecretsScreen {
    pub fn new() -> Self {
        Self
    }
}

impl Component for SecretsScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(match key.code {
                KeyCode::Char('q') | KeyCode::Esc => Some(Action::Quit),
                KeyCode::Char('1') => Some(Action::NavigateTo(Screen::Hosts)),
                KeyCode::Char('2') => Some(Action::NavigateTo(Screen::Services)),
                KeyCode::Char('4') => Some(Action::NavigateTo(Screen::Security)),
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

        crate::widgets::sidebar::render(frame, columns[0], 2);

        let text = Paragraph::new(Text::styled(
            "Secrets management — coming soon",
            Style::default().bold().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(text, columns[1]);
        Ok(())
    }
}
