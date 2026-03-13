//! Install screen — streamlined installer flow for pre-baked ISOs.
//!
//! When the TUI boots on an ISO with embedded config files at
//! `/etc/keystone/install-config/`, this screen drives the install:
//!
//! 1. **Summary** — Show the pre-baked config (hostname, storage, user)
//! 2. **Disk confirmation** — Verify the configured disk exists
//! 3. **Confirm** — Final warning before erasing the disk
//! 4. **Install** — Run disko + nixos-install, streaming output
//! 5. **Done** — Prompt to remove USB and reboot

use std::path::{Path, PathBuf};

use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame,
};

use std::process::Stdio;

/// Configuration parsed from embedded install-config files.
#[derive(Debug, Clone)]
pub struct InstallerConfig {
    pub config_dir: PathBuf,
    pub hostname: String,
    pub storage_type: Option<String>,
    pub disk_device: Option<String>,
}

impl InstallerConfig {
    /// Detect installer mode by checking for embedded config at the well-known path.
    pub fn detect() -> Option<Self> {
        let config_dir = Path::new("/etc/keystone/install-config");
        if !config_dir.exists() {
            return None;
        }

        let hostname = std::fs::read_to_string(config_dir.join("hostname"))
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "unknown".to_string());

        // Parse storage type and disk device from configuration.nix
        let (storage_type, disk_device) =
            Self::parse_configuration_nix(config_dir).unwrap_or((None, None));

        Some(Self {
            config_dir: config_dir.to_path_buf(),
            hostname,
            storage_type,
            disk_device,
        })
    }

    /// Extract storage type and disk device from configuration.nix via simple pattern matching.
    fn parse_configuration_nix(config_dir: &Path) -> Option<(Option<String>, Option<String>)> {
        let content = std::fs::read_to_string(config_dir.join("configuration.nix")).ok()?;

        let storage_type = content
            .lines()
            .find(|l| l.contains("type =") && !l.contains("machine_type"))
            .and_then(|l| {
                let start = l.find('"')? + 1;
                let end = l[start..].find('"')? + start;
                Some(l[start..end].to_string())
            });

        let disk_device = content
            .lines()
            .find(|l| l.contains("/dev/disk/by-id/"))
            .and_then(|l| {
                let start = l.find('"')? + 1;
                let end = l[start..].find('"')? + start;
                Some(l[start..end].to_string())
            });

        Some((storage_type, disk_device))
    }
}

/// The phases of the install flow.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallPhase {
    /// Show config summary, waiting for user to proceed.
    Summary,
    /// Confirm disk erasure.
    Confirm,
    /// Running disko + nixos-install.
    Installing,
    /// Install completed successfully.
    Done,
    /// Install failed.
    Failed(String),
}

/// Messages from the install subprocess.
pub enum InstallMessage {
    Output(String),
    PhaseComplete(String),
    Finished(InstallResult),
}

#[derive(Clone, Debug)]
pub enum InstallResult {
    Success,
    Failed(String),
    Cancelled,
}

pub struct InstallScreen {
    config: InstallerConfig,
    phase: InstallPhase,
    /// Output log lines from the install process.
    output_lines: Vec<String>,
    scroll_offset: u16,
    auto_scroll: bool,
    /// Channel for receiving install subprocess messages.
    rx: Option<mpsc::UnboundedReceiver<InstallMessage>>,
    cancel_token: CancellationToken,
}

impl InstallScreen {
    pub fn new(config: InstallerConfig) -> Self {
        Self {
            config,
            phase: InstallPhase::Summary,
            output_lines: Vec::new(),
            scroll_offset: 0,
            auto_scroll: true,
            rx: None,
            cancel_token: CancellationToken::new(),
        }
    }

    #[cfg(test)]
    pub fn new_with_channel(
        config: InstallerConfig,
        rx: mpsc::UnboundedReceiver<InstallMessage>,
    ) -> Self {
        Self {
            config,
            phase: InstallPhase::Summary,
            output_lines: Vec::new(),
            scroll_offset: 0,
            auto_scroll: true,
            rx: Some(rx),
            cancel_token: CancellationToken::new(),
        }
    }

    pub fn phase(&self) -> &InstallPhase {
        &self.phase
    }

    pub fn config(&self) -> &InstallerConfig {
        &self.config
    }

