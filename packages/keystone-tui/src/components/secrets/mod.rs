//! Secrets component — agenix secret management.
//!
//! List, create, rotate, and re-key agenix-encrypted secrets.
//! Future: types.rs + run.rs for CLI/JSON shared logic.

use crate::action::Action;
use crate::component::Component;
use crossterm::event::{Event, KeyCode, KeyEventKind};
use ratatui::{
    layout::{Alignment, Rect},
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
            match key.code {
                KeyCode::Char('q') => return Ok(Some(Action::Quit)),
                KeyCode::Esc => return Ok(Some(Action::GoBack)),
                _ => {}
            }
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        let text = Paragraph::new(Text::styled(
            "Secrets management — coming soon",
            Style::default().bold().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(text, area);
        Ok(())
    }
}
