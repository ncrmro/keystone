//! Text input widget for the Keystone TUI.

use crossterm::event::{KeyCode, KeyEvent};
use ratatui::{
    layout::Rect,
    style::{Color, Style},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

/// A simple text input field.
#[derive(Default, Clone)]
pub struct TextInput {
    /// The current input value.
    value: String,
    /// Cursor position within the input.
    cursor_position: usize,
    /// Placeholder text shown when empty.
    placeholder: String,
    /// Whether the input is focused.
    focused: bool,
}

impl TextInput {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_placeholder(mut self, placeholder: impl Into<String>) -> Self {
        self.placeholder = placeholder.into();
        self
    }

    pub fn value(&self) -> &str {
        &self.value
    }

    pub fn set_value(&mut self, value: impl Into<String>) {
        self.value = value.into();
        self.cursor_position = self.value.len();
    }

    pub fn clear(&mut self) {
        self.value.clear();
        self.cursor_position = 0;
    }

    pub fn set_focused(&mut self, focused: bool) {
        self.focused = focused;
    }

    pub fn is_focused(&self) -> bool {
        self.focused
    }

    /// Handle a key event, returning true if the event was consumed.
    pub fn handle_key(&mut self, key: KeyEvent) -> bool {
        match key.code {
            KeyCode::Char(c) => {
                self.value.insert(self.cursor_position, c);
                self.cursor_position += 1;
                true
            }
            KeyCode::Backspace => {
                if self.cursor_position > 0 {
                    self.cursor_position -= 1;
                    self.value.remove(self.cursor_position);
                }
                true
            }
            KeyCode::Delete => {
                if self.cursor_position < self.value.len() {
                    self.value.remove(self.cursor_position);
                }
                true
            }
            KeyCode::Left => {
                if self.cursor_position > 0 {
                    self.cursor_position -= 1;
                }
                true
            }
            KeyCode::Right => {
                if self.cursor_position < self.value.len() {
                    self.cursor_position += 1;
                }
                true
            }
            KeyCode::Home => {
                self.cursor_position = 0;
                true
            }
            KeyCode::End => {
                self.cursor_position = self.value.len();
                true
            }
            _ => false,
        }
    }

    /// Render the text input widget.
    pub fn render(&self, frame: &mut Frame, area: Rect, title: &str) {
        let display_text = if self.value.is_empty() && !self.focused {
            self.placeholder.clone()
        } else {
            self.value.clone()
        };

        let style = if self.focused {
            Style::default().fg(Color::Yellow)
        } else if self.value.is_empty() {
            Style::default().fg(Color::DarkGray)
        } else {
            Style::default()
        };

        let border_style = if self.focused {
            Style::default().fg(Color::Yellow)
        } else {
            Style::default()
        };

        let block = Block::default()
            .title(title)
            .borders(Borders::ALL)
            .border_style(border_style);

        let paragraph = Paragraph::new(display_text).style(style).block(block);

        frame.render_widget(paragraph, area);

        // Show cursor when focused
        if self.focused {
            let cursor_x = area.x + 1 + self.cursor_position as u16;
            let cursor_y = area.y + 1;
            if cursor_x < area.x + area.width - 1 {
                frame.set_cursor_position((cursor_x, cursor_y));
            }
        }
    }
}
