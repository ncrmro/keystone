//! Selection menu widget for the Keystone TUI.

use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::Text,
    widgets::Paragraph,
    Frame,
};

/// A selectable menu with items.
pub struct SelectMenu<T> {
    items: Vec<MenuItem<T>>,
    selected: usize,
}

/// An item in a selection menu.
pub struct MenuItem<T> {
    pub label: String,
    pub value: T,
}

impl<T> SelectMenu<T> {
    pub fn new(items: Vec<MenuItem<T>>) -> Self {
        Self { items, selected: 0 }
    }

    pub fn selected_index(&self) -> usize {
        self.selected
    }

    pub fn selected_value(&self) -> Option<&T> {
        self.items.get(self.selected).map(|item| &item.value)
    }

    pub fn next(&mut self) {
        if !self.items.is_empty() {
            self.selected = (self.selected + 1) % self.items.len();
        }
    }

    pub fn previous(&mut self) {
        if !self.items.is_empty() {
            self.selected = if self.selected == 0 {
                self.items.len() - 1
            } else {
                self.selected - 1
            };
        }
    }

    /// Render the menu centered in the given area.
    pub fn render(&self, frame: &mut Frame, area: Rect) {
        if self.items.is_empty() {
            return;
        }

        // Create constraints for each item
        let constraints: Vec<Constraint> = self
            .items
            .iter()
            .map(|_| Constraint::Length(1))
            .collect();

        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints(constraints)
            .split(area);

        for (i, item) in self.items.iter().enumerate() {
            let is_selected = i == self.selected;

            let style = if is_selected {
                Style::default()
                    .fg(Color::Green)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };

            let prefix = if is_selected { "> " } else { "  " };
            let text = Text::styled(format!("{}{}", prefix, item.label), style);

            let paragraph = Paragraph::new(text);
            frame.render_widget(paragraph, chunks[i]);
        }
    }
}
