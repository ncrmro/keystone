//! ISO screen — build installer ISO and write to USB or save to ~/Downloads.
//!
//! Phases:
//! 1. Building — runs `nix build .#iso` in the active repo
//! 2. SelectTarget — choose USB device or ~/Downloads
//! 3. Writing — `dd` to USB or `cp` to ~/Downloads
//! 4. Done / Failed

use std::path::PathBuf;
use std::process::Stdio;

use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame,
};

/// A removable block device or the ~/Downloads save option.
#[derive(Debug, Clone)]
pub struct IsoTarget {
    pub label: String,
    pub path: String,
    pub is_usb: bool,
    pub size: String,
}

/// Messages from async operations back to the UI.
pub enum IsoMessage {
    BuildOutput(String),
    BuildFinished(bool),
    TargetsDiscovered(Vec<IsoTarget>),
    WriteOutput(String),
    WriteFinished(bool),
}

#[derive(Debug, Clone, PartialEq)]
pub enum IsoPhase {
    Building,
    SelectTarget,
    Writing,
    Done,
    Failed(String),
}

pub struct IsoScreen {
    phase: IsoPhase,
    repo_path: PathBuf,
    /// Lines of build/write output.
    output_lines: Vec<String>,
    scroll_offset: u16,
    auto_scroll: bool,
    /// Path to the built .iso file (set after build succeeds).
    iso_path: Option<PathBuf>,
    /// Available write targets.
    targets: Vec<IsoTarget>,
    selected_target: usize,
    /// Async message channel.
    rx: Option<mpsc::UnboundedReceiver<IsoMessage>>,
}

impl IsoScreen {
    pub fn new(repo_path: PathBuf) -> Self {
        let (tx, rx) = mpsc::unbounded_channel();

        let build_repo = repo_path.clone();
        tokio::spawn(async move {
            Self::run_build(tx, build_repo).await;
        });

        Self {
            phase: IsoPhase::Building,
            repo_path,
            output_lines: Vec::new(),
            scroll_offset: 0,
            auto_scroll: true,
            iso_path: None,
            targets: Vec::new(),
            selected_target: 0,
            rx: Some(rx),
        }
    }

    /// For testing — inject a channel instead of spawning a build.
    #[cfg(test)]
    pub fn new_with_channel(
        repo_path: PathBuf,
        rx: mpsc::UnboundedReceiver<IsoMessage>,
    ) -> Self {
        Self {
            phase: IsoPhase::Building,
            repo_path,
            output_lines: Vec::new(),
            scroll_offset: 0,
            auto_scroll: true,
            iso_path: None,
            targets: Vec::new(),
            selected_target: 0,
            rx: Some(rx),
        }
    }

    pub fn phase(&self) -> &IsoPhase {
        &self.phase
    }

    pub fn targets(&self) -> &[IsoTarget] {
        &self.targets
    }

    pub fn selected_target(&self) -> usize {
        self.selected_target
    }

    pub fn iso_path(&self) -> Option<&PathBuf> {
        self.iso_path.as_ref()
    }

    /// Poll for async messages (non-blocking).
    pub fn poll(&mut self) {
        let messages: Vec<IsoMessage> = {
            if let Some(ref mut rx) = self.rx {
                let mut msgs = Vec::new();
                while let Ok(msg) = rx.try_recv() {
                    msgs.push(msg);
                }
                msgs
            } else {
                Vec::new()
            }
        };

        for msg in messages {
            match msg {
                IsoMessage::BuildOutput(line) => {
                    self.output_lines.push(line);
                }
                IsoMessage::BuildFinished(success) => {
                    if success {
                        // Find the .iso file in the result
                        self.iso_path = Self::find_iso_file(&self.repo_path);
                        if self.iso_path.is_some() {
                            self.phase = IsoPhase::SelectTarget;
                            self.output_lines.clear();
                            // Discover targets
                            self.spawn_target_discovery();
                        } else {
                            self.phase = IsoPhase::Failed(
                                "Build succeeded but no .iso file found in result".to_string(),
                            );
                        }
                    } else {
                        self.phase = IsoPhase::Failed("ISO build failed".to_string());
                    }
                }
                IsoMessage::TargetsDiscovered(targets) => {
                    self.targets = targets;
                }
                IsoMessage::WriteOutput(line) => {
                    self.output_lines.push(line);
                }
                IsoMessage::WriteFinished(success) => {
                    if success {
                        self.phase = IsoPhase::Done;
                    } else {
                        self.phase = IsoPhase::Failed("Write failed".to_string());
                    }
                }
            }
        }
    }

