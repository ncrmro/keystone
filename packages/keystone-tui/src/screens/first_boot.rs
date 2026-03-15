//! First-boot screen — post-install setup wizard.
//!
//! After a fresh Keystone install, on first boot the TUI detects a
//! `.first-boot-pending` marker in `~/.keystone/repos/nixos-config/` and
//! walks the user through:
//!
//! 1. Generating real hardware.nix
//! 2. Initializing a git repo with the config
//! 3. Showing the SSH public key for GitHub
//! 4. Setting up a git remote and pushing

use std::path::{Path, PathBuf};

use tokio::process::Command;
use tokio::sync::mpsc;

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Span, Text},
    widgets::{Block, Borders, Paragraph, Wrap},
    Frame,
};

use crate::ui::TextInput;

/// Configuration for the first-boot flow.
#[derive(Debug, Clone)]
pub struct FirstBootConfig {
    pub config_dir: PathBuf,
    pub hostname: String,
    pub username: String,
    pub github_username: Option<String>,
}

impl FirstBootConfig {
    /// Detect first-boot mode by looking for the marker file.
    pub fn detect() -> Option<Self> {
        let home = home::home_dir()?;
        let config_dir = home.join(".keystone").join("repos").join("nixos-config");
        let marker = config_dir.join(".first-boot-pending");

        if !marker.exists() {
            return None;
        }

        // Read hostname from the config
        let hostname = std::fs::read_to_string("/etc/hostname")
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "keystone".to_string());

        // Read username from embedded metadata or current user
        let username = std::fs::read_to_string("/etc/keystone/install-config/username")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| std::env::var("USER").unwrap_or_else(|_| "user".to_string()));

        let github_username =
            std::fs::read_to_string("/etc/keystone/install-config/github_username")
                .ok()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty());

        Some(Self {
            config_dir,
            hostname,
            username,
            github_username,
        })
    }
}

/// Phases of the first-boot wizard.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FirstBootPhase {
    /// Welcome message.
    Welcome,
    /// Generating hardware.nix via nixos-generate-config.
    GeneratingHardware,
    /// git init + add + commit.
    GitSetup,
    /// Display SSH public key + GitHub instructions.
    ShowSshKey,
    /// Text input for git remote URL.
    RemoteInput,
    /// Pushing to remote.
    Pushing,
    /// Setup complete.
    Done,
    /// An error occurred.
    Failed(String),
}

/// Messages from first-boot async operations.
pub enum FirstBootMessage {
    Output(String),
    HardwareGenerated,
    GitReady,
    SshKey(String),
    PushResult(Result<(), String>),
    Failed(String),
}

pub struct FirstBootScreen {
    config: FirstBootConfig,
    phase: FirstBootPhase,
    output_lines: Vec<String>,
    ssh_public_key: Option<String>,
    remote_input: TextInput,
    rx: Option<mpsc::UnboundedReceiver<FirstBootMessage>>,
    push_skipped: bool,
}

impl FirstBootScreen {
    pub fn new(config: FirstBootConfig) -> Self {
        let default_remote = config
            .github_username
            .as_ref()
            .map(|gh| format!("git@github.com:{}/nixos-config.git", gh))
            .unwrap_or_default();

        let mut remote_input =
            TextInput::new().with_placeholder("git@github.com:user/nixos-config.git");
        if !default_remote.is_empty() {
            remote_input.set_value(&default_remote);
        }

        Self {
            config,
            phase: FirstBootPhase::Welcome,
            output_lines: Vec::new(),
            ssh_public_key: None,
            remote_input,
            rx: None,
            push_skipped: false,
        }
    }

    pub fn phase(&self) -> &FirstBootPhase {
        &self.phase
    }

    pub fn ssh_public_key(&self) -> Option<&str> {
        self.ssh_public_key.as_deref()
    }

    /// Start the first-boot process (Welcome → GeneratingHardware).
    pub fn start(&mut self) {
        if self.phase != FirstBootPhase::Welcome {
            return;
        }
        self.phase = FirstBootPhase::GeneratingHardware;
        self.spawn_hardware_generation();
    }