    pub fn output_lines(&self) -> &[String] {
        &self.output_lines
    }

    /// Move from Summary → Confirm.
    pub fn proceed_to_confirm(&mut self) {
        if self.phase == InstallPhase::Summary {
            self.phase = InstallPhase::Confirm;
        }
    }

    /// Move from Confirm → Installing, spawning the install subprocess.
    pub fn start_install(&mut self) {
        if self.phase != InstallPhase::Confirm {
            return;
        }

        self.phase = InstallPhase::Installing;
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let cancel_token = CancellationToken::new();
        self.cancel_token = cancel_token.clone();

        let config_dir = self.config.config_dir.clone();
        let hostname = self.config.hostname.clone();

        tokio::spawn(async move {
            // Phase 1: Run disko to partition and format the disk
            let _ = tx.send(InstallMessage::Output(
                "=== Phase 1/2: Partitioning with disko ===".to_string(),
            ));

            let disko_result = run_command(
                "disko",
                &[
                    "--mode",
                    "disko",
                    &format!("{}/configuration.nix", config_dir.display()),
                ],
                &config_dir,
                &tx,
                &cancel_token,
            )
            .await;

            if let Err(e) = disko_result {
                let _ = tx.send(InstallMessage::Finished(InstallResult::Failed(format!(
                    "disko failed: {}",
                    e
                ))));
                return;
            }

            if cancel_token.is_cancelled() {
                let _ = tx.send(InstallMessage::Finished(InstallResult::Cancelled));
                return;
            }

            let _ = tx.send(InstallMessage::PhaseComplete(
                "Disk partitioning complete.".to_string(),
            ));

            // Phase 2: Run nixos-install
            let _ = tx.send(InstallMessage::Output(String::new()));
            let _ = tx.send(InstallMessage::Output(
                "=== Phase 2/2: Installing NixOS ===".to_string(),
            ));

            let flake_ref = format!(
                "{}#{}",
                config_dir.display(),
                hostname,
            );

            let install_result = run_command(
                "nixos-install",
                &["--flake", &flake_ref, "--no-root-password"],
                &config_dir,
                &tx,
                &cancel_token,
            )
            .await;

            match install_result {
                Ok(()) => {
                    let _ = tx.send(InstallMessage::Finished(InstallResult::Success));
                }
                Err(e) => {
                    let _ = tx.send(InstallMessage::Finished(InstallResult::Failed(format!(
                        "nixos-install failed: {}",
                        e
                    ))));
                }
            }
        });
    }

    /// Go back from Confirm → Summary.
    pub fn go_back(&mut self) {
        if self.phase == InstallPhase::Confirm {
            self.phase = InstallPhase::Summary;
        }
    }

    /// Cancel a running install.
    pub fn cancel(&mut self) {
        if self.phase == InstallPhase::Installing {
            self.cancel_token.cancel();
        }
    }

    pub fn is_finished(&self) -> bool {
        matches!(self.phase, InstallPhase::Done | InstallPhase::Failed(_))
    }

    pub fn scroll_up(&mut self) {
        self.auto_scroll = false;
        self.scroll_offset = self.scroll_offset.saturating_add(1);
    }

    pub fn scroll_down(&mut self) {
        if self.scroll_offset > 0 {
            self.scroll_offset = self.scroll_offset.saturating_sub(1);
            if self.scroll_offset == 0 {
                self.auto_scroll = true;
            }
        }
    }