    pub fn target_up(&mut self) {
        if !self.targets.is_empty() && self.selected_target > 0 {
            self.selected_target -= 1;
        }
    }

    pub fn target_down(&mut self) {
        if !self.targets.is_empty() && self.selected_target < self.targets.len() - 1 {
            self.selected_target += 1;
        }
    }

    pub fn select_target(&mut self) {
        if self.targets.is_empty() || self.phase != IsoPhase::SelectTarget {
            return;
        }

        let target = self.targets[self.selected_target].clone();
        let iso_path = match &self.iso_path {
            Some(p) => p.clone(),
            None => return,
        };

        self.phase = IsoPhase::Writing;
        self.output_lines.clear();
        self.auto_scroll = true;

        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);

        tokio::spawn(async move {
            Self::run_write(tx, iso_path, target).await;
        });
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

    // -- async operations --

    async fn run_build(tx: mpsc::UnboundedSender<IsoMessage>, repo_path: PathBuf) {
        let _ = tx.send(IsoMessage::BuildOutput(
            "$ nix build .#iso".to_string(),
        ));
        let _ = tx.send(IsoMessage::BuildOutput(String::new()));

        let child_result = Command::new("nix")
            .args(["build", ".#iso"])
            .current_dir(&repo_path)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn();

        let mut child = match child_result {
            Ok(c) => c,
            Err(e) => {
                let _ = tx.send(IsoMessage::BuildOutput(format!(
                    "Failed to start nix build: {e}"
                )));
                let _ = tx.send(IsoMessage::BuildFinished(false));
                return;
            }
        };

        // Stream stderr (nix build output goes to stderr)
        let stderr = child.stderr.take();
        let stdout = child.stdout.take();

        let tx_stderr = tx.clone();
        let stderr_task = tokio::spawn(async move {
            if let Some(stderr) = stderr {
                let reader = BufReader::new(stderr);
                let mut lines = reader.lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    if tx_stderr.send(IsoMessage::BuildOutput(line)).is_err() {
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
                    if tx_stdout.send(IsoMessage::BuildOutput(line)).is_err() {
                        break;
                    }
                }
            }
        });

        let status = child.wait().await;
        let _ = stderr_task.await;
        let _ = stdout_task.await;

        let success = status.is_ok_and(|s| s.success());
        let _ = tx.send(IsoMessage::BuildFinished(success));
    }

    fn find_iso_file(repo_path: &PathBuf) -> Option<PathBuf> {
        // nix build .#iso creates a `result` symlink
        let result = repo_path.join("result");
        if !result.exists() {
            return None;
        }

        // Look for .iso files inside result/iso/
        let iso_dir = result.join("iso");
        if iso_dir.is_dir() {
            if let Ok(entries) = std::fs::read_dir(&iso_dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.extension().is_some_and(|e| e == "iso") {
                        return Some(path);
                    }
                }
            }
        }

        // Maybe the result itself is the ISO
        if result.extension().is_some_and(|e| e == "iso") {
            return Some(result);
        }