    fn spawn_hardware_generation(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let config_dir = self.config.config_dir.clone();

        tokio::spawn(async move {
            let _ = tx.send(FirstBootMessage::Output(
                "Generating hardware configuration...".to_string(),
            ));

            let output = Command::new("nixos-generate-config")
                .args(["--show-hardware-config"])
                .output()
                .await;

            match output {
                Ok(out) if out.status.success() => {
                    let hw_config = String::from_utf8_lossy(&out.stdout).to_string();
                    let hw_path = config_dir.join("hardware.nix");
                    if let Err(e) = tokio::fs::write(&hw_path, &hw_config).await {
                        let _ = tx.send(FirstBootMessage::Failed(format!(
                            "Failed to write hardware.nix: {}",
                            e
                        )));
                        return;
                    }
                    let _ = tx.send(FirstBootMessage::Output(
                        "hardware.nix generated successfully.".to_string(),
                    ));
                    let _ = tx.send(FirstBootMessage::HardwareGenerated);
                }
                Ok(out) => {
                    let stderr = String::from_utf8_lossy(&out.stderr);
                    let _ = tx.send(FirstBootMessage::Failed(format!(
                        "nixos-generate-config failed: {}",
                        stderr
                    )));
                }
                Err(e) => {
                    let _ = tx.send(FirstBootMessage::Failed(format!(
                        "Failed to run nixos-generate-config: {}",
                        e
                    )));
                }
            }
        });
    }

    fn spawn_git_setup(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let config_dir = self.config.config_dir.clone();

        tokio::spawn(async move {
            let _ = tx.send(FirstBootMessage::Output(
                "Initializing git repository...".to_string(),
            ));

            // git init with explicit branch name to match subsequent push
            let init = Command::new("git")
                .args(["init", "-b", "main"])
                .current_dir(&config_dir)
                .output()
                .await;

            if let Err(e) = init {
                let _ = tx.send(FirstBootMessage::Failed(format!("git init failed: {}", e)));
                return;
            }

            // Remove .first-boot-pending from tracking (don't commit it)
            let _ = Command::new("git")
                .args(["rm", "--cached", "-f", ".first-boot-pending"])
                .current_dir(&config_dir)
                .output()
                .await;

            // Add .gitignore to exclude the marker
            let gitignore_path = config_dir.join(".gitignore");
            let _ = tokio::fs::write(&gitignore_path, ".first-boot-pending\n").await;

            // git add .
            let add = Command::new("git")
                .args(["add", "."])
                .current_dir(&config_dir)
                .output()
                .await;

            if let Err(e) = add {
                let _ = tx.send(FirstBootMessage::Failed(format!("git add failed: {}", e)));
                return;
            }

            // git commit
            let commit = Command::new("git")
                .args(["commit", "-m", "feat: initial Keystone configuration"])
                .current_dir(&config_dir)
                .output()
                .await;

            match commit {
                Ok(out) if out.status.success() => {
                    let _ = tx.send(FirstBootMessage::Output(
                        "Git repository initialized with initial commit.".to_string(),
                    ));
                    let _ = tx.send(FirstBootMessage::GitReady);
                }
                Ok(out) => {
                    let stderr = String::from_utf8_lossy(&out.stderr);
                    let _ = tx.send(FirstBootMessage::Failed(format!(
                        "git commit failed: {}",
                        stderr
                    )));
                }
                Err(e) => {
                    let _ = tx.send(FirstBootMessage::Failed(format!(
                        "git commit failed: {}",
                        e
                    )));
                }
            }
        });
    }

    fn spawn_ssh_key_check(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let username = self.config.username.clone();

        tokio::spawn(async move {
            let home = home::home_dir().unwrap_or_else(|| PathBuf::from("/root"));
            let pub_key_path = home.join(".ssh").join("id_ed25519.pub");

            if !pub_key_path.exists() {
                let _ = tx.send(FirstBootMessage::Output(
                    "Generating SSH key...".to_string(),
                ));

                let hostname = tokio::fs::read_to_string("/etc/hostname")
                    .await
                    .unwrap_or_else(|_| "keystone".to_string());
                let hostname = hostname.trim();

                let keygen = Command::new("ssh-keygen")
                    .args([
                        "-t",
                        "ed25519",
                        "-N",
                        "",
                        "-C",
                        &format!("{}@{}", username, hostname),
                        "-f",
                        &home.join(".ssh").join("id_ed25519").display().to_string(),
                    ])
                    .output()
                    .await;

                if let Err(e) = keygen {
                    let _ = tx.send(FirstBootMessage::Failed(format!(
                        "ssh-keygen failed: {}",
                        e
                    )));
                    return;
                }
            }

            match tokio::fs::read_to_string(&pub_key_path).await {
                Ok(key) => {
                    let _ = tx.send(FirstBootMessage::SshKey(key.trim().to_string()));
                }
                Err(e) => {
                    let _ = tx.send(FirstBootMessage::Failed(format!(
                        "Failed to read SSH public key: {}",
                        e
                    )));
                }
            }
        });
    }

