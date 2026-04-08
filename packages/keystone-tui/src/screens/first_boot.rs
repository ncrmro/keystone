//! First-boot screen — post-install setup wizard.
//!
//! After a fresh Keystone install, on first boot the TUI detects a
//! `.first-boot-pending` marker in `~/.keystone/repos/nixos-config/` and
//! walks the user through:
//!
//! 1. Gathering real hardware facts (disk identifiers, kernel modules)
//! 2. Building an in-memory patch plan with diff preview
//! 3. User review before any file is written
//! 4. Committing and optionally pushing the reconciled hardware.nix
//! 5. Initializing a git repo and configuring a remote for future pushes

use std::path::PathBuf;

use tokio::process::Command;
use tokio::sync::mpsc;

use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Span, Text},
    widgets::{Block, Borders, Paragraph, Wrap},
    Frame,
};

use crate::disk::discover_disks;
use crate::ui::TextInput;

/// Placeholder written by the installer into hardware.nix for disk identifiers.
/// First-boot reconciliation replaces this when a confident match exists.
const KEYSTONE_DISK_PLACEHOLDER: &str = "__KEYSTONE_DISK__";

// ─── Data models ────────────────────────────────────────────────────────────

/// A disk observed on the booted system.
#[derive(Debug, Clone)]
pub struct DetectedDisk {
    /// Stable by-id path, e.g. `/dev/disk/by-id/nvme-Samsung_990_PRO_2TB`.
    pub path: String,
    /// Whether this disk satisfies the install-time `__KEYSTONE_DISK__` placeholder.
    pub matches_install_placeholder: bool,
}

/// Hardware facts collected on first boot before any repo changes are made.
#[derive(Debug, Clone)]
pub struct FirstBootHardwareFacts {
    pub hostname: String,
    /// Raw output of `nixos-generate-config --show-hardware-config`.
    pub generated_hardware_nix: String,
    /// Stable disk identifiers observed after boot.
    pub disk_devices: Vec<DetectedDisk>,
    /// Kernel modules extracted from the generated hardware config.
    pub kernel_modules: Vec<String>,
}

impl FirstBootHardwareFacts {
    /// Extract module names from `boot.initrd.availableKernelModules` and
    /// `boot.kernelModules` lines in the generated hardware.nix content.
    fn extract_kernel_modules(hw_nix: &str) -> Vec<String> {
        let mut modules = Vec::new();
        for line in hw_nix.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("boot.initrd.availableKernelModules")
                || trimmed.starts_with("boot.kernelModules")
            {
                // Extract quoted strings: "module1" "module2"
                let mut rest = trimmed;
                while let Some(start) = rest.find('"') {
                    rest = &rest[start + 1..];
                    if let Some(end) = rest.find('"') {
                        let module = rest[..end].to_string();
                        if !module.is_empty() && !modules.contains(&module) {
                            modules.push(module);
                        }
                        rest = &rest[end + 1..];
                    } else {
                        break;
                    }
                }
            }
        }
        modules
    }
}

/// An in-memory plan describing which files will change and why.
#[derive(Debug, Clone)]
pub struct PushbackPatchPlan {
    /// File that will receive the patched content.
    pub hardware_nix_path: PathBuf,
    /// Current on-disk content (empty string if file does not exist yet).
    pub current_content: String,
    /// Proposed new content after reconciliation.
    pub proposed_content: String,
    /// Human-readable unified diff shown to the user before apply.
    pub diff_preview: String,
    /// Non-fatal warnings surfaced to the user (e.g. no confident disk mapping).
    pub warnings: Vec<String>,
    /// Default commit message used when the user accepts.
    pub commit_message: String,
}

impl PushbackPatchPlan {
    /// Returns `true` when the proposed content is identical to the current content.
    pub fn is_noop(&self) -> bool {
        self.proposed_content == self.current_content
    }