    /// Poll for subprocess messages.
    pub fn poll(&mut self) {
        let rx = match self.rx.as_mut() {
            Some(rx) => rx,
            None => return,
        };

        while let Ok(msg) = rx.try_recv() {
            match msg {
                InstallMessage::Output(line) => {
                    self.output_lines.push(line);
                }
                InstallMessage::PhaseComplete(msg) => {
                    self.output_lines.push(msg);
                }
                InstallMessage::Finished(result) => match result {
                    InstallResult::Success => {
                        self.output_lines
                            .push(String::from("\nInstallation complete!"));
                        self.phase = InstallPhase::Done;
                    }
                    InstallResult::Failed(err) => {
                        self.output_lines
                            .push(format!("\nInstallation failed: {}", err));
                        self.phase = InstallPhase::Failed(err);
                    }
                    InstallResult::Cancelled => {
                        self.output_lines
                            .push(String::from("\nInstallation cancelled."));
                        self.phase = InstallPhase::Failed("Cancelled by user".to_string());
                    }
                },
            }
        }
    }

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        match &self.phase {
            InstallPhase::Summary => self.render_summary(frame, area),
            InstallPhase::Confirm => self.render_confirm(frame, area),
            InstallPhase::Installing => self.render_installing(frame, area),
            InstallPhase::Done => self.render_done(frame, area),
            InstallPhase::Failed(err) => self.render_failed(frame, area, err),
        }
    }

    fn render_summary(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(8),   // Config summary
                Constraint::Length(3), // Help
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled(
            "Keystone Installer",
            Style::default().bold().fg(Color::Green),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // Config summary
        let disk = self
            .config
            .disk_device
            .as_deref()
            .unwrap_or("(not detected)");
        let storage = self
            .config
            .storage_type
            .as_deref()
            .unwrap_or("(not detected)");

        let items = vec![
            ListItem::new(Line::from(vec![
                Span::styled("  Hostname:  ", Style::default().fg(Color::DarkGray)),
                Span::styled(&self.config.hostname, Style::default().bold()),
            ])),
            ListItem::new(Line::from(vec![
                Span::styled("  Storage:   ", Style::default().fg(Color::DarkGray)),
                Span::styled(storage, Style::default().bold()),
            ])),
            ListItem::new(Line::from(vec![
                Span::styled("  Disk:      ", Style::default().fg(Color::DarkGray)),
                Span::styled(disk, Style::default().bold()),
            ])),
            ListItem::new(Line::from("")),
            ListItem::new(Line::from(vec![
                Span::styled("  Config:    ", Style::default().fg(Color::DarkGray)),
                Span::styled(
                    self.config.config_dir.display().to_string(),
                    Style::default().fg(Color::DarkGray),
                ),
            ])),
        ];

        let summary = List::new(items).block(
            Block::default()
                .title(" Configuration Summary ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green)),
        );
        frame.render_widget(summary, chunks[1]);

        // Help
        let help = Paragraph::new(Text::styled(
            "Enter: proceed to install • q: quit",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_confirm(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),   // Warning
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Confirm Installation",
            Style::default()
                .bold()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let disk = self
            .config
            .disk_device
            .as_deref()
            .unwrap_or("(unknown disk)");
        let warning_text = format!(
            "\n  WARNING: This will ERASE ALL DATA on:\n\n    {}\n\n  This action cannot be undone.",
            disk,
        );
        let warning = Paragraph::new(Text::styled(
            warning_text,
            Style::default().fg(Color::Red).bold(),
        ))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Red)),
        );
        frame.render_widget(warning, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: confirm and install • Esc: go back",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_installing(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),   // Output
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            format!("Installing: {} (in progress...)", self.config.hostname),
            Style::default().bold().yellow(),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // Output area with scrolling
        let output_height = chunks[1].height.saturating_sub(2) as usize;
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

        let help = Paragraph::new(Text::styled(
            "↑/↓: scroll • Esc: cancel",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_done(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),   // Message
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Installation Complete",
            Style::default().bold().fg(Color::Green),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let message = Paragraph::new(Text::styled(
            format!(
                "\n  NixOS has been installed as '{}'.\n\n  \
                 Please remove the USB drive and reboot.\n\n  \
                 After reboot, enroll Secure Boot keys with:\n    \
                 sudo sbctl enroll-keys --microsoft",
                self.config.hostname,
            ),
            Style::default().fg(Color::Green),
        ))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green)),
        );
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "r: reboot • q: quit to shell",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_failed(&self, frame: &mut Frame, area: Rect, error: &str) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),   // Output + error
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Installation Failed",
            Style::default().bold().fg(Color::Red),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // Show the last N lines of output plus the error
        let output_height = chunks[1].height.saturating_sub(2) as usize;
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
                    .title(format!(" Error: {} ", error))
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Red)),
            )
            .wrap(Wrap { trim: false })
            .scroll((scroll, 0));
        frame.render_widget(output, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "↑/↓: scroll • q: quit to shell",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}

