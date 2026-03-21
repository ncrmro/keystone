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

use crate::disk::DiskEntry;

/// Configuration parsed from embedded install-config files.
#[derive(Debug, Clone)]
pub struct InstallerConfig {
    pub config_dir: PathBuf,
    pub hostname: String,
    pub username: Option<String>,
    pub github_username: Option<String>,
    pub storage_type: Option<String>,
    pub disk_device: Option<String>,
}

impl InstallerConfig {
    /// Detect installer mode by checking for embedded config at the well-known path.
    ///
    /// The ISO filesystem is read-only (squashfs), so we copy the config to a
    /// writable tmpdir before returning. This allows disk selection to inject
    /// the chosen device into configuration.nix at install time.
    pub fn detect() -> Option<Self> {
        let config_dir = Path::new("/etc/keystone/install-config");
        if !config_dir.exists() {
            return None;
        }

        let hostname = std::fs::read_to_string(config_dir.join("hostname"))
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "unknown".to_string());

        let username = std::fs::read_to_string(config_dir.join("username"))
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        let github_username = std::fs::read_to_string(config_dir.join("github_username"))
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());

        // Copy to writable location so we can inject disk selection later
        let writable_dir = PathBuf::from("/tmp/keystone-install-config");
        let effective_dir = if Self::copy_to_writable(config_dir, &writable_dir).is_ok() {
            writable_dir
        } else {
            config_dir.to_path_buf()
        };

        // Parse storage type and disk device from configuration.nix
        let (storage_type, disk_device) =
            Self::parse_configuration_nix(&effective_dir).unwrap_or((None, None));

        // Treat the placeholder as "no disk configured"
        let disk_device = disk_device.filter(|d| d != "__KEYSTONE_DISK__");

        Some(Self {
            config_dir: effective_dir,
            hostname,
            username,
            github_username,
            storage_type,
            disk_device,
        })
    }

    /// Copy config files to a writable tmpdir for disk injection.
    fn copy_to_writable(src: &Path, dst: &Path) -> std::io::Result<()> {
        if dst.exists() {
            std::fs::remove_dir_all(dst)?;
        }
        std::fs::create_dir_all(dst)?;
        for entry in std::fs::read_dir(src)? {
            let entry = entry?;
            let dest_file = dst.join(entry.file_name());
            std::fs::copy(entry.path(), dest_file)?;
        }
        Ok(())
    }

    /// Extract storage type and disk device from configuration.nix via rnix AST.
    fn parse_configuration_nix(config_dir: &Path) -> Option<(Option<String>, Option<String>)> {
        let content = std::fs::read_to_string(config_dir.join("configuration.nix")).ok()?;
        let root = rnix::Root::parse(&content);
        let syntax = root.syntax();

        let mut storage_type = None;
        let mut disk_device = None;

        // Walk the AST looking for `storage.type = "..."` and `storage.devices = [ "..." ]`
        for node in syntax.descendants() {
            if node.kind() != rnix::SyntaxKind::NODE_ATTRPATH_VALUE {
                continue;
            }

            let path_text = Self::attr_path_text(&node);

            // Match `type` inside a `storage` context (storage.type = "zfs")
            if path_text.ends_with(".type") || path_text == "type" {
                if let Some(val) = Self::extract_string_literal(&node) {
                    if val == "zfs" || val == "ext4" {
                        storage_type = Some(val);
                    }
                }
            }

            // Match `devices` inside storage — extract first element of the list
            if path_text.ends_with(".devices") || path_text == "devices" {
                for descendant in node.descendants() {
                    if descendant.kind() == rnix::SyntaxKind::NODE_LIST {
                        // Get the first string in the list
                        for child in descendant.children() {
                            if child.kind() == rnix::SyntaxKind::NODE_STRING {
                                let text = child.text().to_string();
                                let trimmed = text.trim_matches('"');
                                if !trimmed.is_empty() {
                                    disk_device = Some(trimmed.to_string());
                                    break;
                                }
                            }
                        }
                        break;
                    }
                }
            }
        }

        Some((storage_type, disk_device))
    }

    /// Get the dot-joined attribute path text from a NODE_ATTRPATH_VALUE.
    fn attr_path_text(node: &rnix::SyntaxNode) -> String {
        node.children()
            .find(|n| n.kind() == rnix::SyntaxKind::NODE_ATTRPATH)
            .map(|ap| {
                ap.children()
                    .filter(|n| n.kind() == rnix::SyntaxKind::NODE_IDENT)
                    .map(|n| n.text().to_string())
                    .collect::<Vec<_>>()
                    .join(".")
            })
            .unwrap_or_default()
    }

    /// Extract a string literal value from a NODE_ATTRPATH_VALUE node.
    fn extract_string_literal(node: &rnix::SyntaxNode) -> Option<String> {
        for descendant in node.descendants() {
            if descendant.kind() == rnix::SyntaxKind::NODE_STRING {
                let text = descendant.text().to_string();
                let trimmed = text.trim_matches('"');
                if !trimmed.is_empty() {
                    return Some(trimmed.to_string());
                }
            }
        }
        None
    }

    /// Replace the disk placeholder in the writable configuration.nix.
    fn inject_disk_device(config_dir: &Path, device: &str) -> std::io::Result<()> {
        let config_path = config_dir.join("configuration.nix");
        let content = std::fs::read_to_string(&config_path)?;
        let updated = content.replace("__KEYSTONE_DISK__", device);
        std::fs::write(&config_path, updated)?;
        Ok(())
    }
}