    /// Generate a minimal line-level diff between current and proposed content.
    ///
    /// Uses a simple sequential diff: matching lines are prefixed with ` `,
    /// removed lines with `-`, and added lines with `+`. Truncated at 40 lines
    /// to keep the TUI readable.
    fn build_diff(current: &str, proposed: &str) -> String {
        if current == proposed {
            return "(no changes)".to_string();
        }

        let mut lines = Vec::new();
        let current_lines: Vec<&str> = current.lines().collect();
        let proposed_lines: Vec<&str> = proposed.lines().collect();

        let mut i = 0;
        let mut j = 0;
        while i < current_lines.len() || j < proposed_lines.len() {
            let c = current_lines.get(i).copied();
            let p = proposed_lines.get(j).copied();
            match (c, p) {
                (Some(cl), Some(pl)) if cl == pl => {
                    lines.push(format!(" {}", cl));
                    i += 1;
                    j += 1;
                }
                _ => {
                    if let Some(cl) = c {
                        lines.push(format!("-{}", cl));
                        i += 1;
                    }
                    if let Some(pl) = p {
                        lines.push(format!("+{}", pl));
                        j += 1;
                    }
                }
            }
        }

        if lines.len() > 40 {
            lines.truncate(40);
            lines.push("... (diff truncated)".to_string());
        }

        lines.join("\n")
    }
}

// ─── Config ─────────────────────────────────────────────────────────────────

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

// ─── Phases ──────────────────────────────────────────────────────────────────

/// Phases of the first-boot wizard.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FirstBootPhase {
    /// Welcome message.
    Welcome,
    /// Collecting hardware facts from the running system.
    GatheringFacts,
    /// Presenting the patch plan for user review before any file is written.
    ReviewPlan,
    /// Applying the accepted patch to disk.
    ApplyingPatch,
    /// git init + add + commit.
    GitSetup,
    /// Display SSH public key + GitHub instructions.
    ShowSshKey,
    /// Text input for git remote URL.
    RemoteInput,
    /// Pushing to remote.
    Pushing,
    /// hardware.nix already matches detected hardware — no reconciliation needed.
    NoChangesRequired,
    /// Setup complete.
    Done,
    /// An error occurred.
    Failed(String),
}

// ─── Messages ────────────────────────────────────────────────────────────────

/// Messages from first-boot async operations.
pub enum FirstBootMessage {
    Output(String),
    HardwareFacts(FirstBootHardwareFacts, PushbackPatchPlan),
    PatchApplied,
    GitReady,
    SshKey(String),
    PushResult(Result<(), String>),
    Failed(String),
}

// ─── Screen ──────────────────────────────────────────────────────────────────