        None
    }

    fn spawn_target_discovery(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);

        tokio::spawn(async move {
            let mut targets = Vec::new();

            // Always offer ~/Downloads
            let downloads = home::home_dir().unwrap_or_default().join("Downloads");
            targets.push(IsoTarget {
                label: format!("Save to {}", downloads.display()),
                path: downloads.to_string_lossy().to_string(),
                is_usb: false,
                size: String::new(),
            });

            // Discover removable USB devices via lsblk
            if let Ok(output) = tokio::process::Command::new("lsblk")
                .args(["--json", "-d", "-o", "NAME,SIZE,MODEL,TRAN,TYPE,RM"])
                .output()
                .await
            {
                if let Ok(text) = String::from_utf8(output.stdout) {
                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                        if let Some(devices) = json["blockdevices"].as_array() {
                            for dev in devices {
                                let rm = dev["rm"].as_bool().unwrap_or(false);
                                let dev_type = dev["type"].as_str().unwrap_or("");
                                let tran = dev["tran"].as_str().unwrap_or("");
                                let name = dev["name"].as_str().unwrap_or("");

                                // Only removable disks (USB sticks, etc.)
                                if !rm || dev_type != "disk" || name.is_empty() {
                                    continue;
                                }

                                let model = dev["model"]
                                    .as_str()
                                    .unwrap_or("Unknown")
                                    .trim()
                                    .to_string();
                                let size =
                                    dev["size"].as_str().unwrap_or("?").to_string();

                                targets.push(IsoTarget {
                                    label: format!(
                                        "/dev/{name} — {model} ({size}, {tran})"
                                    ),
                                    path: format!("/dev/{name}"),
                                    is_usb: true,
                                    size,
                                });
                            }
                        }
                    }
                }
            }

            let _ = tx.send(IsoMessage::TargetsDiscovered(targets));
        });
    }

    async fn run_write(
        tx: mpsc::UnboundedSender<IsoMessage>,
        iso_path: PathBuf,
        target: IsoTarget,
    ) {
        let iso_display = iso_path.display().to_string();

        if target.is_usb {
            // Write to USB with dd
            let _ = tx.send(IsoMessage::WriteOutput(format!(
                "Writing {} to {}...",
                iso_display, target.path
            )));
            let _ = tx.send(IsoMessage::WriteOutput(
                "This may take several minutes.".to_string(),
            ));
            let _ = tx.send(IsoMessage::WriteOutput(String::new()));

            let child_result = Command::new("sudo")
                .args([
                    "dd",
                    &format!("if={}", iso_path.display()),
                    &format!("of={}", target.path),
                    "bs=4M",
                    "status=progress",
                    "conv=fsync",
                ])
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .kill_on_drop(true)
                .spawn();

            let mut child = match child_result {
                Ok(c) => c,
                Err(e) => {
                    let _ = tx.send(IsoMessage::WriteOutput(format!(
                        "Failed to start dd: {e}"
                    )));
                    let _ = tx.send(IsoMessage::WriteFinished(false));
                    return;
                }
            };

            // dd writes progress to stderr
            let stderr = child.stderr.take();
            let tx_stderr = tx.clone();
            let stderr_task = tokio::spawn(async move {
                if let Some(stderr) = stderr {
                    let reader = BufReader::new(stderr);
                    let mut lines = reader.lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        if tx_stderr.send(IsoMessage::WriteOutput(line)).is_err() {
                            break;
                        }
                    }
                }
            });

            let status = child.wait().await;
            let _ = stderr_task.await;

            let success = status.is_ok_and(|s| s.success());
            if success {
                let _ = tx.send(IsoMessage::WriteOutput(String::new()));
                let _ = tx.send(IsoMessage::WriteOutput(format!(
                    "ISO written to {}",
                    target.path
                )));
            }
            let _ = tx.send(IsoMessage::WriteFinished(success));
        } else {
            // Copy to ~/Downloads
            let dest_dir = PathBuf::from(&target.path);
            if let Err(e) = std::fs::create_dir_all(&dest_dir) {
                let _ = tx.send(IsoMessage::WriteOutput(format!(
                    "Failed to create {}: {e}",
                    dest_dir.display()
                )));
                let _ = tx.send(IsoMessage::WriteFinished(false));
                return;
            }

            let filename = iso_path
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();
            let dest = dest_dir.join(&filename);

            let _ = tx.send(IsoMessage::WriteOutput(format!(
                "Copying {} to {}...",
                iso_display,
                dest.display()
            )));

            match std::fs::copy(&iso_path, &dest) {
                Ok(bytes) => {
                    let mb = bytes / (1024 * 1024);
                    let _ = tx.send(IsoMessage::WriteOutput(format!(
                        "Copied {mb} MiB to {}",
                        dest.display()
                    )));
                    let _ = tx.send(IsoMessage::WriteFinished(true));
                }
                Err(e) => {
                    let _ = tx.send(IsoMessage::WriteOutput(format!(
                        "Copy failed: {e}"
                    )));
                    let _ = tx.send(IsoMessage::WriteFinished(false));
                }
            }
        }
    }

    // -- rendering --

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        match &self.phase {
            IsoPhase::Building => self.render_building(frame, area),
            IsoPhase::SelectTarget => self.render_select_target(frame, area),
            IsoPhase::Writing => self.render_output(frame, area, "Writing ISO", Color::Yellow),
            IsoPhase::Done => self.render_output(frame, area, "ISO Complete", Color::Green),
            IsoPhase::Failed(msg) => {
                self.render_output(frame, area, &format!("Failed: {msg}"), Color::Red)
            }
        }
    }

    fn render_building(&self, frame: &mut Frame, area: Rect) {
        self.render_output(frame, area, "Building ISO...", Color::Yellow);
    }

    fn render_output(&self, frame: &mut Frame, area: Rect, title: &str, title_color: Color) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        // Title
        let title_widget = Paragraph::new(Text::styled(
            title,
            Style::default().bold().fg(title_color),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title_widget, chunks[0]);

        // Output area
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

        // Help text
        let help_text = match &self.phase {
            IsoPhase::Done | IsoPhase::Failed(_) => "Esc: back • q: quit",
            _ => "↑/↓: scroll • Esc: cancel",
        };
        let help = Paragraph::new(Text::styled(
            help_text,
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_select_target(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Length(4),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled(
            "ISO Built — Select Destination",
            Style::default().bold().fg(Color::Green),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        // ISO info
        let iso_info = if let Some(ref path) = self.iso_path {
            let size = std::fs::metadata(path)
                .map(|m| format!("{} MiB", m.len() / (1024 * 1024)))
                .unwrap_or_else(|_| "?".to_string());
            format!(
                "  ISO: {}\n  Size: {}",
                path.file_name().unwrap_or_default().to_string_lossy(),
                size
            )
        } else {
            "  ISO: unknown".to_string()
        };
        let info = Paragraph::new(iso_info)
            .style(Style::default().fg(Color::Cyan))
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(info, chunks[1]);

        // Target list
        let items: Vec<ListItem> = self
            .targets
            .iter()
            .enumerate()
            .map(|(i, target)| {
                let style = if i == self.selected_target {
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default()
                };

                let prefix = if i == self.selected_target {
                    "▸ "
                } else {
                    "  "
                };

                let warning = if target.is_usb {
                    Span::styled(" (ALL DATA WILL BE ERASED)", Style::default().fg(Color::Red))
                } else {
                    Span::raw("")
                };

                ListItem::new(Line::from(vec![
                    Span::styled(format!("{prefix}{}", target.label), style),
                    warning,
                ]))
            })
            .collect();

        let list = List::new(items).block(
            Block::default()
                .title(" Destination ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        );
        frame.render_widget(list, chunks[2]);

        // Help
        let help_text = if self.targets.is_empty() {
            "Discovering devices..."
        } else {
            "↑/↓: navigate • Enter: write • Esc: cancel"
        };
        let help = Paragraph::new(Text::styled(
            help_text,
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[3]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_repo_path() -> PathBuf {
        PathBuf::from("/tmp/test-repo")
    }

    #[test]
    fn test_initial_phase_is_building() {
        let (_, rx) = mpsc::unbounded_channel();
        let screen = IsoScreen::new_with_channel(test_repo_path(), rx);
        assert_eq!(*screen.phase(), IsoPhase::Building);
    }

    #[test]
    fn test_poll_collects_build_output() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = IsoScreen::new_with_channel(test_repo_path(), rx);

        tx.send(IsoMessage::BuildOutput("line 1".to_string())).unwrap();
        tx.send(IsoMessage::BuildOutput("line 2".to_string())).unwrap();

        screen.poll();
        assert_eq!(screen.output_lines.len(), 2);
        assert_eq!(screen.output_lines[0], "line 1");
    }

    #[test]
    fn test_build_failure_goes_to_failed() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = IsoScreen::new_with_channel(test_repo_path(), rx);

        tx.send(IsoMessage::BuildFinished(false)).unwrap();
        screen.poll();

        assert!(matches!(screen.phase(), IsoPhase::Failed(_)));
    }

    #[test]
    fn test_target_navigation() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = IsoScreen::new_with_channel(test_repo_path(), rx);
        screen.phase = IsoPhase::SelectTarget;

        tx.send(IsoMessage::TargetsDiscovered(vec![
            IsoTarget {
                label: "~/Downloads".to_string(),
                path: "/home/user/Downloads".to_string(),
                is_usb: false,
                size: String::new(),
            },
            IsoTarget {
                label: "/dev/sda".to_string(),
                path: "/dev/sda".to_string(),
                is_usb: true,
                size: "32G".to_string(),
            },
        ]))
        .unwrap();
        screen.poll();

        assert_eq!(screen.selected_target(), 0);
        screen.target_down();
        assert_eq!(screen.selected_target(), 1);
        screen.target_down(); // at end, no-op
        assert_eq!(screen.selected_target(), 1);
        screen.target_up();
        assert_eq!(screen.selected_target(), 0);
    }

    #[test]
    fn test_target_up_at_zero_is_noop() {
        let (_, rx) = mpsc::unbounded_channel();
        let mut screen = IsoScreen::new_with_channel(test_repo_path(), rx);
        screen.target_up();
        assert_eq!(screen.selected_target(), 0);
    }

    #[test]
    fn test_scroll_disables_auto_scroll() {
        let (_, rx) = mpsc::unbounded_channel();
        let mut screen = IsoScreen::new_with_channel(test_repo_path(), rx);
        assert!(screen.auto_scroll);
        screen.scroll_up();
        assert!(!screen.auto_scroll);
        screen.scroll_down();
        assert!(screen.auto_scroll);
    }
}
