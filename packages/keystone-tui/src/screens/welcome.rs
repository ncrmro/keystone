use crate::ui::TextInput;
use crossterm::event::KeyEvent;
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Text},
    widgets::{Block, Borders, Clear, Paragraph},
    Frame,
};

/// The Welcome screen, displayed on first run or when no repos are configured.
pub struct WelcomeScreen {
    state: WelcomeState,
    selected_option: WelcomeOption,
    git_url_input: TextInput,
    repo_name_input: TextInput,
    error_message: Option<String>,
    success_message: Option<String>,
}

/// State machine for the welcome screen flow.
#[derive(Default, PartialEq, Eq, Clone)]
pub enum WelcomeState {
    #[default]
    SelectAction,
    InputGitUrl,
    InputRepoName,
    Importing,
    Creating,
    Success,
    Error,
}

#[derive(Default, PartialEq, Eq, Clone, Copy)]
pub enum WelcomeOption {
    #[default]
    ImportExisting,
    CreateNew,
}

/// Result from handling input on the welcome screen.
pub enum WelcomeAction {
    None,
    ImportRepo { name: String, git_url: String },
    CreateRepo { name: String },
    /// User acknowledged success - app should transition to repos view
    Complete,
}

impl Default for WelcomeScreen {
    fn default() -> Self {
        Self::new()
    }
}

impl WelcomeScreen {
    pub fn new() -> Self {
        Self {
            state: WelcomeState::SelectAction,
            selected_option: WelcomeOption::ImportExisting,
            git_url_input: TextInput::new().with_placeholder("https://github.com/user/repo.git"),
            repo_name_input: TextInput::new().with_placeholder("my-infrastructure"),
            error_message: None,
            success_message: None,
        }
    }

    pub fn state(&self) -> &WelcomeState {
        &self.state
    }

    pub fn next(&mut self) {
        if self.state == WelcomeState::SelectAction {
            self.selected_option = match self.selected_option {
                WelcomeOption::ImportExisting => WelcomeOption::CreateNew,
                WelcomeOption::CreateNew => WelcomeOption::ImportExisting,
            };
        }
    }

    pub fn previous(&mut self) {
        if self.state == WelcomeState::SelectAction {
            self.selected_option = match self.selected_option {
                WelcomeOption::ImportExisting => WelcomeOption::CreateNew,
                WelcomeOption::CreateNew => WelcomeOption::ImportExisting,
            };
        }
    }

    pub fn get_selected_option(&self) -> WelcomeOption {
        self.selected_option
    }

    /// Handle Enter key press, returning an action to perform.
    pub fn confirm(&mut self) -> WelcomeAction {
        match self.state {
            WelcomeState::SelectAction => {
                match self.selected_option {
                    WelcomeOption::ImportExisting => {
                        self.state = WelcomeState::InputGitUrl;
                        self.git_url_input.set_focused(true);
                    }
                    WelcomeOption::CreateNew => {
                        self.state = WelcomeState::InputRepoName;
                        self.repo_name_input.set_focused(true);
                    }
                }
                WelcomeAction::None
            }
            WelcomeState::InputGitUrl => {
                let git_url = self.git_url_input.value().to_string();
                if git_url.is_empty() {
                    self.error_message = Some("Git URL cannot be empty".to_string());
                    self.state = WelcomeState::Error;
                    return WelcomeAction::None;
                }
                // Extract repo name from URL
                let name = extract_repo_name(&git_url).unwrap_or_else(|| "keystone-config".to_string());
                self.state = WelcomeState::Importing;
                WelcomeAction::ImportRepo { name, git_url }
            }
            WelcomeState::InputRepoName => {
                let name = self.repo_name_input.value().to_string();
                if name.is_empty() {
                    self.error_message = Some("Repository name cannot be empty".to_string());
                    self.state = WelcomeState::Error;
                    return WelcomeAction::None;
                }
                self.state = WelcomeState::Creating;
                WelcomeAction::CreateRepo { name }
            }
            WelcomeState::Error => {
                // Dismiss error and go back to appropriate state
                self.error_message = None;
                self.state = WelcomeState::SelectAction;
                WelcomeAction::None
            }
            WelcomeState::Success => {
                // User acknowledged success - signal app to transition
                WelcomeAction::Complete
            }
            _ => WelcomeAction::None,
        }
    }

    /// Handle Escape key press.
    pub fn cancel(&mut self) {
        match self.state {
            WelcomeState::InputGitUrl | WelcomeState::InputRepoName => {
                self.git_url_input.set_focused(false);
                self.repo_name_input.set_focused(false);
                self.state = WelcomeState::SelectAction;
            }
            WelcomeState::Error => {
                self.error_message = None;
                self.state = WelcomeState::SelectAction;
            }
            _ => {}
        }
    }

    /// Handle text input for the current state.
    pub fn handle_text_input(&mut self, key: KeyEvent) -> bool {
        match self.state {
            WelcomeState::InputGitUrl => self.git_url_input.handle_key(key),
            WelcomeState::InputRepoName => self.repo_name_input.handle_key(key),
            _ => false,
        }
    }

    /// Called when import/create operation completes successfully.
    pub fn set_success(&mut self, message: String) {
        self.success_message = Some(message);
        self.state = WelcomeState::Success;
    }