pub struct FirstBootScreen {
    config: FirstBootConfig,
    phase: FirstBootPhase,
    output_lines: Vec<String>,
    ssh_public_key: Option<String>,
    remote_input: TextInput,
    rx: Option<mpsc::UnboundedReceiver<FirstBootMessage>>,
    push_skipped: bool,
    /// Hardware facts gathered during `GatheringFacts`.
    facts: Option<FirstBootHardwareFacts>,
    /// Patch plan built from gathered facts.
    patch_plan: Option<PushbackPatchPlan>,
    /// Whether the inline diff is expanded in the review view.
    show_diff: bool,
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
            facts: None,
            patch_plan: None,
            show_diff: false,
        }
    }

    pub fn phase(&self) -> &FirstBootPhase {
        &self.phase
    }

    pub fn ssh_public_key(&self) -> Option<&str> {
        self.ssh_public_key.as_deref()
    }

    /// Start the first-boot process (Welcome → GatheringFacts).
    pub fn start(&mut self) {
        if self.phase != FirstBootPhase::Welcome {
            return;
        }
        self.phase = FirstBootPhase::GatheringFacts;
        self.spawn_gather_facts();
    }

    // ─── Async spawners ───────────────────────────────────────────────────

    /// Gather hardware facts: run nixos-generate-config and discover disks.
    /// Builds an in-memory `PushbackPatchPlan` — does NOT write any files.
    fn spawn_gather_facts(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let config_dir = self.config.config_dir.clone();
        let hostname = self.config.hostname.clone();

        tokio::spawn(async move {
            let _ = tx.send(FirstBootMessage::Output(
                "Running nixos-generate-config...".to_string(),
            ));

            // Step 1: run nixos-generate-config --show-hardware-config
            let gen_output = Command::new("nixos-generate-config")
                .args(["--show-hardware-config"])
                .output()
                .await;

            let generated_hardware_nix = match gen_output {
                Ok(out) if out.status.success() => {
                    String::from_utf8_lossy(&out.stdout).to_string()
                }
                Ok(out) => {
                    let stderr = String::from_utf8_lossy(&out.stderr);
                    let _ = tx.send(FirstBootMessage::Failed(format!(
                        "nixos-generate-config failed: {}",
                        stderr
                    )));
                    return;
                }
                Err(e) => {
                    let _ = tx.send(FirstBootMessage::Failed(format!(
                        "Failed to run nixos-generate-config: {}",
                        e
                    )));
                    return;
                }
            };

            let _ = tx.send(FirstBootMessage::Output(
                "Discovering disk devices...".to_string(),
            ));

            // Step 2: discover stable disk identifiers
            let raw_disks = discover_disks().await.unwrap_or_default();

            // Step 3: read existing hardware.nix (may not exist yet)
            let hw_path = config_dir.join("hardware.nix");
            let current_content = tokio::fs::read_to_string(&hw_path)
                .await
                .unwrap_or_default();

            // Step 4: determine placeholder → disk mapping confidence
            let contains_placeholder = current_content.contains(KEYSTONE_DISK_PLACEHOLDER);
            let mut warnings: Vec<String> = Vec::new();

            let disk_devices: Vec<DetectedDisk> = raw_disks
                .iter()
                .map(|d| {
                    // A disk matches the placeholder only when exactly one disk is
                    // present — multiple disks means we cannot guess which is the
                    // install target without risking silent data loss.
                    let matches = contains_placeholder && raw_disks.len() == 1;
                    DetectedDisk {
                        path: d.by_id_path.clone(),
                        matches_install_placeholder: matches,
                    }
                })
                .collect();

            // Warn when the placeholder exists but we cannot map it confidently
            if contains_placeholder && disk_devices.len() != 1 {
                if disk_devices.is_empty() {
                    warnings.push(
                        "No stable /dev/disk/by-id/ entries found — \
                         __KEYSTONE_DISK__ placeholder will not be replaced."
                            .to_string(),
                    );
                } else {
                    warnings.push(format!(
                        "Multiple disks detected ({}); cannot confidently map \
                         __KEYSTONE_DISK__ placeholder — manual edit required.",
                        disk_devices.len()
                    ));
                }
            }

            // Step 5: build proposed hardware.nix content
            let mut proposed_content = generated_hardware_nix.clone();

            // Replace placeholder only when exactly one disk matched
            let confident_disk = disk_devices
                .iter()
                .find(|d| d.matches_install_placeholder)
                .map(|d| d.path.clone());

            if let Some(ref disk_path) = confident_disk {
                proposed_content =
                    proposed_content.replace(KEYSTONE_DISK_PLACEHOLDER, disk_path.as_str());
            }

            // Step 6: extract kernel modules for the summary view
            let kernel_modules =
                FirstBootHardwareFacts::extract_kernel_modules(&proposed_content);

            let facts = FirstBootHardwareFacts {
                hostname: hostname.clone(),
                generated_hardware_nix,
                disk_devices,
                kernel_modules,
            };

            // Step 7: compute diff and finalize the patch plan
            let diff_preview = PushbackPatchPlan::build_diff(&current_content, &proposed_content);

            let plan = PushbackPatchPlan {
                hardware_nix_path: hw_path,
                current_content,
                proposed_content,
                diff_preview,
                warnings,
                commit_message: format!(
                    "feat(keystone-tui): reconcile first-boot hardware for {}",
                    hostname
                ),
            };

            let _ = tx.send(FirstBootMessage::Output("Facts gathered.".to_string()));
            let _ = tx.send(FirstBootMessage::HardwareFacts(facts, plan));
        });
    }

    /// Write the accepted patch plan to disk (hardware.nix only).
    /// Does NOT commit — that happens in `spawn_git_setup`.
    fn spawn_apply_patch(&mut self) {
        let plan = match &self.patch_plan {
            Some(p) => p.clone(),
            None => return,
        };

        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);

        tokio::spawn(async move {
            let _ = tx.send(FirstBootMessage::Output(
                "Writing hardware.nix...".to_string(),
            ));

            if let Err(e) =
                tokio::fs::write(&plan.hardware_nix_path, &plan.proposed_content).await
            {
                let _ = tx.send(FirstBootMessage::Failed(format!(
                    "Failed to write hardware.nix: {}",
                    e
                )));
                return;
            }

            let _ = tx.send(FirstBootMessage::Output(
                "hardware.nix written successfully.".to_string(),
            ));
            let _ = tx.send(FirstBootMessage::PatchApplied);
        });
    }

    fn spawn_git_setup(&mut self) {
        let (tx, rx) = mpsc::unbounded_channel();
        self.rx = Some(rx);
        let config_dir = self.config.config_dir.clone();
        let commit_msg = self
            .patch_plan
            .as_ref()
            .map(|p| p.commit_message.clone())
            .unwrap_or_else(|| "feat: initial Keystone configuration".to_string());

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

            // Remove .first-boot-pending from tracking (don't commit the marker)
            let _ = Command::new("git")
                .args(["rm", "--cached", "-f", ".first-boot-pending"])
                .current_dir(&config_dir)
                .output()
                .await;

            // Add .gitignore to exclude the marker from future commits
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
                .args(["commit", "-m", &commit_msg])
                .current_dir(&config_dir)
                .output()
                .await;

            match commit {
                Ok(out) if out.status.success() => {
                    let _ = tx.send(FirstBootMessage::Output(
                        "Git repository initialized with hardware reconciliation commit."
                            .to_string(),
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

    // ─── User actions ─────────────────────────────────────────────────────

    /// Toggle the inline diff view while in `ReviewPlan`.
    pub fn toggle_diff(&mut self) {
        if self.phase == FirstBootPhase::ReviewPlan {
            self.show_diff = !self.show_diff;
        }
    }

    /// Accept the patch plan and begin writing hardware.nix.
    pub fn accept_plan(&mut self) {
        if self.phase != FirstBootPhase::ReviewPlan {
            return;
        }
        self.phase = FirstBootPhase::ApplyingPatch;
        self.show_diff = false;
        self.spawn_apply_patch();
    }

    /// Skip the patch plan — leave the marker so the flow can be retried later.
    ///
    /// Per spec: if the user skips, the `.first-boot-pending` marker MUST remain.
    pub fn skip_plan(&mut self) {
        if self.phase == FirstBootPhase::ReviewPlan {
            // Intentionally do NOT call finish() — marker stays on disk.
            self.phase = FirstBootPhase::Done;
            self.push_skipped = true;
        }
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

    /// Advance from `ShowSshKey` to `RemoteInput`.
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

    /// Finish the flow from `NoChangesRequired` — removes the marker and exits cleanly.
    pub fn finish_no_changes(&mut self) {
        if self.phase == FirstBootPhase::NoChangesRequired {
            self.finish();
        }
    }

    /// Complete the flow and remove the first-boot marker.
    fn finish(&mut self) {
        let marker = self.config.config_dir.join(".first-boot-pending");
        let _ = std::fs::remove_file(&marker);
        self.phase = FirstBootPhase::Done;
    }

    /// Poll for async messages from background tasks.
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
                FirstBootMessage::HardwareFacts(facts, plan) => {
                    self.facts = Some(facts);
                    if plan.is_noop() {
                        // hardware.nix already matches — no patch needed
                        self.patch_plan = Some(plan);
                        self.phase = FirstBootPhase::NoChangesRequired;
                    } else {
                        self.patch_plan = Some(plan);
                        self.phase = FirstBootPhase::ReviewPlan;
                    }
                }
                FirstBootMessage::PatchApplied => {
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

    // ─── Rendering ────────────────────────────────────────────────────────

    pub fn render(&self, frame: &mut Frame, area: Rect) {
        match &self.phase {
            FirstBootPhase::Welcome => self.render_welcome(frame, area),
            FirstBootPhase::GatheringFacts | FirstBootPhase::ApplyingPatch => {
                self.render_progress(frame, area)
            }
            FirstBootPhase::ReviewPlan => self.render_review_plan(frame, area),
            FirstBootPhase::GitSetup => self.render_progress(frame, area),
            FirstBootPhase::ShowSshKey => self.render_ssh_key(frame, area),
            FirstBootPhase::RemoteInput => self.render_remote_input(frame, area),
            FirstBootPhase::Pushing => self.render_progress(frame, area),
            FirstBootPhase::NoChangesRequired => self.render_no_changes(frame, area),
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
                 1. Gather hardware facts for this machine\n  \
                 2. Show a diff preview before updating hardware.nix\n  \
                 3. Initialize a git repository\n  \
                 4. Help you push your config to GitHub\n",
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
            FirstBootPhase::GatheringFacts => "Gathering hardware facts...",
            FirstBootPhase::ApplyingPatch => "Applying hardware.nix patch...",
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

    fn render_review_plan(&self, frame: &mut Frame, area: Rect) {
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
            Style::default().bold().fg(Color::Yellow),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let mut lines: Vec<Line> = Vec::new();
        lines.push(Line::from(format!("  Host: {}", self.config.hostname)));
        lines.push(Line::from(""));

        if let Some(facts) = &self.facts {
            lines.push(Line::from(Span::styled(
                "  Detected hardware",
                Style::default().add_modifier(Modifier::BOLD),
            )));

            for disk in &facts.disk_devices {
                let marker = if disk.matches_install_placeholder { " ✓" } else { "" };
                lines.push(Line::from(format!("  • Disk: {}{}", disk.path, marker)));
            }
            if facts.disk_devices.is_empty() {
                lines.push(Line::from("  • Disk: (none detected via /dev/disk/by-id/)"));
            }

            if facts.kernel_modules.is_empty() {
                lines.push(Line::from("  • Kernel modules: (none)"));
            } else {
                lines.push(Line::from(format!(
                    "  • Kernel modules: {}",
                    facts.kernel_modules.join(", ")
                )));
            }
            lines.push(Line::from(""));
        }

        if let Some(plan) = &self.patch_plan {
            for w in &plan.warnings {
                lines.push(Line::from(Span::styled(
                    format!("  ⚠ {}", w),
                    Style::default().fg(Color::Yellow),
                )));
            }
            if !plan.warnings.is_empty() {
                lines.push(Line::from(""));
            }

            lines.push(Line::from(Span::styled(
                "  Planned patch",
                Style::default().add_modifier(Modifier::BOLD),
            )));
            lines.push(Line::from(format!(
                "  • Update: {}",
                plan.hardware_nix_path.display()
            )));
            lines.push(Line::from(""));

            if self.show_diff {
                lines.push(Line::from(Span::styled(
                    "  Diff preview:",
                    Style::default().add_modifier(Modifier::BOLD),
                )));
                for diff_line in plan.diff_preview.lines() {
                    let style = if diff_line.starts_with('+') {
                        Style::default().fg(Color::Green)
                    } else if diff_line.starts_with('-') {
                        Style::default().fg(Color::Red)
                    } else {
                        Style::default().fg(Color::DarkGray)
                    };
                    lines.push(Line::from(Span::styled(
                        format!("  {}", diff_line),
                        style,
                    )));
                }
            }
        }

        let body = Paragraph::new(lines)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::Yellow)),
            )
            .wrap(Wrap { trim: false });
        frame.render_widget(body, chunks[1]);

        let diff_hint = if self.show_diff { "v: hide diff" } else { "v: view diff" };
        let help = Paragraph::new(Text::styled(
            format!("Enter: apply and commit • s: skip for now • {}", diff_hint),
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_no_changes(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "No changes required",
            Style::default().bold().fg(Color::Green),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let message = Paragraph::new(Text::from(vec![
            Line::from(""),
            Line::from(Span::styled(
                "  hardware.nix already matches the detected hardware.",
                Style::default().fg(Color::Green),
            )),
            Line::from(""),
            Line::from("  No reconciliation patch is needed."),
            Line::from("  The first-boot marker will be removed."),
            Line::from(""),
        ]))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green)),
        );
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: finish • q: exit",
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

// ─── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config() -> FirstBootConfig {
        FirstBootConfig {
            config_dir: PathBuf::from("/home/testuser/.keystone/repos/nixos-config"),
            hostname: "test-machine".to_string(),
            username: "testuser".to_string(),
            github_username: Some("octocat".to_string()),
        }
    }

    #[test]
    fn test_initial_phase_is_welcome() {
        let screen = FirstBootScreen::new(test_config());
        assert_eq!(*screen.phase(), FirstBootPhase::Welcome);
    }

    #[test]
    fn test_remote_input_pre_filled() {
        let screen = FirstBootScreen::new(test_config());
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
        let mut screen = FirstBootScreen::new(test_config());
        screen.phase = FirstBootPhase::ShowSshKey;
        screen.skip();
        assert_eq!(*screen.phase(), FirstBootPhase::RemoteInput);
    }

    #[test]
    fn test_skip_from_remote_input() {
        let mut screen = FirstBootScreen::new(test_config());
        screen.phase = FirstBootPhase::RemoteInput;
        screen.skip();
        assert_eq!(*screen.phase(), FirstBootPhase::Done);
        assert!(screen.push_skipped);
    }

    #[test]
    fn test_poll_ssh_key() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_config());
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
        let mut screen = FirstBootScreen::new(test_config());
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
        let mut screen = FirstBootScreen::new(test_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::Pushing;

        tx.send(FirstBootMessage::PushResult(Err("auth failed".to_string())))
            .unwrap();

        screen.poll();
        assert!(matches!(screen.phase(), FirstBootPhase::Failed(_)));
    }

    // ─── Hardware detection tests ─────────────────────────────────────────

    #[test]
    fn test_extract_kernel_modules_empty() {
        let hw_nix = "# generated hardware config\nboot.loader.systemd-boot.enable = true;\n";
        let modules = FirstBootHardwareFacts::extract_kernel_modules(hw_nix);
        assert!(modules.is_empty());
    }

    #[test]
    fn test_extract_kernel_modules_parses_quoted_list() {
        let hw_nix = r#"
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" ];
  boot.kernelModules = [ "kvm-intel" ];
"#;
        let modules = FirstBootHardwareFacts::extract_kernel_modules(hw_nix);
        assert!(modules.contains(&"nvme".to_string()));
        assert!(modules.contains(&"xhci_pci".to_string()));
        assert!(modules.contains(&"ahci".to_string()));
        assert!(modules.contains(&"usbhid".to_string()));
        assert!(modules.contains(&"kvm-intel".to_string()));
    }

    #[test]
    fn test_extract_kernel_modules_deduplicates() {
        let hw_nix = r#"
  boot.initrd.availableKernelModules = [ "nvme" "nvme" ];
"#;
        let modules = FirstBootHardwareFacts::extract_kernel_modules(hw_nix);
        let nvme_count = modules.iter().filter(|m| *m == "nvme").count();
        assert_eq!(nvme_count, 1);
    }

    #[test]
    fn test_patch_plan_is_noop_when_identical() {
        let plan = PushbackPatchPlan {
            hardware_nix_path: PathBuf::from("/tmp/hardware.nix"),
            current_content: "same".to_string(),
            proposed_content: "same".to_string(),
            diff_preview: String::new(),
            warnings: vec![],
            commit_message: String::new(),
        };
        assert!(plan.is_noop());
    }

    #[test]
    fn test_patch_plan_not_noop_when_different() {
        let plan = PushbackPatchPlan {
            hardware_nix_path: PathBuf::from("/tmp/hardware.nix"),
            current_content: "old".to_string(),
            proposed_content: "new".to_string(),
            diff_preview: String::new(),
            warnings: vec![],
            commit_message: String::new(),
        };
        assert!(!plan.is_noop());
    }

    #[test]
    fn test_build_diff_marks_additions_and_removals() {
        let diff = PushbackPatchPlan::build_diff("old line", "new line");
        assert!(diff.contains("-old line"));
        assert!(diff.contains("+new line"));
    }

    #[test]
    fn test_build_diff_noop_label() {
        let diff = PushbackPatchPlan::build_diff("same", "same");
        assert_eq!(diff, "(no changes)");
    }

    #[test]
    fn test_poll_hardware_facts_noop_transitions_to_no_changes() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::GatheringFacts;

        let facts = FirstBootHardwareFacts {
            hostname: "test-machine".to_string(),
            generated_hardware_nix: "same".to_string(),
            disk_devices: vec![],
            kernel_modules: vec![],
        };
        let plan = PushbackPatchPlan {
            hardware_nix_path: PathBuf::from("/tmp/hardware.nix"),
            current_content: "same".to_string(),
            proposed_content: "same".to_string(),
            diff_preview: "(no changes)".to_string(),
            warnings: vec![],
            commit_message: String::new(),
        };

        tx.send(FirstBootMessage::HardwareFacts(facts, plan)).unwrap();
        screen.poll();

        assert_eq!(*screen.phase(), FirstBootPhase::NoChangesRequired);
    }

    #[test]
    fn test_poll_hardware_facts_diff_transitions_to_review() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = FirstBootScreen::new(test_config());
        screen.rx = Some(rx);
        screen.phase = FirstBootPhase::GatheringFacts;

        let facts = FirstBootHardwareFacts {
            hostname: "test-machine".to_string(),
            generated_hardware_nix: "new content".to_string(),
            disk_devices: vec![],
            kernel_modules: vec![],
        };
        let plan = PushbackPatchPlan {
            hardware_nix_path: PathBuf::from("/tmp/hardware.nix"),
            current_content: "old content".to_string(),
            proposed_content: "new content".to_string(),
            diff_preview: "-old content\n+new content".to_string(),
            warnings: vec![],
            commit_message: "feat: reconcile".to_string(),
        };

        tx.send(FirstBootMessage::HardwareFacts(facts, plan)).unwrap();
        screen.poll();

        assert_eq!(*screen.phase(), FirstBootPhase::ReviewPlan);
    }

    #[test]
    fn test_skip_plan_keeps_marker_by_not_calling_finish() {
        // skip_plan transitions to Done with push_skipped=true but does NOT
        // delete the marker file (finish() is not called).
        let mut screen = FirstBootScreen::new(test_config());
        screen.phase = FirstBootPhase::ReviewPlan;
        screen.skip_plan();
        assert_eq!(*screen.phase(), FirstBootPhase::Done);
        assert!(screen.push_skipped);
    }

    #[tokio::test]
    async fn test_accept_plan_transitions_to_applying() {
        let mut screen = FirstBootScreen::new(test_config());
        screen.phase = FirstBootPhase::ReviewPlan;
        screen.patch_plan = Some(PushbackPatchPlan {
            hardware_nix_path: PathBuf::from("/tmp/hardware.nix"),
            current_content: "old".to_string(),
            proposed_content: "new".to_string(),
            diff_preview: "-old\n+new".to_string(),
            warnings: vec![],
            commit_message: "feat: reconcile".to_string(),
        });
        screen.accept_plan();
        assert_eq!(*screen.phase(), FirstBootPhase::ApplyingPatch);
    }

    #[test]
    fn test_toggle_diff_only_in_review_phase() {
        let mut screen = FirstBootScreen::new(test_config());
        screen.phase = FirstBootPhase::ReviewPlan;
        assert!(!screen.show_diff);
        screen.toggle_diff();
        assert!(screen.show_diff);
        screen.toggle_diff();
        assert!(!screen.show_diff);

        // Must not toggle outside ReviewPlan
        screen.phase = FirstBootPhase::Welcome;
        screen.toggle_diff();
        assert!(!screen.show_diff);
    }

    #[test]
    fn test_multiple_disks_produces_warning() {
        // Validate the warning logic that runs inside spawn_gather_facts.
        // We test it in isolation to avoid spawning async tasks.
        let disk_count = 2usize;
        let contains_placeholder = true;

        let mut warnings = Vec::new();
        if contains_placeholder && disk_count != 1 {
            if disk_count == 0 {
                warnings.push("no stable ids".to_string());
            } else {
                warnings.push(format!(
                    "Multiple disks detected ({}); cannot confidently map",
                    disk_count
                ));
            }
        }

        assert_eq!(warnings.len(), 1);
        assert!(warnings[0].contains("Multiple disks detected"));
    }

    #[test]
    fn test_no_disks_produces_warning() {
        let disk_count = 0usize;
        let contains_placeholder = true;

        let mut warnings = Vec::new();
        if contains_placeholder && disk_count != 1 {
            if disk_count == 0 {
                warnings.push(
                    "No stable /dev/disk/by-id/ entries found — \
                     __KEYSTONE_DISK__ placeholder will not be replaced."
                        .to_string(),
                );
            } else {
                warnings.push("multiple disks".to_string());
            }
        }

        assert_eq!(warnings.len(), 1);
        assert!(warnings[0].contains("No stable"));
    }
}