    fn spawn_push(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let config_dir = self.config.config_dir.clone();
        let remote_url = self.remote_input.value().to_string();

        tokio::spawn(async move {
            let _ = tx.send(FirstBootMessage::Output(format!(
                "Adding remote: {}",
                remote_url
            )));

            // Check if remote already exists
            let remote_check = Command::new("git")
                .args(["remote", "get-url", "origin"])
                .current_dir(&config_dir)
                .output()
                .await;

            let remote_exists = remote_check.map(|o| o.status.success()).unwrap_or(false);

            if remote_exists {
                let _ = Command::new("git")
                    .args(["remote", "set-url", "origin", &remote_url])
                    .current_dir(&config_dir)
                    .output()
                    .await;
            } else {
                let add = Command::new("git")
                    .args(["remote", "add", "origin", &remote_url])
                    .current_dir(&config_dir)
                    .output()
                    .await;

                if let Err(e) = add {
                    let _ = tx.send(FirstBootMessage::PushResult(Err(format!(
                        "git remote add failed: {}",
                        e
                    ))));
                    return;
                }
            }

            let _ = tx.send(FirstBootMessage::Output("Pushing to remote...".to_string()));

            let push = Command::new("git")
                .args(["push", "-u", "origin", "main"])
                .current_dir(&config_dir)
                .output()
                .await;

            match push {
                Ok(out) if out.status.success() => {
                    let _ = tx.send(FirstBootMessage::PushResult(Ok(())));
                }
                Ok(out) => {
                    let stderr = String::from_utf8_lossy(&out.stderr);
                    let _ = tx.send(FirstBootMessage::PushResult(Err(format!(
                        "git push failed: {}",
                        stderr
                    ))));
                }
                Err(e) => {
                    let _ = tx.send(FirstBootMessage::PushResult(Err(format!(
                        "git push failed: {}",
                        e
                    ))));
                }
            }
        });
    }

    /// Skip the current step (SSH key display or push).
    pub fn skip(&mut self) {
        match self.phase {
            FirstBootPhase::ShowSshKey => {
                self.phase = FirstBootPhase::RemoteInput;
                self.remote_input.set_focused(true);
            }
            FirstBootPhase::RemoteInput => {
                self.push_skipped = true;
                self.finish();
            }
            FirstBootPhase::Pushing => {
                self.push_skipped = true;
                self.finish();
            }
            _ => {}
        }
    }

    /// Continue from ShowSshKey to RemoteInput.
    pub fn continue_to_remote(&mut self) {
        if self.phase == FirstBootPhase::ShowSshKey {
            self.phase = FirstBootPhase::RemoteInput;
            self.remote_input.set_focused(true);
        }
    }

    /// Submit the remote URL and start pushing.
    pub fn submit_remote(&mut self) {
        if self.phase != FirstBootPhase::RemoteInput {
            return;
        }
        let url = self.remote_input.value().to_string();
        if url.is_empty() {
            self.push_skipped = true;
            self.finish();
            return;
        }
        self.phase = FirstBootPhase::Pushing;
        self.spawn_push();
    }

    /// Retry a failed push.
    pub fn retry_push(&mut self) {
        if matches!(self.phase, FirstBootPhase::Failed(_)) {
            self.phase = FirstBootPhase::Pushing;
            self.spawn_push();
        }
    }

    /// Handle text input for the remote URL field.
    pub fn handle_text_input(&mut self, key: crossterm::event::KeyEvent) {
        if self.phase == FirstBootPhase::RemoteInput {
            self.remote_input.handle_key(key);
        }
    }

