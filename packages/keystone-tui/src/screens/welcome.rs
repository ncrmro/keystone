use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout},
    style::{Modifier, Style, Stylize},
    text::Text,
    widgets::{Block, Borders, Paragraph},
    Frame,
};

/// The Welcome screen, displayed on first run or when no repos are configured.
#[derive(Default)]
pub struct WelcomeScreen {
    selected_option: WelcomeOption,
}

#[derive(Default, PartialEq, Eq)]
#[allow(dead_code)]
enum WelcomeOption {
    #[default]
    ImportExisting,
    CreateNew,
}

impl WelcomeScreen {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn render(&mut self, frame: &mut Frame, area: ratatui::layout::Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage(30),
                Constraint::Percentage(20),
                Constraint::Percentage(20),
                Constraint::Percentage(30),
            ])
            .split(area);

        let title_block = Paragraph::new(Text::styled(
            "Welcome to Keystone TUI!",
            Style::default().bold().yellow(),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::NONE));
        frame.render_widget(title_block, chunks[0]);

        let import_text = match self.selected_option {
            WelcomeOption::ImportExisting => Text::styled(
                "Import existing repository",
                Style::default().green().add_modifier(Modifier::BOLD),
            ),
            _ => Text::raw("Import existing repository"),
        };
        let import_paragraph = Paragraph::new(import_text)
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::NONE));
        frame.render_widget(import_paragraph, chunks[1]);

        let create_text = match self.selected_option {
            WelcomeOption::CreateNew => Text::styled(
                "Create new repository",
                Style::default().green().add_modifier(Modifier::BOLD),
            ),
            _ => Text::raw("Create new repository"),
        };
        let create_paragraph = Paragraph::new(create_text)
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::NONE));
        frame.render_widget(create_paragraph, chunks[2]);
    }
}
