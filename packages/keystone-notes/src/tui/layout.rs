use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::widgets::{Block, Borders, Paragraph};
use ratatui::Frame;
use super::state::AppState;

pub fn ui(f: &mut Frame, app: &AppState) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints(
            [
                Constraint::Percentage(10),
                Constraint::Percentage(80),
                Constraint::Percentage(10),
            ]
            .as_ref(),
        )
        .split(f.area());

    let title = Paragraph::new("Keystone Notes Agent").block(Block::default().borders(Borders::ALL));
    f.render_widget(title, chunks[0]);
    
    let jobs_text = app.jobs.join("\n");
    let content = Paragraph::new(jobs_text).block(Block::default().title("Jobs").borders(Borders::ALL));
    f.render_widget(content, chunks[1]);
    
    let footer = Paragraph::new("Press 'q' to quit").block(Block::default().borders(Borders::ALL));
    f.render_widget(footer, chunks[2]);
}