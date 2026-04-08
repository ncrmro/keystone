//! First-boot screen — post-install hardware reconciliation wizard.
//!
//! After a fresh Keystone install, on first boot the TUI detects a
//! `.first-boot-pending` marker in the installed system flake directory and
//! walks the user through:
//!
//! 1. Detecting real hardware facts from the installed machine
//! 2. Building an in-memory reconciliation plan for `hardware.nix`
//! 3. Showing a summary and diff preview before any files are written
//! 4. Applying the reviewed patch, then continuing with the existing git flow

use std::path::PathBuf;

use crossterm::event::{Event, KeyCode, KeyEventKind};
use tokio::process::Command;
use tokio::sync::mpsc;

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, Paragraph, Wrap},
    Frame,
};

use crate::action::Action;
use crate::component::Component;
use crate::widgets::TextInput;

/// Configuration for the first-boot flow.
#[derive(Debug, Clone)]
pub struct FirstBootConfig {
    pub config_dir: PathBuf,
    pub hostname: String,
    pub username: String,
    pub github_username: Option<String>,
}

impl FirstBootConfig {
    fn installed_config_dir() -> Option<PathBuf> {
        std::env::var_os("KEYSTONE_SYSTEM_FLAKE")
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .or_else(|| {
                std::fs::read_to_string("/etc/keystone/system-flake")
                    .ok()
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .map(PathBuf::from)
            })
            .or_else(|| {
                let home = home::home_dir()?;
                Some(home.join(".keystone").join("repos").join("nixos-config"))
            })
    }

