//! Build screen - streams nixos-rebuild build output.

use std::path::PathBuf;
use std::process::Stdio;

use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Style, Stylize},
    text::{Line, Text},
    widgets::{Block, Borders, Paragraph, Wrap},
    Frame,
};

/// Messages sent from the build subprocess to the UI.
pub enum BuildMessage {
    /// A line of output (stdout or stderr).
    Output(String),
    /// Build finished with an exit status.
    Finished(BuildResult),
}

/// The result of a build.
#[derive(Clone)]
pub enum BuildResult {
    Success,
    Failed(i32),
    Cancelled,
    Error(String),
}

/// Screen for running and displaying nixos-rebuild build output.
pub struct BuildScreen {
    /// Host name being built.
    host_name: String,
    /// Lines of build output.
    output_lines: Vec<String>,
    /// Current scroll offset (0 = auto-scroll to bottom).
    scroll_offset: u16,
    /// Whether auto-scroll is active.
    auto_scroll: bool,
    /// Build result when complete.
    result: Option<BuildResult>,
    /// Channel receiver for build output messages.
    rx: mpsc::UnboundedReceiver<BuildMessage>,
    /// Cancellation token for stopping the build.
    cancel_token: CancellationToken,
}

impl BuildScreen {
    /// Start a new build for the given host.
    pub fn new(host_name: String, repo_path: PathBuf) -> Self {
        let (tx, rx) = mpsc::unbounded_channel();
        let cancel_token = CancellationToken::new();
        let token = cancel_token.clone();

        let flake_ref = format!(".#{}", host_name);
        let build_host = host_name.clone();

        // Spawn the build process
        tokio::spawn(async move {
            let child_result = Command::new("nixos-rebuild")
                .arg("build")
                .arg("--flake")
                .arg(&flake_ref)
                .current_dir(&repo_path)
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .kill_on_drop(true)
                .spawn();

            let mut child = match child_result {
                Ok(c) => c,
                Err(e) => {
                    let _ = tx.send(BuildMessage::Finished(BuildResult::Error(format!(
                        "Failed to start nixos-rebuild: {}",
                        e
                    ))));
                    return;
                }
            };

            let _ = tx.send(BuildMessage::Output(format!(
                "$ nixos-rebuild build --flake .#{}",
                build_host
            )));
            let _ = tx.send(BuildMessage::Output(String::new()));

            // Stream stderr (nix build output goes to stderr)
            let stderr = child.stderr.take();
            let stdout = child.stdout.take();

            let tx_stderr = tx.clone();
            let stderr_task = tokio::spawn(async move {
                if let Some(stderr) = stderr {
                    let reader = BufReader::new(stderr);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        if tx_stderr.send(BuildMessage::Output(line)).is_err() {
                            break;
                        }
                    }
                }
            });

            let tx_stdout = tx.clone();
            let stdout_task = tokio::spawn(async move {
                if let Some(stdout) = stdout {
                    let reader = BufReader::new(stdout);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        if tx_stdout.send(BuildMessage::Output(line)).is_err() {
                            break;
                        }
                    }
                }
            });

            // Wait for either completion or cancellation
            tokio::select! {
                status = child.wait() => {
                    let _ = stderr_task.await;
                    let _ = stdout_task.await;

                    let result = match status {
                        Ok(s) if s.success() => BuildResult::Success,
                        Ok(s) => BuildResult::Failed(s.code().unwrap_or(-1)),
                        Err(e) => BuildResult::Error(format!("Process error: {}", e)),
                    };
                    let _ = tx.send(BuildMessage::Finished(result));
                }
                _ = token.cancelled() => {
                    // kill_on_drop will handle cleanup when child is dropped
                    drop(child);
                    let _ = stderr_task.await;
                    let _ = stdout_task.await;
                    let _ = tx.send(BuildMessage::Finished(BuildResult::Cancelled));
                }
            }
        });

        Self {
            host_name,
            output_lines: Vec::new(),
            scroll_offset: 0,
            auto_scroll: true,
            result: None,
            rx,
            cancel_token,
        }
    }

    /// Poll for new messages from the build process (non-blocking).
    pub fn poll(&mut self) {
        while let Ok(msg) = self.rx.try_recv() {
            match msg {
                BuildMessage::Output(line) => {
                    self.output_lines.push(line);
                }
                BuildMessage::Finished(result) => {
                    self.result = Some(result);
                }
            }
        }
    }

    /// Whether the build has completed.
    pub fn is_finished(&self) -> bool {
        self.result.is_some()
    }

    /// Cancel the running build process.
    pub fn cancel(&self) {
        self.cancel_token.cancel();
    }

    /// Scroll up.
    pub fn scroll_up(&mut self) {
        self.auto_scroll = false;
        self.scroll_offset = self.scroll_offset.saturating_add(1);
    }

    /// Scroll down.
    pub fn scroll_down(&mut self) {
        if self.scroll_offset > 0 {
            self.scroll_offset = self.scroll_offset.saturating_sub(1);
            if self.scroll_offset == 0 {
                self.auto_scroll = true;
            }
        }
    }

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),   // Output
                Constraint::Length(3), // Status / Help
            ])
            .split(area);

        // Title
        let status_indicator = match &self.result {
            None => " (building...)",
            Some(BuildResult::Success) => " (success)",
            Some(BuildResult::Failed(_)) => " (failed)",
            Some(BuildResult::Cancelled) => " (cancelled)",
            Some(BuildResult::Error(_)) => " (error)",
        };
        let title_style = match &self.result {
            None => Style::default().bold().yellow(),
            Some(BuildResult::Success) => Style::default().bold().green(),
            _ => Style::default().bold().red(),
        };
        let title = Paragraph::new(Text::styled(
            format!("Building: {}{}", self.host_name, status_indicator),
            title_style,
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // Output area
        let output_height = chunks[1].height.saturating_sub(2) as usize; // subtract borders
        let total_lines = self.output_lines.len();

        let scroll = if self.auto_scroll {
            total_lines.saturating_sub(output_height) as u16
        } else {
            let max_scroll = total_lines.saturating_sub(output_height) as u16;
            max_scroll.saturating_sub(self.scroll_offset)
        };

        let output_lines: Vec<Line> = self
            .output_lines
            .iter()
            .map(|line| Line::from(line.as_str()))
            .collect();

        let output = Paragraph::new(output_lines)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::DarkGray)),
            )
            .wrap(Wrap { trim: false })
            .scroll((scroll, 0));
        frame.render_widget(output, chunks[1]);

        // Help text
        let help_text = if self.is_finished() {
            "Esc: back • q: quit"
        } else {
            "↑/↓: scroll • Esc: cancel"
        };
        let help = Paragraph::new(Text::styled(
            help_text,
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}