/// Run a command, streaming output lines to the channel.
async fn run_command(
    program: &str,
    args: &[&str],
    cwd: &Path,
    tx: &mpsc::UnboundedSender<InstallMessage>,
    cancel_token: &CancellationToken,
) -> Result<(), String> {
    let cmd_display = format!("$ {} {}", program, args.join(" "));
    let _ = tx.send(InstallMessage::Output(cmd_display));

    let child_result = Command::new(program)
        .args(args)
        .current_dir(cwd)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn();

    let mut child = match child_result {
        Ok(c) => c,
        Err(e) => return Err(format!("Failed to start {}: {}", program, e)),
    };

    let stderr = child.stderr.take();
    let stdout = child.stdout.take();

    let tx_stderr = tx.clone();
    let stderr_task = tokio::spawn(async move {
        if let Some(stderr) = stderr {
            let reader = BufReader::new(stderr);
            let mut lines = reader.lines();
            while let Ok(Some(line)) = lines.next_line().await {
                if tx_stderr.send(InstallMessage::Output(line)).is_err() {
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
                if tx_stdout.send(InstallMessage::Output(line)).is_err() {
                    break;
                }
            }
        }
    });

    tokio::select! {
        status = child.wait() => {
            let _ = stderr_task.await;
            let _ = stdout_task.await;

            match status {
                Ok(s) if s.success() => Ok(()),
                Ok(s) => Err(format!("{} exited with code {}", program, s.code().unwrap_or(-1))),
                Err(e) => Err(format!("{} process error: {}", program, e)),
            }
        }
        _ = cancel_token.cancelled() => {
            drop(child);
            let _ = stderr_task.await;
            let _ = stdout_task.await;
            Err("Cancelled".to_string())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config() -> InstallerConfig {
        InstallerConfig {
            config_dir: PathBuf::from("/etc/keystone/install-config"),
            hostname: "test-laptop".to_string(),
            storage_type: Some("ext4".to_string()),
            disk_device: Some("/dev/disk/by-id/nvme-TEST".to_string()),
        }
    }

    #[test]
    fn test_initial_phase_is_summary() {
        let screen = InstallScreen::new(test_config());
        assert_eq!(*screen.phase(), InstallPhase::Summary);
    }

    #[test]
    fn test_proceed_to_confirm() {
        let mut screen = InstallScreen::new(test_config());
        screen.proceed_to_confirm();
        assert_eq!(*screen.phase(), InstallPhase::Confirm);
    }

    #[test]
    fn test_go_back_from_confirm() {
        let mut screen = InstallScreen::new(test_config());
        screen.proceed_to_confirm();
        screen.go_back();
        assert_eq!(*screen.phase(), InstallPhase::Summary);
    }

    #[test]
    fn test_go_back_from_summary_is_noop() {
        let mut screen = InstallScreen::new(test_config());
        screen.go_back();
        assert_eq!(*screen.phase(), InstallPhase::Summary);
    }

    #[test]
    fn test_poll_collects_output() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = InstallScreen::new_with_channel(test_config(), rx);
        screen.phase = InstallPhase::Installing;

        tx.send(InstallMessage::Output("partitioning...".to_string()))
            .unwrap();
        tx.send(InstallMessage::Output("formatting...".to_string()))
            .unwrap();

        screen.poll();
        assert_eq!(screen.output_lines().len(), 2);
    }

    #[test]
    fn test_poll_handles_success() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = InstallScreen::new_with_channel(test_config(), rx);
        screen.phase = InstallPhase::Installing;

        tx.send(InstallMessage::Finished(InstallResult::Success))
            .unwrap();

        screen.poll();
        assert_eq!(*screen.phase(), InstallPhase::Done);
        assert!(screen.is_finished());
    }

    #[test]
    fn test_poll_handles_failure() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = InstallScreen::new_with_channel(test_config(), rx);
        screen.phase = InstallPhase::Installing;

        tx.send(InstallMessage::Finished(InstallResult::Failed(
            "disk error".to_string(),
        )))
        .unwrap();

        screen.poll();
        assert!(matches!(screen.phase(), InstallPhase::Failed(_)));
        assert!(screen.is_finished());
    }

    #[test]
    fn test_scroll_behavior() {
        let mut screen = InstallScreen::new(test_config());
        assert!(screen.auto_scroll);

        screen.scroll_up();
        assert!(!screen.auto_scroll);

        screen.scroll_down();
        assert!(screen.auto_scroll);
    }
}