    /// Detect first-boot mode by looking for the marker file.
    pub fn detect() -> Option<Self> {
        let config_dir = Self::installed_config_dir()?;
        let marker = config_dir.join(".first-boot-pending");

        if !marker.exists() {
            return None;
        }

        let hostname = std::fs::read_to_string("/etc/hostname")
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "keystone".to_string());

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HardwarePatchPlan {
    pub current_hardware_nix: String,
    pub proposed_hardware_nix: String,
    pub detected_disk_ids: Vec<String>,
    pub detected_kernel_modules: Vec<String>,
    pub diff_preview: Vec<String>,
    pub has_changes: bool,
}

/// Phases of the first-boot wizard.
///
/// Onboarding flow (REQ-008):
/// Stage 5: Hardware → commit locally → Secure Boot → TPM → reboot
/// Stage 6: SSH keys → push pending commit → secrets
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FirstBootPhase {
    // Stage 5: First boot after install
    Welcome,
    DetectingHardware,
    ReviewPatch,
    GitSetup, // local commit only — no push yet (ISO has no SSH keys)
    // Security enrollment (Stage 5 continued)
    SecureBootEnroll, // TODO: wire to security::secure_boot
    TpmEnroll,        // TODO: wire to security::tpm
    RebootPrompt,     // reboot for SB+TPM to take effect
    // Stage 6: After security reboot
    SshKeySetup,  // TODO: detect/generate/import SSH keys
    ShowSshKey,   // display public key for user to add to GitHub
    RemoteInput,  // enter git remote URL
    Pushing,      // push the pending hardware commit
    SecretsSetup, // TODO: agenix secrets initialization
    Done,
    Failed(String),
}

/// Messages from first-boot async operations.
pub enum FirstBootMessage {
    Output(String),
    PatchPlanReady(HardwarePatchPlan),
    NoChangesRequired(String),
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
    hardware_plan: Option<HardwarePatchPlan>,
    done_message: String,
    marker_removed: bool,
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
            hardware_plan: None,
            done_message: "Setup complete.".to_string(),
            marker_removed: false,
        }
    }

    pub fn phase(&self) -> &FirstBootPhase {
        &self.phase
    }

    pub fn ssh_public_key(&self) -> Option<&str> {
        self.ssh_public_key.as_deref()
    }

    pub fn hardware_plan(&self) -> Option<&HardwarePatchPlan> {
        self.hardware_plan.as_ref()
    }

    /// Start the first-boot process (Welcome → DetectingHardware).
    pub fn start(&mut self) {
        if self.phase != FirstBootPhase::Welcome {
            return;
        }
        self.phase = FirstBootPhase::DetectingHardware;
        self.spawn_hardware_detection();
    }

    fn spawn_hardware_detection(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let config_dir = self.config.config_dir.clone();

        tokio::spawn(async move {
            let _ = tx.send(FirstBootMessage::Output(
                "Detecting hardware with nixos-generate-config...".to_string(),
            ));

            // Try hosts/<hostname>/hardware.nix first (mkSystemFlake layout),
            // fall back to flat hardware.nix for backward compat.
            let hostname = std::fs::read_to_string("/etc/hostname")
                .ok()
                .map(|s| s.trim().to_string())
                .unwrap_or_default();
            let hardware_path = if !hostname.is_empty() {
                let host_path = config_dir
                    .join("hosts")
                    .join(&hostname)
                    .join("hardware.nix");
                if host_path.exists() {
                    host_path
                } else {
                    config_dir.join("hardware.nix")
                }
            } else {
                config_dir.join("hardware.nix")
            };

            let current_hardware = match tokio::fs::read_to_string(&hardware_path).await {
                Ok(content) => content,
                Err(e) => {
                    let _ = tx.send(FirstBootMessage::Failed(format!(
                        "Failed to read current hardware.nix: {}",
                        e
                    )));
                    return;
                }
            };

            let output = Command::new("nixos-generate-config")
                .args(["--show-hardware-config"])
                .output()
                .await;

            match output {
                Ok(out) if out.status.success() => {
                    let proposed_hardware = String::from_utf8_lossy(&out.stdout).to_string();

                    match build_hardware_patch_plan(&current_hardware, &proposed_hardware) {
                        Ok(plan) if !plan.has_changes => {
                            let _ = tx.send(FirstBootMessage::NoChangesRequired(
                                "No hardware reconciliation changes are required.".to_string(),
                            ));
                        }
                        Ok(plan) => {
                            let _ = tx.send(FirstBootMessage::Output(
                                "Hardware facts collected. Review the proposed patch before applying it."
                                    .to_string(),
                            ));
                            let _ = tx.send(FirstBootMessage::PatchPlanReady(plan));
                        }
                        Err(err) => {
                            let _ = tx.send(FirstBootMessage::Failed(err));
                        }
                    }
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

    pub fn apply_patch(&mut self) {
        if self.phase != FirstBootPhase::ReviewPatch {
            return;
        }

        let Some(plan) = self.hardware_plan.as_ref() else {
            self.phase = FirstBootPhase::Failed(
                "Cannot apply patch because no hardware reconciliation plan exists.".to_string(),
            );
            return;
        };

        if !plan.has_changes {
            self.complete(
                true,
                "No hardware reconciliation changes were required. The marker was cleared.",
            );
            return;
        }

        // Write to hosts/<hostname>/hardware.nix if it exists, else flat path
        let hostname = std::fs::read_to_string("/etc/hostname")
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_default();
        let hardware_path = if !hostname.is_empty() {
            let host_path = self
                .config
                .config_dir
                .join("hosts")
                .join(&hostname)
                .join("hardware.nix");
            if host_path.exists() || self.config.config_dir.join("hosts").exists() {
                host_path
            } else {
                self.config.config_dir.join("hardware.nix")
            }
        } else {
            self.config.config_dir.join("hardware.nix")
        };
        if let Err(e) = std::fs::write(&hardware_path, &plan.proposed_hardware_nix) {
            self.phase =
                FirstBootPhase::Failed(format!("Failed to write reconciled hardware.nix: {}", e));
            return;
        }

        self.output_lines.push(format!(
            "Applied reconciled hardware.nix at {}",
            hardware_path.display()
        ));
        self.phase = FirstBootPhase::GitSetup;
        self.spawn_git_setup();
    }

    fn spawn_git_setup(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let config_dir = self.config.config_dir.clone();

        tokio::spawn(async move {
            let _ = tx.send(FirstBootMessage::Output(
                "Initializing git repository...".to_string(),
            ));

            let init = Command::new("git")
                .args(["init", "-b", "main"])
                .current_dir(&config_dir)
                .output()
                .await;

            if let Err(e) = init {
                let _ = tx.send(FirstBootMessage::Failed(format!("git init failed: {}", e)));
                return;
            }

            let _ = Command::new("git")
                .args(["rm", "--cached", "-f", ".first-boot-pending"])
                .current_dir(&config_dir)
                .output()
                .await;

            let gitignore_path = config_dir.join(".gitignore");
            let _ = tokio::fs::write(&gitignore_path, ".first-boot-pending\n").await;

            let add = Command::new("git")
                .args(["add", "."])
                .current_dir(&config_dir)
                .output()
                .await;

            if let Err(e) = add {
                let _ = tx.send(FirstBootMessage::Failed(format!("git add failed: {}", e)));
                return;
            }

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

    /// Skip the current step.
    pub fn skip(&mut self) {
        match self.phase {
            FirstBootPhase::ReviewPatch => {
                self.complete(
                    false,
                    "Skipped hardware reconciliation. The first-boot marker was preserved so you can retry later.",
                );
            }
            FirstBootPhase::ShowSshKey => {
                self.phase = FirstBootPhase::RemoteInput;
                self.remote_input.set_focused(true);
            }
            FirstBootPhase::RemoteInput => {
                self.push_skipped = true;
                self.complete(
                    true,
                    "Applied hardware reconciliation. Git push was skipped.",
                );
            }
            FirstBootPhase::Pushing => {
                self.push_skipped = true;
                self.complete(
                    true,
                    "Applied hardware reconciliation. Git push was skipped.",
                );
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
            self.complete(
                true,
                "Applied hardware reconciliation. Git push was skipped.",
            );
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

    pub fn handle_text_input(&mut self, key: crossterm::event::KeyEvent) {
        if self.phase == FirstBootPhase::RemoteInput {
            self.remote_input.handle_key(key);
        }
    }

    fn complete(&mut self, remove_marker: bool, message: &str) {
        self.done_message = message.to_string();
        self.marker_removed = remove_marker;
        if remove_marker {
            let marker = self.config.config_dir.join(".first-boot-pending");
            let _ = std::fs::remove_file(&marker);
        }
        self.phase = FirstBootPhase::Done;
    }

    pub fn poll(&mut self) {
        let rx = match self.rx.as_mut() {
            Some(rx) => rx,
            None => return,
        };

        let mut messages = Vec::new();
        while let Ok(msg) = rx.try_recv() {
            messages.push(msg);
        }

        for msg in messages {
            match msg {
                FirstBootMessage::Output(line) => {
                    self.output_lines.push(line);
                }
                FirstBootMessage::PatchPlanReady(plan) => {
                    self.hardware_plan = Some(plan);
                    self.phase = FirstBootPhase::ReviewPatch;
                }
                FirstBootMessage::NoChangesRequired(message) => {
                    self.complete(true, &message);
                }
                FirstBootMessage::GitReady => {
                    // Local commit done. Next: security enrollment (Stage 5).
                    // Push is deferred to Stage 6 after SSH keys are configured.
                    self.phase = FirstBootPhase::SecureBootEnroll;
                }
                FirstBootMessage::SshKey(key) => {
                    self.ssh_public_key = Some(key);
                }
                FirstBootMessage::PushResult(Ok(())) => {
                    self.output_lines.push("Push successful!".to_string());
                    self.complete(
                        true,
                        "Applied hardware reconciliation and pushed the repository successfully.",
                    );
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
            FirstBootPhase::DetectingHardware | FirstBootPhase::GitSetup => {
                self.render_progress(frame, area)
            }
            FirstBootPhase::ReviewPatch => self.render_review_patch(frame, area),
            // Security enrollment (Stage 5)
            FirstBootPhase::SecureBootEnroll => {
                self.render_enrollment_step(frame, area, "Secure Boot", "sbctl enroll-keys")
            }
            FirstBootPhase::TpmEnroll => {
                self.render_enrollment_step(frame, area, "TPM2", "systemd-cryptenroll")
            }
            FirstBootPhase::RebootPrompt => self.render_reboot_prompt(frame, area),
            // SSH + push (Stage 6)
            FirstBootPhase::SshKeySetup => {
                self.render_enrollment_step(frame, area, "SSH Keys", "ssh-keygen / GitHub import")
            }
            FirstBootPhase::ShowSshKey => self.render_ssh_key(frame, area),
            FirstBootPhase::RemoteInput => self.render_remote_input(frame, area),
            FirstBootPhase::Pushing => self.render_progress(frame, area),
            FirstBootPhase::SecretsSetup => {
                self.render_enrollment_step(frame, area, "Secrets", "agenix init")
            }
            FirstBootPhase::Done => self.render_done(frame, area),
            FirstBootPhase::Failed(err) => self.render_failed(frame, area, err),
        }
    }

    fn render_welcome(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "First boot: hardware reconciliation",
            t.active_style(),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let message = Paragraph::new(Text::styled(
            format!(
                "\n  Your system '{}' has been installed.\n\n  \
                 This wizard will:\n  \
                 1. Detect real hardware and update hardware.nix\n  \
                 2. Commit changes locally (push later)\n  \
                 3. Enroll Secure Boot keys\n  \
                 4. Enroll TPM2 for automatic disk unlock\n  \
                 5. Set up SSH keys and push to remote\n  \
                 6. Initialize secrets for services\n",
                self.config.hostname
            ),
            Style::default(),
        ))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.active)),
        );
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: detect hardware • q: exit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_progress(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let phase_label = match &self.phase {
            FirstBootPhase::DetectingHardware => "Detecting hardware and building patch plan...",
            FirstBootPhase::GitSetup => "Setting up git repository...",
            FirstBootPhase::Pushing => "Pushing to remote...",
            _ => "Working...",
        };

        let title = Paragraph::new(Text::styled(phase_label, t.title_style()))
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
                    .border_style(t.inactive_style()),
            )
            .wrap(Wrap { trim: false });
        frame.render_widget(output, chunks[1]);

        let help = Paragraph::new(Text::styled("Please wait...", t.inactive_style()))
            .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_review_patch(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Length(8),
                Constraint::Min(8),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Review hardware reconciliation",
            t.active_style(),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let summary_lines = if let Some(plan) = &self.hardware_plan {
            let mut lines = vec![
                Line::from(format!("  Host: {}", self.config.hostname)),
                Line::from(""),
                Line::from("  Detected disk identifiers:"),
            ];

            if plan.detected_disk_ids.is_empty() {
                lines.push(Line::from(Span::styled(
                    "  - none detected",
                    t.error_style(),
                )));
            } else {
                for disk in &plan.detected_disk_ids {
                    lines.push(Line::from(format!("  - {}", disk)));
                }
            }

            lines.push(Line::from(""));
            lines.push(Line::from("  Detected kernel modules:"));
            if plan.detected_kernel_modules.is_empty() {
                lines.push(Line::from("  - none detected"));
            } else {
                lines.push(Line::from(format!(
                    "  - {}",
                    plan.detected_kernel_modules.join(", ")
                )));
            }
            lines
        } else {
            vec![Line::from("  No hardware reconciliation plan available.")]
        };

        let summary = Paragraph::new(summary_lines)
            .block(
                Block::default()
                    .title("Summary")
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(t.active)),
            )
            .wrap(Wrap { trim: false });
        frame.render_widget(summary, chunks[1]);

        let diff_lines: Vec<Line> = self
            .hardware_plan
            .as_ref()
            .map(|plan| {
                plan.diff_preview
                    .iter()
                    .map(|line| {
                        let style = if line.starts_with('+') {
                            Style::default().fg(t.active)
                        } else if line.starts_with('-') {
                            Style::default().fg(t.error)
                        } else {
                            Style::default()
                        };
                        Line::from(Span::styled(format!("  {}", line), style))
                    })
                    .collect()
            })
            .unwrap_or_else(|| vec![Line::from("  No diff preview available.")]);

        let diff = Paragraph::new(diff_lines)
            .block(
                Block::default()
                    .title("Diff preview")
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(t.accent)),
            )
            .wrap(Wrap { trim: false });
        frame.render_widget(diff, chunks[2]);

        let help = Paragraph::new(Text::styled(
            "Enter: apply patch • s: skip for now • q: exit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[3]);
    }

    fn render_ssh_key(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("SSH Public Key", t.active_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let key_display = self.ssh_public_key.as_deref().unwrap_or("Loading...");

        let message = Paragraph::new(Text::from(vec![
            Line::from(""),
            Line::from("  Add this SSH key to GitHub:"),
            Line::from("  https://github.com/settings/keys"),
            Line::from(""),
            Line::from(Span::styled(format!("  {}", key_display), t.title_style())),
            Line::from(""),
        ]))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.active)),
        )
        .wrap(Wrap { trim: false });
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: continue to remote setup • s: skip push",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_remote_input(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Length(5),
                Constraint::Min(3),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("Git Remote", t.active_style()))
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
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[3]);
    }

    /// Generic enrollment step placeholder for SB, TPM, SSH, secrets.
    fn render_enrollment_step(&self, frame: &mut Frame, area: Rect, title: &str, tool: &str) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let heading = Paragraph::new(Text::styled(format!("Setup: {}", title), t.title_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(heading, chunks[0]);

        let body = Paragraph::new(Text::styled(
            format!(
                "\n  TODO: {} enrollment\n\n  \
                 Tool: {}\n\n  \
                 Press Enter to continue or 's' to skip.",
                title, tool,
            ),
            Style::default(),
        ))
        .block(Block::default().borders(Borders::ALL));
        frame.render_widget(body, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: proceed • s: skip • q: quit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_reboot_prompt(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let heading = Paragraph::new(Text::styled("Reboot required", t.title_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(heading, chunks[0]);

        let body = Paragraph::new(Text::styled(
            "\n  Secure Boot and TPM enrollment require a reboot to take effect.\n\n  \
             After rebooting, the TUI will continue with SSH key setup\n  \
             and push the pending hardware config commit.",
            Style::default(),
        ))
        .block(Block::default().borders(Borders::ALL));
        frame.render_widget(body, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "r: reboot now • s: skip (continue without reboot) • q: quit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_done(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("First-boot flow complete", t.active_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let marker_status = if self.marker_removed {
            "  First-boot marker: cleared"
        } else {
            "  First-boot marker: preserved"
        };

        let message = Paragraph::new(Text::from(vec![
            Line::from(""),
            Line::from(format!("  {}", self.done_message)),
            Line::from(marker_status),
            Line::from(""),
            Line::from(format!("  Config: {}", self.config.config_dir.display())),
            Line::from(""),
        ]))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.active)),
        );
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled("q: exit", t.inactive_style()))
            .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_failed(&self, frame: &mut Frame, area: Rect, error: &str) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "First-boot flow failed",
            t.error_style().add_modifier(Modifier::BOLD),
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
            t.error_style().add_modifier(Modifier::BOLD),
        )));

        let output = Paragraph::new(lines)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(t.error)),
            )
            .wrap(Wrap { trim: false });
        frame.render_widget(output, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "r: retry push • s: skip • q: exit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}

fn build_hardware_patch_plan(
    current_hardware_nix: &str,
    proposed_hardware_nix: &str,
) -> Result<HardwarePatchPlan, String> {
    let detected_disk_ids = extract_stable_disk_identifiers(proposed_hardware_nix);
    if detected_disk_ids.is_empty() {
        return Err(
            "No confident stable disk mapping was detected in the generated hardware config. The flow will not guess."
                .to_string(),
        );
    }

    let detected_kernel_modules = extract_kernel_modules(proposed_hardware_nix);
    let has_changes = current_hardware_nix.trim() != proposed_hardware_nix.trim();
    let diff_preview = build_diff_preview(current_hardware_nix, proposed_hardware_nix);

    Ok(HardwarePatchPlan {
        current_hardware_nix: current_hardware_nix.to_string(),
        proposed_hardware_nix: proposed_hardware_nix.to_string(),
        detected_disk_ids,
        detected_kernel_modules,
        diff_preview,
        has_changes,
    })
}

fn extract_stable_disk_identifiers(config: &str) -> Vec<String> {
    let mut ids = Vec::new();

    for line in config.lines() {
        for value in extract_quoted_strings(line) {
            if value.contains("/dev/disk/by-")
                || value.contains("UUID=")
                || value.contains("PARTUUID=")
            {
                push_unique(&mut ids, value);
            }
        }
    }

    ids
}

fn extract_kernel_modules(config: &str) -> Vec<String> {
    let mut modules = Vec::new();
    let mut in_modules_list = false;

    for line in config.lines() {
        let trimmed = line.trim();
        if trimmed.contains("boot.initrd.availableKernelModules")
            || trimmed.contains("boot.kernelModules")
        {
            in_modules_list = true;
        }

        if in_modules_list {
            for value in extract_quoted_strings(trimmed) {
                push_unique(&mut modules, value);
            }
            if trimmed.contains(']') {
                in_modules_list = false;
            }
        }
    }

    modules
}

fn extract_quoted_strings(line: &str) -> Vec<String> {
    let mut values = Vec::new();
    let mut current = String::new();
    let mut in_string = false;
    let mut escape = false;

    for ch in line.chars() {
        if !in_string {
            if ch == '"' {
                in_string = true;
                current.clear();
            }
            continue;
        }

        if escape {
            current.push(ch);
            escape = false;
            continue;
        }

        match ch {
            '\\' => escape = true,
            '"' => {
                in_string = false;
                values.push(current.clone());
                current.clear();
            }
            _ => current.push(ch),
        }
    }

    values
}

fn push_unique(values: &mut Vec<String>, candidate: String) {
    if !values.iter().any(|existing| existing == &candidate) {
        values.push(candidate);
    }
}

fn build_diff_preview(current: &str, proposed: &str) -> Vec<String> {
    let current_lines: Vec<&str> = current.lines().collect();
    let proposed_lines: Vec<&str> = proposed.lines().collect();
    let mut preview = Vec::new();
    let max_len = current_lines.len().max(proposed_lines.len());

    for idx in 0..max_len {
        let current_line = current_lines.get(idx);
        let proposed_line = proposed_lines.get(idx);

        if current_line == proposed_line {
            continue;
        }

        if let Some(line) = current_line {
            preview.push(format!("- {}", line));
        }
        if let Some(line) = proposed_line {
            preview.push(format!("+ {}", line));
        }

        if preview.len() >= 40 {
            preview.push("... diff truncated ...".to_string());
            break;
        }
    }

    if preview.is_empty() {
        preview.push("No changes.".to_string());
    }

    preview
}

impl Component for FirstBootScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(self.handle_key_event(key.code, key));
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        self.render(frame, area);
        Ok(())
    }
}

impl FirstBootScreen {
    /// Handle a key press, returning an optional global Action.
    fn handle_key_event(
        &mut self,
        code: KeyCode,
        key: &crossterm::event::KeyEvent,
    ) -> Option<Action> {
        match self.phase() {
            FirstBootPhase::Welcome => match code {
                KeyCode::Enter => {
                    self.start();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::DetectingHardware
            | FirstBootPhase::GitSetup
            | FirstBootPhase::Pushing => {
                // No user input during async phases
                None
            }
            // Security enrollment (Stage 5)
            FirstBootPhase::SecureBootEnroll => match code {
                // TODO: wire to security::secure_boot::enroll_keys()
                KeyCode::Enter => {
                    self.phase = FirstBootPhase::TpmEnroll;
                    None
                }
                KeyCode::Char('s') => {
                    self.phase = FirstBootPhase::TpmEnroll;
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::TpmEnroll => match code {
                // TODO: wire to security::tpm::enroll()
                KeyCode::Enter => {
                    self.phase = FirstBootPhase::RebootPrompt;
                    None
                }
                KeyCode::Char('s') => {
                    self.phase = FirstBootPhase::RebootPrompt;
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::RebootPrompt => match code {
                KeyCode::Char('r') => Some(Action::Reboot),
                KeyCode::Char('s') => {
                    // Skip reboot, continue to SSH key setup
                    self.phase = FirstBootPhase::SshKeySetup;
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            // Stage 6: SSH keys + push
            FirstBootPhase::SshKeySetup => match code {
                // TODO: wire to security::yubikey::detect_devices()
                // TODO: offer ssh-keygen, GitHub import, YubiKey enrollment
                KeyCode::Enter => {
                    self.continue_to_remote();
                    None
                }
                KeyCode::Char('s') => {
                    self.skip();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::SecretsSetup => match code {
                // TODO: wire to agenix secrets init
                KeyCode::Enter | KeyCode::Char('s') => {
                    self.complete(true, "Onboarding complete!");
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::ReviewPatch => match code {
                KeyCode::Enter => {
                    self.apply_patch();
                    None
                }
                KeyCode::Char('s') => {
                    self.skip();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::ShowSshKey => match code {
                KeyCode::Enter => {
                    self.continue_to_remote();
                    None
                }
                KeyCode::Char('s') => {
                    self.skip();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::RemoteInput => match code {
                KeyCode::Enter => {
                    self.submit_remote();
                    None
                }
                KeyCode::Esc => {
                    self.skip();
                    None
                }
                _ => {
                    self.handle_text_input(*key);
                    None
                }
            },
            FirstBootPhase::Done => match code {
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            FirstBootPhase::Failed(_) => match code {
                KeyCode::Char('r') => {
                    self.retry_push();
                    None
                }
                KeyCode::Char('s') => {
                    self.skip();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_first_boot_config() -> FirstBootConfig {
        FirstBootConfig {
            config_dir: PathBuf::from("/home/testuser/.worktrees/ncrmro/nixos-config/main"),
            hostname: "test-machine".to_string(),
            username: "testuser".to_string(),
            github_username: Some("octocat".to_string()),
        }
    }

    fn sample_generated_hardware() -> &'static str {
        r#"{
  fileSystems."/" = {
    device = "/dev/disk/by-id/nvme-Samsung_990_PRO";
  };

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" ];
}
"#
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
            config_dir: PathBuf::from("/home/testuser/.worktrees/ncrmro/nixos-config/main"),
            hostname: "test-machine".to_string(),
            username: "testuser".to_string(),
            github_username: None,
        };
        let screen = FirstBootScreen::new(config);
        assert_eq!(screen.remote_input.value(), "");
    }

    #[test]
    fn test_build_patch_plan_detects_changes_and_summary() {
        let current = "{\n  # placeholder\n}\n";
        let plan = build_hardware_patch_plan(current, sample_generated_hardware()).unwrap();

        assert!(plan.has_changes);
        assert_eq!(
            plan.detected_disk_ids,
            vec!["/dev/disk/by-id/nvme-Samsung_990_PRO".to_string()]
        );
        assert_eq!(
            plan.detected_kernel_modules,
            vec![
                "nvme".to_string(),
                "xhci_pci".to_string(),
                "thunderbolt".to_string()
            ]
        );
        assert!(plan.diff_preview.iter().any(|line| line.starts_with('+')));
    }

    #[test]
    fn test_build_patch_plan_no_changes() {
        let plan =
            build_hardware_patch_plan(sample_generated_hardware(), sample_generated_hardware())
                .unwrap();
        assert!(!plan.has_changes);
        assert_eq!(plan.diff_preview, vec!["No changes.".to_string()]);
    }

    #[test]
    fn test_build_patch_plan_requires_confident_disk_mapping() {
        let generated = r#"{
  boot.initrd.availableKernelModules = [ "nvme" ];
}
"#;
        let err = build_hardware_patch_plan("{ }", generated).unwrap_err();
        assert!(err.contains("No confident stable disk mapping"));
    }

    #[test]
    fn test_skip_from_review_preserves_marker() {
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.phase = FirstBootPhase::ReviewPatch;
        screen.skip();
        assert_eq!(*screen.phase(), FirstBootPhase::Done);
        assert!(!screen.marker_removed);
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
        assert!(screen.marker_removed);
    }

    #[test]
    fn test_poll_patch_plan_ready() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_first_boot_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::DetectingHardware;

        tx.send(FirstBootMessage::PatchPlanReady(
            build_hardware_patch_plan("{ }", sample_generated_hardware()).unwrap(),
        ))
        .unwrap();

        screen.poll();
        assert_eq!(*screen.phase(), FirstBootPhase::ReviewPatch);
        assert!(screen.hardware_plan().is_some());
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
        assert!(screen.marker_removed);
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