    /// Called when import/create operation fails.
    pub fn set_error(&mut self, message: String) {
        self.error_message = Some(message);
        self.state = WelcomeState::Error;
    }

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        match self.state {
            WelcomeState::SelectAction => self.render_select_action(frame, area),
            WelcomeState::InputGitUrl => self.render_input_git_url(frame, area),
            WelcomeState::InputRepoName => self.render_input_repo_name(frame, area),
            WelcomeState::Importing => self.render_loading(frame, area, "Cloning repository..."),
            WelcomeState::Creating => self.render_loading(frame, area, "Creating repository from template..."),
            WelcomeState::Success => self.render_success(frame, area),
            WelcomeState::Error => self.render_error(frame, area),
        }
    }

    fn render_select_action(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage(30),
                Constraint::Length(3),
                Constraint::Length(3),
                Constraint::Percentage(30),
                Constraint::Min(0),
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled(
            "Welcome to Keystone TUI!",
            Style::default().bold().yellow(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        // Import option
        let import_style = if self.selected_option == WelcomeOption::ImportExisting {
            Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)
        } else {
            Style::default()
        };
        let import_prefix = if self.selected_option == WelcomeOption::ImportExisting { "> " } else { "  " };
        let import_text = Paragraph::new(format!("{}Import existing repository", import_prefix))
            .style(import_style)
            .alignment(Alignment::Center);
        frame.render_widget(import_text, chunks[1]);

        // Create option
        let create_style = if self.selected_option == WelcomeOption::CreateNew {
            Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)
        } else {
            Style::default()
        };
        let create_prefix = if self.selected_option == WelcomeOption::CreateNew { "> " } else { "  " };
        let create_text = Paragraph::new(format!("{}Create new repository", create_prefix))
            .style(create_style)
            .alignment(Alignment::Center);
        frame.render_widget(create_text, chunks[2]);

        // Help text
        let help = Paragraph::new(Text::styled(
            "↑/↓ or j/k to navigate • Enter to select • q to quit",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[3]);
    }

    fn render_input_git_url(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage(30),
                Constraint::Length(3),
                Constraint::Length(3),
                Constraint::Min(0),
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled(
            "Import Existing Repository",
            Style::default().bold().yellow(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        // Input area (centered)
        let input_area = centered_rect(60, 3, chunks[1]);
        self.git_url_input.render(frame, input_area, "Git URL");

        // Help text
        let help = Paragraph::new(Text::styled(
            "Enter to confirm • Esc to cancel",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_input_repo_name(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage(30),
                Constraint::Length(3),
                Constraint::Length(3),
                Constraint::Min(0),
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled(
            "Create New Repository",
            Style::default().bold().yellow(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(title, chunks[0]);

        // Input area (centered)
        let input_area = centered_rect(60, 3, chunks[1]);
        self.repo_name_input.render(frame, input_area, "Repository Name");

        // Help text
        let help = Paragraph::new(Text::styled(
            "Enter to confirm • Esc to cancel",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_loading(&self, frame: &mut Frame, area: Rect, message: &str) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage(45),
                Constraint::Length(3),
                Constraint::Percentage(45),
            ])
            .split(area);

        let loading = Paragraph::new(Text::styled(
            message,
            Style::default().fg(Color::Yellow),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(loading, chunks[1]);
    }

    fn render_success(&self, frame: &mut Frame, area: Rect) {
        let popup_area = centered_rect(60, 20, area);
        frame.render_widget(Clear, popup_area);

        let message = self.success_message.as_deref().unwrap_or("Operation completed successfully!");
        let lines: Vec<Line> = vec![
            Line::from("").style(Style::default()),
            Line::from("✓ Success!").style(Style::default().fg(Color::Green).bold()),
            Line::from("").style(Style::default()),
            Line::from(message).style(Style::default()),
            Line::from("").style(Style::default()),
            Line::from("Press Enter to continue").style(Style::default().fg(Color::DarkGray)),
        ];

        let paragraph = Paragraph::new(lines)
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::Green)));
        frame.render_widget(paragraph, popup_area);
    }

    fn render_error(&self, frame: &mut Frame, area: Rect) {
        let popup_area = centered_rect(60, 20, area);
        frame.render_widget(Clear, popup_area);

        let message = self.error_message.as_deref().unwrap_or("An error occurred");
        let lines: Vec<Line> = vec![
            Line::from("").style(Style::default()),
            Line::from("✗ Error").style(Style::default().fg(Color::Red).bold()),
            Line::from("").style(Style::default()),
            Line::from(message).style(Style::default()),
            Line::from("").style(Style::default()),
            Line::from("Press Enter or Esc to dismiss").style(Style::default().fg(Color::DarkGray)),
        ];

        let paragraph = Paragraph::new(lines)
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::Red)));
        frame.render_widget(paragraph, popup_area);
    }
}

/// Extract repository name from a git URL.
fn extract_repo_name(url: &str) -> Option<String> {
    // Handle both HTTPS and SSH URLs
    // https://github.com/user/repo.git -> repo
    // git@github.com:user/repo.git -> repo
    let url = url.trim_end_matches(".git");
    url.rsplit('/').next()
        .or_else(|| url.rsplit(':').next())
        .map(|s| s.to_string())
}

/// Create a centered rectangle within the given area.
fn centered_rect(percent_x: u16, height: u16, area: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(area);

    Rect {
        x: popup_layout[1].x,
        y: popup_layout[1].y,
        width: popup_layout[1].width,
        height: height.min(popup_layout[1].height),
    }
}