    fn finish(&mut self) {
        // Remove the first-boot marker
        let marker = self.config.config_dir.join(".first-boot-pending");
        let _ = std::fs::remove_file(&marker);
        self.phase = FirstBootPhase::Done;
    }

    /// Poll for async messages.
    pub fn poll(&mut self) {
        let rx = match self.rx.as_mut() {
            Some(rx) => rx,
            None => return,
        };

        // Collect messages to avoid borrow conflicts when spawning follow-up tasks
        let mut messages = Vec::new();
        while let Ok(msg) = rx.try_recv() {
            messages.push(msg);
        }

        for msg in messages {
            match msg {
                FirstBootMessage::Output(line) => {
                    self.output_lines.push(line);
                }
                FirstBootMessage::HardwareGenerated => {
                    self.phase = FirstBootPhase::GitSetup;
                    self.spawn_git_setup();
                }
                FirstBootMessage::GitReady => {
                    self.phase = FirstBootPhase::ShowSshKey;
                    self.spawn_ssh_key_check();
                }
                FirstBootMessage::SshKey(key) => {
                    self.ssh_public_key = Some(key);
                }
                FirstBootMessage::PushResult(Ok(())) => {
                    self.output_lines.push("Push successful!".to_string());
                    self.finish();
                }
                FirstBootMessage::PushResult(Err(e)) => {
                    self.output_lines.push(format!("Push failed: {}", e));
                    self.phase = FirstBootPhase::Failed(e);
                }
                FirstBootMessage::Failed(e) => {
                    self.phase = FirstBootPhase::Failed(e);
                }
            }
        }
    }

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        match &self.phase {
            FirstBootPhase::Welcome => self.render_welcome(frame, area),
            FirstBootPhase::GeneratingHardware | FirstBootPhase::GitSetup => {
                self.render_progress(frame, area)
            }
            FirstBootPhase::ShowSshKey => self.render_ssh_key(frame, area),
            FirstBootPhase::RemoteInput => self.render_remote_input(frame, area),
            FirstBootPhase::Pushing => self.render_progress(frame, area),
            FirstBootPhase::Done => self.render_done(frame, area),
            FirstBootPhase::Failed(err) => self.render_failed(frame, area, err),
        }
    }

    fn render_welcome(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Welcome to Keystone!",
            Style::default().bold().fg(Color::Green),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let message = Paragraph::new(Text::styled(
            format!(
                "\n  Your system '{}' has been installed.\n\n  \
                 This wizard will:\n  \
                 1. Generate hardware.nix for this machine\n  \
                 2. Initialize a git repository\n  \
                 3. Help you push your config to GitHub\n",
                self.config.hostname
            ),
            Style::default(),
        ))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green)),
        );
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: begin setup • q: skip setup",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_progress(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let phase_label = match &self.phase {
            FirstBootPhase::GeneratingHardware => "Generating hardware configuration...",
            FirstBootPhase::GitSetup => "Setting up git repository...",
            FirstBootPhase::Pushing => "Pushing to remote...",
            _ => "Working...",
        };

        let title = Paragraph::new(Text::styled(phase_label, Style::default().bold().yellow()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let output_lines: Vec<Line> = self
            .output_lines
            .iter()
            .map(|line| Line::from(format!("  {}", line)))
            .collect();

        let output = Paragraph::new(output_lines)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::DarkGray)),
            )
            .wrap(Wrap { trim: false });
        frame.render_widget(output, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Please wait...",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_ssh_key(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "SSH Public Key",
            Style::default().bold().fg(Color::Green),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let key_display = self.ssh_public_key.as_deref().unwrap_or("Loading...");

        let message = Paragraph::new(Text::from(vec![
            Line::from(""),
            Line::from("  Add this SSH key to GitHub:"),
            Line::from("  https://github.com/settings/keys"),
            Line::from(""),
            Line::from(Span::styled(
                format!("  {}", key_display),
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            )),
            Line::from(""),
        ]))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green)),
        )
        .wrap(Wrap { trim: false });
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: continue to remote setup • s: skip push",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_remote_input(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Length(5),
                Constraint::Min(3),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Git Remote",
            Style::default().bold().fg(Color::Green),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let instructions = Paragraph::new(Text::from(vec![
            Line::from(""),
            Line::from("  Enter the git remote URL for your config repository:"),
            Line::from(""),
        ]))
        .block(Block::default());
        frame.render_widget(instructions, chunks[1]);

        self.remote_input.render(frame, chunks[2], "Remote URL");

        let help = Paragraph::new(Text::styled(
            "Enter: push • s: skip push",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[3]);
    }

    fn render_done(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Setup Complete!",
            Style::default().bold().fg(Color::Green),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let push_status = if self.push_skipped {
            "  Push: skipped (you can push manually later)"
        } else {
            "  Push: successful"
        };

        let message = Paragraph::new(Text::from(vec![
            Line::from(""),
            Line::from(format!("  Config: {}", self.config.config_dir.display())),
            Line::from(push_status),
            Line::from(""),
            Line::from("  To rebuild your system:"),
            Line::from(Span::styled(
                format!(
                    "    sudo nixos-rebuild switch --flake {}",
                    self.config.config_dir.display()
                ),
                Style::default().fg(Color::Yellow),
            )),
            Line::from(""),
        ]))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green)),
        );
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "q: exit",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_failed(&self, frame: &mut Frame, area: Rect, error: &str) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Setup Failed",
            Style::default().bold().fg(Color::Red),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let mut lines: Vec<Line> = self
            .output_lines
            .iter()
            .map(|l| Line::from(format!("  {}", l)))
            .collect();
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            format!("  Error: {}", error),
            Style::default().fg(Color::Red).bold(),
        )));

        let output = Paragraph::new(lines)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Red)),
            )
            .wrap(Wrap { trim: false });
        frame.render_widget(output, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "r: retry push • s: skip • q: exit",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_first_boot_config() -> FirstBootConfig {
        FirstBootConfig {
            config_dir: PathBuf::from("/home/testuser/.keystone/repos/nixos-config"),
            hostname: "test-machine".to_string(),
            username: "testuser".to_string(),
            github_username: Some("octocat".to_string()),
        }
    }

    #[test]
    fn test_initial_phase_is_welcome() {
        let screen = FirstBootScreen::new(test_first_boot_config());
        assert_eq!(*screen.phase(), FirstBootPhase::Welcome);
    }

    #[test]
    fn test_remote_input_pre_filled() {
        let screen = FirstBootScreen::new(test_first_boot_config());
        assert_eq!(
            screen.remote_input.value(),
            "git@github.com:octocat/nixos-config.git"
        );
    }

    #[test]
    fn test_remote_input_empty_without_github() {
        let config = FirstBootConfig {
            config_dir: PathBuf::from("/home/testuser/.keystone/repos/nixos-config"),
            hostname: "test-machine".to_string(),
            username: "testuser".to_string(),
            github_username: None,
        };
        let screen = FirstBootScreen::new(config);
        assert_eq!(screen.remote_input.value(), "");
    }

    #[test]
    fn test_skip_from_ssh_key() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.phase = FirstBootPhase::ShowSshKey;
        screen.skip();
        assert_eq!(*screen.phase(), FirstBootPhase::RemoteInput);
    }

    #[test]
    fn test_skip_from_remote_input() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.phase = FirstBootPhase::RemoteInput;
        screen.skip();
        assert_eq!(*screen.phase(), FirstBootPhase::Done);
        assert!(screen.push_skipped);
    }

    #[test]
    fn test_poll_ssh_key() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::ShowSshKey;

        tx.send(FirstBootMessage::SshKey(
            "ssh-ed25519 AAAAC3test testuser@test-machine".to_string(),
        ))
        .unwrap();

        screen.poll();
        assert!(screen.ssh_public_key().is_some());
        assert!(screen.ssh_public_key().unwrap().contains("ssh-ed25519"));
    }

    #[test]
    fn test_poll_push_success() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::Pushing;

        tx.send(FirstBootMessage::PushResult(Ok(()))).unwrap();

        screen.poll();
        assert_eq!(*screen.phase(), FirstBootPhase::Done);
        assert!(!screen.push_skipped);
    }

    #[test]
    fn test_poll_push_failure() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::Pushing;

        tx.send(FirstBootMessage::PushResult(Err("auth failed".to_string())))
            .unwrap();

        screen.poll();
        assert!(matches!(screen.phase(), FirstBootPhase::Failed(_)));
    }
}