/// The phases of the install flow.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallPhase {
    /// Show config summary, waiting for user to proceed.
    Summary,
    /// Select a disk device (shown when no disk was pre-configured).
    DiskSelection,
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
    DisksDiscovered(Vec<DiskEntry>),
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
    /// Discovered disks for DiskSelection phase.
    available_disks: Vec<DiskEntry>,
    selected_disk_index: usize,
    /// Whether disk discovery is still running.
    discovering_disks: bool,
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
            available_disks: Vec::new(),
            selected_disk_index: 0,
            discovering_disks: false,
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
            available_disks: Vec::new(),
            selected_disk_index: 0,
            discovering_disks: false,
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

    pub fn available_disks(&self) -> &[DiskEntry] {
        &self.available_disks
    }

    pub fn selected_disk_index(&self) -> usize {
        self.selected_disk_index
    }

    /// Move from Summary → DiskSelection (if no disk configured) or Confirm.
    pub fn proceed_to_confirm(&mut self) {
        if self.phase != InstallPhase::Summary {
            return;
        }

        if self.config.disk_device.is_none() {
            // No disk pre-configured — enter disk selection
            self.phase = InstallPhase::DiskSelection;
            self.discovering_disks = true;
            self.spawn_disk_discovery();
        } else {
            self.phase = InstallPhase::Confirm;
        }
    }

    /// Spawn async disk discovery.
    fn spawn_disk_discovery(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);

        tokio::spawn(async move {
            match crate::disk::discover_disks().await {
                Ok(disks) => {
                    let _ = tx.send(InstallMessage::DisksDiscovered(disks));
                }
                Err(e) => {
                    let _ = tx.send(InstallMessage::Output(format!(
                        "Disk discovery failed: {}",
                        e
                    )));
                    let _ = tx.send(InstallMessage::DisksDiscovered(Vec::new()));
                }
            }
        });
    }

    /// Move disk selection cursor up.
    pub fn disk_up(&mut self) {
        if !self.available_disks.is_empty() {
            self.selected_disk_index = if self.selected_disk_index == 0 {
                self.available_disks.len() - 1
            } else {
                self.selected_disk_index - 1
            };
        }
    }

    /// Move disk selection cursor down.
    pub fn disk_down(&mut self) {
        if !self.available_disks.is_empty() {
            self.selected_disk_index = (self.selected_disk_index + 1) % self.available_disks.len();
        }
    }

    /// Select the highlighted disk and proceed to Confirm.
    pub fn select_disk(&mut self) {
        if self.phase != InstallPhase::DiskSelection || self.available_disks.is_empty() {
            return;
        }

        let selected = &self.available_disks[self.selected_disk_index];
        let device_path = selected.by_id_path.clone();

        // Inject the selected disk into the writable configuration.nix
        if let Err(e) = InstallerConfig::inject_disk_device(&self.config.config_dir, &device_path) {
            self.phase = InstallPhase::Failed(format!("Failed to set disk device: {}", e));
            return;
        }

        self.config.disk_device = Some(device_path);
        self.rx = None; // Clean up discovery channel
        self.phase = InstallPhase::Confirm;
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
        let username = self.config.username.clone();

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
                    "--flake",
                    &format!("{}#{}", config_dir.display(), hostname),
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

            let flake_ref = format!("{}#{}", config_dir.display(), hostname,);

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
                    // Copy config to the installed system for first-boot flow
                    if let Some(ref user) = username {
                        let _ = tx.send(InstallMessage::Output(
                            "Copying config to installed system...".to_string(),
                        ));
                        if let Err(e) = copy_config_to_target(&config_dir, user, &tx).await {
                            let _ = tx.send(InstallMessage::Output(format!(
                                "Warning: failed to copy config: {}",
                                e
                            )));
                        }
                    }

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

    /// Go back from Confirm → DiskSelection/Summary, or DiskSelection → Summary.
    pub fn go_back(&mut self) {
        match self.phase {
            InstallPhase::Confirm => {
                // If disk was selected interactively, go back to disk selection
                if !self.available_disks.is_empty() {
                    self.phase = InstallPhase::DiskSelection;
                } else {
                    self.phase = InstallPhase::Summary;
                }
            }
            InstallPhase::DiskSelection => {
                self.phase = InstallPhase::Summary;
            }
            _ => {}
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
                InstallMessage::DisksDiscovered(disks) => {
                    self.available_disks = disks;
                    self.selected_disk_index = 0;
                    self.discovering_disks = false;
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
            InstallPhase::DiskSelection => self.render_disk_selection(frame, area),
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
                Constraint::Min(8),    // Config summary
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

    fn render_disk_selection(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),    // Disk list
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Select Installation Disk",
            Style::default().bold().fg(Color::Yellow),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        if self.discovering_disks {
            let loading = Paragraph::new(Text::styled(
                "\n  Discovering disks...",
                Style::default().fg(Color::DarkGray),
            ))
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Yellow)),
            );
            frame.render_widget(loading, chunks[1]);
        } else if self.available_disks.is_empty() {
            let no_disks = Paragraph::new(Text::styled(
                "\n  No disks found. Ensure drives are connected and detected by the kernel.",
                Style::default().fg(Color::Red),
            ))
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Red)),
            );
            frame.render_widget(no_disks, chunks[1]);
        } else {
            let items: Vec<ListItem> = self
                .available_disks
                .iter()
                .enumerate()
                .map(|(i, disk)| {
                    let indicator = if i == self.selected_disk_index {
                        "▸ "
                    } else {
                        "  "
                    };
                    let style = if i == self.selected_disk_index {
                        Style::default()
                            .fg(Color::Yellow)
                            .add_modifier(Modifier::BOLD)
                    } else {
                        Style::default()
                    };
                    ListItem::new(Line::from(vec![
                        Span::styled(indicator, style),
                        Span::styled(&disk.model, style),
                        Span::styled(
                            format!("  {}  [{}]", disk.size, disk.transport),
                            Style::default().fg(Color::DarkGray),
                        ),
                    ]))
                })
                .collect();

            let disk_list = List::new(items).block(
                Block::default()
                    .title(" Available Disks ")
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Yellow)),
            );
            frame.render_widget(disk_list, chunks[1]);
        }

        let help = Paragraph::new(Text::styled(
            "↑/↓: navigate • Enter: select disk • Esc: back",
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
                Constraint::Min(5),    // Warning
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
                Constraint::Min(5),    // Output
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
                Constraint::Min(5),    // Message
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
                Constraint::Min(5),    // Output + error
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

/// Copy the generated config to the installed system for the first-boot flow.
///
/// Creates the installed system flake directory on the target and copies
/// flake.nix, configuration.nix, hardware.nix with a `.first-boot-pending`
/// marker so the TUI knows to run the first-boot wizard on next login.
async fn copy_config_to_target(
    config_dir: &Path,
    username: &str,
    tx: &mpsc::UnboundedSender<InstallMessage>,
) -> Result<(), String> {
    let target_home = PathBuf::from(format!("/mnt/home/{}", username));
    let repo_dir = target_home
        .join(".keystone")
        .join("repos")
        .join("nixos-config");

    tokio::fs::create_dir_all(&repo_dir)
        .await
        .map_err(|e| format!("Failed to create config dir: {}", e))?;

    // Copy config files
    for filename in &["flake.nix", "configuration.nix", "hardware.nix"] {
        let src = config_dir.join(filename);
        let dst = repo_dir.join(filename);
        if src.exists() {
            tokio::fs::copy(&src, &dst)
                .await
                .map_err(|e| format!("Failed to copy {}: {}", filename, e))?;
        }
    }

    // Write first-boot marker
    tokio::fs::write(repo_dir.join(".first-boot-pending"), "")
        .await
        .map_err(|e| format!("Failed to write first-boot marker: {}", e))?;

    let keystone_etc_dir = PathBuf::from("/mnt/etc/keystone");
    tokio::fs::create_dir_all(&keystone_etc_dir)
        .await
        .map_err(|e| format!("Failed to create /etc/keystone: {}", e))?;
    tokio::fs::write(
        keystone_etc_dir.join("system-flake"),
        format!("{}\n", repo_dir.display()),
    )
    .await
    .map_err(|e| format!("Failed to write system flake path: {}", e))?;

    // Fix ownership — look up uid/gid from the installed system's passwd
    let passwd_path = PathBuf::from("/mnt/etc/passwd");
    if passwd_path.exists() {
        let passwd = tokio::fs::read_to_string(&passwd_path)
            .await
            .unwrap_or_default();
        if let Some(line) = passwd
            .lines()
            .find(|l| l.starts_with(&format!("{}:", username)))
        {
            let parts: Vec<&str> = line.split(':').collect();
            if parts.len() >= 4 {
                let uid = parts[2];
                let gid = parts[3];
                let keystone_dir = target_home.join(".keystone");
                let _ = Command::new("chown")
                    .args([
                        "-R",
                        &format!("{}:{}", uid, gid),
                        &keystone_dir.display().to_string(),
                    ])
                    .output()
                    .await;
            }
        }
    }

    let _ = tx.send(InstallMessage::Output(format!(
        "Config copied to {}",
        repo_dir.display()
    )));
    Ok(())
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
            username: Some("testuser".to_string()),
            github_username: None,
            storage_type: Some("ext4".to_string()),
            disk_device: Some("/dev/disk/by-id/nvme-TEST".to_string()),
        }
    }

    fn test_config_no_disk() -> InstallerConfig {
        InstallerConfig {
            config_dir: PathBuf::from("/tmp/keystone-test-config"),
            hostname: "test-laptop".to_string(),
            username: Some("testuser".to_string()),
            github_username: None,
            storage_type: Some("ext4".to_string()),
            disk_device: None,
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

    #[test]
    fn test_proceed_with_disk_goes_to_confirm() {
        let mut screen = InstallScreen::new(test_config());
        screen.proceed_to_confirm();
        // Disk is pre-configured, should skip DiskSelection
        assert_eq!(*screen.phase(), InstallPhase::Confirm);
    }

    #[tokio::test]
    async fn test_proceed_without_disk_goes_to_selection() {
        let mut screen = InstallScreen::new(test_config_no_disk());
        screen.proceed_to_confirm();
        assert_eq!(*screen.phase(), InstallPhase::DiskSelection);
    }

    #[test]
    fn test_disk_navigation() {
        let mut screen = InstallScreen::new(test_config_no_disk());
        screen.available_disks = vec![
            DiskEntry {
                by_id_path: "/dev/disk/by-id/nvme-disk1".to_string(),
                model: "Samsung 980 PRO".to_string(),
                size: "1T".to_string(),
                transport: "nvme".to_string(),
            },
            DiskEntry {
                by_id_path: "/dev/disk/by-id/ata-disk2".to_string(),
                model: "WD Blue".to_string(),
                size: "2T".to_string(),
                transport: "sata".to_string(),
            },
        ];
        assert_eq!(screen.selected_disk_index(), 0);

        screen.disk_down();
        assert_eq!(screen.selected_disk_index(), 1);

        screen.disk_down();
        assert_eq!(screen.selected_disk_index(), 0); // wrap

        screen.disk_up();
        assert_eq!(screen.selected_disk_index(), 1); // wrap back
    }

    #[test]
    fn test_go_back_from_disk_selection() {
        let mut screen = InstallScreen::new(test_config_no_disk());
        screen.phase = InstallPhase::DiskSelection;
        screen.go_back();
        assert_eq!(*screen.phase(), InstallPhase::Summary);
    }

    #[test]
    fn test_poll_discovers_disks() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = InstallScreen::new_with_channel(test_config_no_disk(), rx);
        screen.phase = InstallPhase::DiskSelection;
        screen.discovering_disks = true;

        tx.send(InstallMessage::DisksDiscovered(vec![DiskEntry {
            by_id_path: "/dev/disk/by-id/nvme-test".to_string(),
            model: "Test Disk".to_string(),
            size: "500G".to_string(),
            transport: "nvme".to_string(),
        }]))
        .unwrap();

        screen.poll();
        assert!(!screen.discovering_disks);
        assert_eq!(screen.available_disks().len(), 1);
    }
}
