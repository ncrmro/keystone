//! Services component — keystoneServices host placement.
//!
//! View and edit which hosts run which Keystone services.
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
pub struct ServicesScreen;

impl ServicesScreen {
    pub fn new() -> Self {
        Self
    }
}

impl Component for ServicesScreen {
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
            "Service placement — coming soon",
            Style::default().bold().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(text, area);
        Ok(())
    }
}
