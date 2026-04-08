//! Install screen — streamlined installer flow for pre-baked ISOs.
//!
//! When the TUI boots on an ISO with either an embedded flake repo at
//! `/etc/keystone/install-repo/` or a legacy config bundle at
//! `/etc/keystone/install-config/`, this screen drives the install:
//!
//! 1. **Host selection** — Choose the target host from the embedded flake repo
//! 2. **Summary** — Show the selected config (hostname, storage, user)
//! 3. **Disk selection** — Choose the destination disk explicitly
//! 4. **Confirm** — Final warning before erasing the disk
//! 5. **Install** — Run disko + nixos-install, streaming output
//! 6. **Done** — Prompt to remove USB and reboot

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::{Command as StdCommand, Stdio};

use anyhow::{Context, Result as AnyhowResult};
use crossterm::event::{Event, KeyCode, KeyEventKind};
use serde::Deserialize;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use crate::action::Action;
use crate::component::Component;
use crate::disk::DiskEntry;
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame,
};

const INSTALL_REPO_PATH: &str = "/etc/keystone/install-repo";
const INSTALL_CONFIG_PATH: &str = "/etc/keystone/install-config";
const INSTALL_KEYSTONE_PATH: &str = "/etc/keystone/install-keystone";
const INSTALL_METADATA_DIR: &str = "/etc/keystone/install-metadata";
const WRITABLE_INSTALL_REPO_PATH: &str = "/tmp/keystone-install-repo";
const WRITABLE_INSTALL_KEYSTONE_PATH: &str = "/tmp/keystone-install-keystone";
const VENDORED_KEYSTONE_INPUT_DIR: &str = ".keystone-input";

#[derive(Debug, Clone)]
pub enum InstallSource {
    EmbeddedRepo {
        repo_dir: PathBuf,
        repo_name: String,
        targets: Vec<InstallTarget>,
    },
    PrebakedConfig,
}

#[derive(Debug, Clone)]
pub struct InstallTarget {
    pub flake_host: String,
    pub hostname: String,
    pub system: Option<String>,
    pub storage_type: Option<String>,
    pub hardware_path: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct InstallTargetJson {
    hostname: String,
    system: Option<String>,
    storage_type: Option<String>,
    hardware_path: String,
}

/// Configuration parsed from the embedded installer repo or legacy config bundle.
#[derive(Debug, Clone)]
pub struct InstallerConfig {
    pub source: InstallSource,
    pub config_dir: PathBuf,
    pub flake_host: String,
    pub hostname: String,
    pub username: Option<String>,
    pub repo_owner: Option<String>,
    pub github_username: Option<String>,
    pub storage_type: Option<String>,
    pub disk_device: Option<String>,
    pub hardware_path: Option<PathBuf>,
}

impl InstallerConfig {
    /// Detect installer mode by checking for embedded repo or config at the well-known paths.
    ///
    /// The ISO filesystem is read-only (squashfs). Legacy config bundles are
    /// copied to a writable tmpdir before returning. Embedded repos are copied
    /// after host selection so disk choice can patch the selected host's
    /// hardware file.
    pub fn detect() -> AnyhowResult<Option<Self>> {
        let repo_dir = Path::new(INSTALL_REPO_PATH);
        if repo_dir.exists() {
            let targets = load_install_targets(repo_dir)?;
            let repo_name =
                read_install_metadata("repo-name").unwrap_or_else(|| "nixos-config".to_string());
            return Ok(Some(Self {
                source: InstallSource::EmbeddedRepo {
                    repo_dir: repo_dir.to_path_buf(),
                    repo_name,
                    targets,
                },
                config_dir: repo_dir.to_path_buf(),
                flake_host: String::new(),
                hostname: String::new(),
                username: read_install_metadata("admin-username"),
                repo_owner: read_install_metadata("repo-owner")
                    .or_else(|| read_install_metadata("admin-username")),
                github_username: None,
                storage_type: None,
                disk_device: None,
                hardware_path: None,
            }));
        }

        let config_dir = Path::new(INSTALL_CONFIG_PATH);
        if !config_dir.exists() {
            return Ok(None);
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

        Ok(Some(Self {
            source: InstallSource::PrebakedConfig,
            config_dir: effective_dir,
            flake_host: hostname.clone(),
            hostname,
            repo_owner: username.clone(),
            username,
            github_username,
            storage_type,
            disk_device,
            hardware_path: None,
        }))
    }

    /// Recursively copy config files to a writable tmpdir for disk injection.
    fn copy_to_writable(src: &Path, dst: &Path) -> std::io::Result<()> {
        if dst.exists() {
            std::fs::remove_dir_all(dst)?;
        }
        Self::copy_dir_recursive(src, dst)
    }

    /// Recursively copy a directory tree.
    fn copy_dir_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
        std::fs::create_dir_all(dst)?;
        for entry in std::fs::read_dir(src)? {
            let entry = entry?;
            let src_path = entry.path();
            let dst_path = dst.join(entry.file_name());
            if src_path.is_dir() {
                Self::copy_dir_recursive(&src_path, &dst_path)?;
            } else {
                std::fs::copy(&src_path, &dst_path)?;
            }
        }
        Ok(())
    }

    /// Find the per-host hardware.nix or configuration.nix path.
    ///
    /// With the mkSystemFlake layout, files live at `hosts/<hostname>/hardware.nix`.
    /// Falls back to flat layout for backward compatibility.
    fn find_host_file(config_dir: &Path, hostname: &str, filename: &str) -> Option<PathBuf> {
        // Try hosts/<hostname>/<filename> first (mkSystemFlake layout)
        let host_path = config_dir.join("hosts").join(hostname).join(filename);
        if host_path.exists() {
            return Some(host_path);
        }
        // Fall back to flat layout
        let flat_path = config_dir.join(filename);
        if flat_path.exists() {
            return Some(flat_path);
        }
        None
    }

    /// Extract storage type and disk device from hardware.nix or configuration.nix
    /// via rnix AST. Tries the mkSystemFlake hosts/ layout first.
    fn parse_configuration_nix(config_dir: &Path) -> Option<(Option<String>, Option<String>)> {
        // Read hostname to find host-specific files
        let hostname = std::fs::read_to_string(config_dir.join("hostname"))
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_default();

        // With mkSystemFlake, storage config lives in hardware.nix.
        // Try hardware.nix first, then configuration.nix for backward compat.
        let files_to_try: Vec<PathBuf> = if hostname.is_empty() {
            vec![
                config_dir.join("hardware.nix"),
                config_dir.join("configuration.nix"),
            ]
        } else {
            vec![
                config_dir
                    .join("hosts")
                    .join(&hostname)
                    .join("hardware.nix"),
                config_dir
                    .join("hosts")
                    .join(&hostname)
                    .join("configuration.nix"),
                config_dir.join("hardware.nix"),
                config_dir.join("configuration.nix"),
            ]
        };

        let content = files_to_try
            .iter()
            .find_map(|p| std::fs::read_to_string(p).ok())?;

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

    /// Replace the disk placeholder in hardware.nix (or configuration.nix for legacy layout).
    fn inject_disk_device(config_dir: &Path, device: &str) -> std::io::Result<()> {
        // With mkSystemFlake layout, disk device is in hardware.nix.
        // Try all candidate files and replace the placeholder wherever found.
        let hostname = std::fs::read_to_string(config_dir.join("hostname"))
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_default();

        let mut candidates: Vec<PathBuf> = Vec::new();
        if !hostname.is_empty() {
            candidates.push(
                config_dir
                    .join("hosts")
                    .join(&hostname)
                    .join("hardware.nix"),
            );
            candidates.push(
                config_dir
                    .join("hosts")
                    .join(&hostname)
                    .join("configuration.nix"),
            );
        }
        candidates.push(config_dir.join("hardware.nix"));
        candidates.push(config_dir.join("configuration.nix"));

        for path in &candidates {
            if let Ok(content) = std::fs::read_to_string(path) {
                if content.contains("__KEYSTONE_DISK__") {
                    let updated = content.replace("__KEYSTONE_DISK__", device);
                    std::fs::write(path, updated)?;
                    return Ok(());
                }
            }
        }

        Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "No file containing __KEYSTONE_DISK__ placeholder found",
        ))
    }

    fn inject_disk_into_hardware(hardware_path: &Path, device: &str) -> std::io::Result<()> {
        let content = std::fs::read_to_string(hardware_path)?;
        let mut updated = Vec::new();
        let mut in_devices = false;
        let mut replaced = false;
        let mut indent = String::new();

        for line in content.lines() {
            if !in_devices && line.contains("keystone.os.storage.devices") && line.contains('[') {
                indent = line
                    .chars()
                    .take_while(|c| c.is_whitespace())
                    .collect::<String>();
                updated.push(format!("{indent}keystone.os.storage.devices = ["));
                updated.push(format!("{indent}  \"{device}\""));
                if line.contains("];") {
                    updated.push(format!("{indent}];"));
                } else {
                    in_devices = true;
                }
                replaced = true;
                continue;
            }

            if in_devices {
                if line.contains("];") {
                    updated.push(format!("{indent}];"));
                    in_devices = false;
                }
                continue;
            }

            updated.push(line.to_string());
        }

        if !replaced {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!(
                    "Could not find keystone.os.storage.devices in {}",
                    hardware_path.display()
                ),
            ));
        }

        std::fs::write(hardware_path, format!("{}\n", updated.join("\n")))?;
        Ok(())
    }

    fn inject_selected_disk(&self, device: &str) -> std::io::Result<()> {
        if let Some(hardware_path) = self.hardware_path.as_ref() {
            Self::inject_disk_into_hardware(hardware_path, device)
        } else {
            Self::inject_disk_device(&self.config_dir, device)
        }
    }

    fn installed_repo_name(&self) -> &str {
        match &self.source {
            InstallSource::EmbeddedRepo { repo_name, .. } => repo_name.as_str(),
            InstallSource::PrebakedConfig => "keystone-config",
        }
    }

    fn installed_repo_owner(&self) -> &str {
        self.repo_owner
            .as_deref()
            .or(self.username.as_deref())
            .unwrap_or("keystone")
    }
}

fn read_install_metadata(name: &str) -> Option<String> {
    std::fs::read_to_string(Path::new(INSTALL_METADATA_DIR).join(name))
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn load_install_targets(repo_dir: &Path) -> AnyhowResult<Vec<InstallTarget>> {
    let targets_path = Path::new(INSTALL_METADATA_DIR).join("targets.json");
    let targets_json = std::fs::read_to_string(&targets_path).with_context(|| {
        format!(
            "Failed to read installer target metadata at {} for repo {}",
            targets_path.display(),
            repo_dir.display()
        )
    })?;

    let targets: BTreeMap<String, InstallTargetJson> = serde_json::from_str(&targets_json)
        .context("Failed to parse installer target metadata JSON")?;

    let mut parsed: Vec<InstallTarget> = targets
        .into_iter()
        .map(|(flake_host, target)| InstallTarget {
            flake_host,
            hostname: target.hostname,
            system: target.system,
            storage_type: target.storage_type,
            hardware_path: target.hardware_path,
        })
        .collect();
    parsed.sort_by(|left, right| left.flake_host.cmp(&right.flake_host));
    Ok(parsed)
}

fn copy_repo_to_writable(src: &Path, dst: &Path) -> AnyhowResult<()> {
    if dst.exists() {
        std::fs::remove_dir_all(dst)
            .with_context(|| format!("Failed to remove {}", dst.display()))?;
    }

    std::fs::create_dir_all(dst).with_context(|| format!("Failed to create {}", dst.display()))?;

    let status = StdCommand::new("cp")
        .args([
            "-a",
            &format!("{}/.", src.display()),
            &dst.display().to_string(),
        ])
        .status()
        .with_context(|| {
            format!(
                "Failed to copy repo from {} to {}",
                src.display(),
                dst.display()
            )
        })?;

    if !status.success() {
        anyhow::bail!(
            "cp -a failed while copying installer repo to {}",
            dst.display()
        );
    }

    // The embedded repo comes from a read-only store-style snapshot. After
    // copying it into /tmp or the installed system, the installer needs to
    // mutate files like flake.lock and hardware.nix, so add owner write bits
    // recursively while preserving the rest of the copied metadata.
    let chmod_status = StdCommand::new("chmod")
        .args(["-R", "u+w", &dst.display().to_string()])
        .status()
        .with_context(|| format!("Failed to make copied repo writable at {}", dst.display()))?;

    if !chmod_status.success() {
        anyhow::bail!(
            "chmod -R u+w failed while preparing writable repo at {}",
            dst.display()
        );
    }

    Ok(())
}

fn rewrite_keystone_lock_input(repo_dir: &Path, keystone_input_dir: &Path) -> AnyhowResult<()> {
    let status = StdCommand::new("nix")
        .args([
            "--extra-experimental-features",
            "nix-command flakes",
            "flake",
            "lock",
            "--override-input",
            "keystone",
            &format!("path:{}", keystone_input_dir.display()),
        ])
        .current_dir(repo_dir)
        .status()
        .with_context(|| {
            format!(
                "Failed to rewrite keystone flake input in {}",
                repo_dir.display()
            )
        })?;

    if !status.success() {
        anyhow::bail!(
            "nix flake lock --override-input keystone failed in {}",
            repo_dir.display()
        );
    }

    Ok(())
}

fn vendor_embedded_keystone_input(repo_dir: &Path) -> AnyhowResult<Option<PathBuf>> {
    let embedded_keystone = Path::new(INSTALL_KEYSTONE_PATH);
    if !embedded_keystone.exists() {
        return Ok(None);
    }

    let vendored_dir = PathBuf::from(WRITABLE_INSTALL_KEYSTONE_PATH);
    copy_repo_to_writable(embedded_keystone, &vendored_dir).with_context(|| {
        format!(
            "Failed to copy embedded keystone input from {} to {}",
            embedded_keystone.display(),
            vendored_dir.display()
        )
    })?;

    rewrite_keystone_lock_input(repo_dir, &vendored_dir)?;
    Ok(Some(vendored_dir))
}

fn parse_hardware_disk_device(hardware_path: &Path) -> Option<String> {
    let content = std::fs::read_to_string(hardware_path).ok()?;
    let mut in_devices = false;

    for line in content.lines() {
        if !in_devices && line.contains("keystone.os.storage.devices") && line.contains('[') {
            in_devices = true;
        }

        if in_devices {
            if line.contains("];") {
                break;
            }

            if line.contains("/dev/disk/by-id/") {
                let start = line.find('"')? + 1;
                let end = line[start..].find('"')? + start;
                return Some(line[start..end].to_string());
            }
        }
    }

    None
}

/// The phases of the install flow.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallPhase {
    /// Select the target host from the embedded repo.
    HostSelection,
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

#[derive(Debug, Clone, PartialEq, Eq)]
struct CommandSpec {
    program: String,
    args: Vec<String>,
}

pub struct InstallScreen {
    config: InstallerConfig,
    phase: InstallPhase,
    available_hosts: Vec<InstallTarget>,
    selected_host_index: usize,
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
        let (phase, available_hosts) = match &config.source {
            InstallSource::EmbeddedRepo { targets, .. } if targets.is_empty() => (
                InstallPhase::Failed(
                    "No installable Linux hosts were found in /etc/keystone/install-repo."
                        .to_string(),
                ),
                Vec::new(),
            ),
            InstallSource::EmbeddedRepo { targets, .. } => {
                (InstallPhase::HostSelection, targets.clone())
            }
            InstallSource::PrebakedConfig => (InstallPhase::Summary, Vec::new()),
        };

        Self {
            config,
            phase,
            available_hosts,
            selected_host_index: 0,
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
        let (phase, available_hosts) = match &config.source {
            InstallSource::EmbeddedRepo { targets, .. } if targets.is_empty() => (
                InstallPhase::Failed(
                    "No installable Linux hosts were found in /etc/keystone/install-repo."
                        .to_string(),
                ),
                Vec::new(),
            ),
            InstallSource::EmbeddedRepo { targets, .. } => {
                (InstallPhase::HostSelection, targets.clone())
            }
            InstallSource::PrebakedConfig => (InstallPhase::Summary, Vec::new()),
        };

        Self {
            config,
            phase,
            available_hosts,
            selected_host_index: 0,
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

    pub fn available_hosts(&self) -> &[InstallTarget] {
        &self.available_hosts
    }

    pub fn selected_host_index(&self) -> usize {
        self.selected_host_index
    }

    pub fn available_disks(&self) -> &[DiskEntry] {
        &self.available_disks
    }

    pub fn selected_disk_index(&self) -> usize {
        self.selected_disk_index
    }

    pub fn host_up(&mut self) {
        if !self.available_hosts.is_empty() {
            self.selected_host_index = if self.selected_host_index == 0 {
                self.available_hosts.len() - 1
            } else {
                self.selected_host_index - 1
            };
        }
    }

    pub fn host_down(&mut self) {
        if !self.available_hosts.is_empty() {
            self.selected_host_index = (self.selected_host_index + 1) % self.available_hosts.len();
        }
    }

    pub fn select_host(&mut self) {
        if self.phase != InstallPhase::HostSelection || self.available_hosts.is_empty() {
            return;
        }

        let selected = self.available_hosts[self.selected_host_index].clone();
        let repo_dir = match &self.config.source {
            InstallSource::EmbeddedRepo { repo_dir, .. } => repo_dir.clone(),
            InstallSource::PrebakedConfig => {
                self.phase = InstallPhase::Failed(
                    "Host selection is not available for legacy embedded install-config bundles."
                        .to_string(),
                );
                return;
            }
        };

        let writable_repo = PathBuf::from(WRITABLE_INSTALL_REPO_PATH);
        if let Err(error) = copy_repo_to_writable(&repo_dir, &writable_repo) {
            self.phase = InstallPhase::Failed(format!("Failed to prepare installer repo: {error}"));
            return;
        }
        if let Err(error) = vendor_embedded_keystone_input(&writable_repo) {
            self.phase =
                InstallPhase::Failed(format!("Failed to vendor embedded keystone input: {error}"));
            return;
        }

        let hardware_path = writable_repo.join(&selected.hardware_path);
        let disk_device = parse_hardware_disk_device(&hardware_path)
            .filter(|path| path.contains("/dev/disk/by-id/") && !path.contains("YOUR-"));

        self.config.config_dir = writable_repo;
        self.config.flake_host = selected.flake_host;
        self.config.hostname = selected.hostname;
        self.config.storage_type = selected.storage_type;
        self.config.disk_device = disk_device;
        self.config.hardware_path = Some(hardware_path);
        self.phase = InstallPhase::Summary;
    }

    /// Move from Summary → DiskSelection.
    ///
    /// Disk selection is always explicit, even when a disk was pre-configured
    /// in the embedded config, so the operator must actively confirm target
    /// media before destructive disk operations.
    pub fn proceed_to_confirm(&mut self) {
        if self.phase != InstallPhase::Summary {
            return;
        }

        self.phase = InstallPhase::DiskSelection;
        self.discovering_disks = true;
        self.spawn_disk_discovery();
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
        if let Err(e) = self.config.inject_selected_disk(&device_path) {
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
        let flake_host = self.config.flake_host.clone();
        let username = self.config.username.clone();
        let repo_owner = self.config.installed_repo_owner().to_string();
        let repo_name = self.config.installed_repo_name().to_string();

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
                    &format!("{}#{}", config_dir.display(), flake_host),
                ],
                &config_dir,
                &tx,
                &cancel_token,
                true,
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

            let flake_ref = format!("{}#{}", config_dir.display(), flake_host);

            let install_result = run_command(
                "nixos-install",
                &["--flake", &flake_ref, "--no-root-password"],
                &config_dir,
                &tx,
                &cancel_token,
                true,
            )
            .await;

            match install_result {
                Ok(()) => {
                    // Copy config to the installed system for first-boot flow
                    if let Some(ref user) = username {
                        let _ = tx.send(InstallMessage::Output(
                            "Copying config to installed system...".to_string(),
                        ));
                        if let Err(e) =
                            copy_config_to_target(&config_dir, user, &repo_owner, &repo_name, &tx)
                                .await
                        {
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

    /// Go back from Confirm → DiskSelection, or DiskSelection → Summary.
    pub fn go_back(&mut self) {
        match self.phase {
            InstallPhase::Confirm => {
                self.phase = InstallPhase::DiskSelection;
            }
            InstallPhase::DiskSelection => {
                self.phase = InstallPhase::Summary;
            }
            InstallPhase::Summary => {
                if matches!(&self.config.source, InstallSource::EmbeddedRepo { .. }) {
                    self.phase = InstallPhase::HostSelection;
                }
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
                    if let Some(preconfigured_disk) = self.config.disk_device.as_deref() {
                        if let Some((index, _)) = self
                            .available_disks
                            .iter()
                            .enumerate()
                            .find(|(_, disk)| disk.by_id_path == preconfigured_disk)
                        {
                            self.selected_disk_index = index;
                        }
                    }
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
            InstallPhase::HostSelection => self.render_host_selection(frame, area),
            InstallPhase::Summary => self.render_summary(frame, area),
            InstallPhase::DiskSelection => self.render_disk_selection(frame, area),
            InstallPhase::Confirm => self.render_confirm(frame, area),
            InstallPhase::Installing => self.render_installing(frame, area),
            InstallPhase::Done => self.render_done(frame, area),
            InstallPhase::Failed(err) => self.render_failed(frame, area, err),
        }
    }

    fn render_host_selection(&self, frame: &mut Frame, area: Rect) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(8),    // Host list
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled(
            "Select Installation Host",
            Style::default().bold().fg(Color::Green),
        ))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        let items: Vec<ListItem> = self
            .available_hosts
            .iter()
            .enumerate()
            .map(|(index, host)| {
                let indicator = if index == self.selected_host_index {
                    "▸ "
                } else {
                    "  "
                };
                let style = if index == self.selected_host_index {
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default()
                };
                let metadata = match (&host.system, &host.storage_type) {
                    (Some(system), Some(storage_type)) => format!("{system}  [{storage_type}]"),
                    (Some(system), None) => system.clone(),
                    (None, Some(storage_type)) => format!("[{storage_type}]"),
                    (None, None) => String::new(),
                };
                let details = format!("hostname={}  {}", host.hostname, metadata)
                    .trim_end()
                    .to_string();

                ListItem::new(Line::from(vec![
                    Span::styled(indicator, style),
                    Span::styled(&host.flake_host, style),
                    Span::styled(
                        format!("  {}", details),
                        Style::default().fg(Color::DarkGray),
                    ),
                ]))
            })
            .collect();

        let host_list = List::new(items).block(
            Block::default()
                .title(" Embedded installer targets ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green)),
        );
        frame.render_widget(host_list, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "↑/↓: navigate • Enter: select host • q: quit",
            Style::default().fg(Color::DarkGray),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_summary(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(8),    // Config summary
                Constraint::Length(3), // Help
            ])
            .split(area);

        // Title
        let title = Paragraph::new(Text::styled("Keystone Installer", t.active_style()))
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
        let source_label = match &self.config.source {
            InstallSource::EmbeddedRepo { .. } => "  Repo:      ",
            InstallSource::PrebakedConfig => "  Config:    ",
        };

        let items = vec![
            ListItem::new(Line::from(vec![
                Span::styled("  Host:      ", t.inactive_style()),
                Span::styled(
                    &self.config.flake_host,
                    Style::default().add_modifier(Modifier::BOLD),
                ),
            ])),
            ListItem::new(Line::from(vec![
                Span::styled("  Hostname:  ", t.inactive_style()),
                Span::styled(
                    &self.config.hostname,
                    Style::default().add_modifier(Modifier::BOLD),
                ),
            ])),
            ListItem::new(Line::from(vec![
                Span::styled("  Storage:   ", t.inactive_style()),
                Span::styled(storage, Style::default().add_modifier(Modifier::BOLD)),
            ])),
            ListItem::new(Line::from(vec![
                Span::styled("  Disk:      ", t.inactive_style()),
                Span::styled(disk, Style::default().add_modifier(Modifier::BOLD)),
            ])),
            ListItem::new(Line::from("")),
            ListItem::new(Line::from(vec![
                Span::styled(source_label, t.inactive_style()),
                Span::styled(
                    self.config.config_dir.display().to_string(),
                    t.inactive_style(),
                ),
            ])),
        ];

        let summary = List::new(items).block(
            Block::default()
                .title(" Configuration Summary ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.active)),
        );
        frame.render_widget(summary, chunks[1]);

        // Help
        let help = Paragraph::new(Text::styled(
            "Enter: proceed to install • Esc: back • q: quit",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_disk_selection(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),    // Disk list
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("Select Installation Disk", t.title_style()))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::BOTTOM));
        frame.render_widget(title, chunks[0]);

        if self.discovering_disks {
            let loading =
                Paragraph::new(Text::styled("\n  Discovering disks...", t.inactive_style())).block(
                    Block::default()
                        .borders(Borders::ALL)
                        .border_style(Style::default().fg(t.accent)),
                );
            frame.render_widget(loading, chunks[1]);
        } else if self.available_disks.is_empty() {
            let no_disks = Paragraph::new(Text::styled(
                "\n  No disks found. Ensure drives are connected and detected by the kernel.",
                t.error_style(),
            ))
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(t.error)),
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
                        Style::default().fg(t.accent).add_modifier(Modifier::BOLD)
                    } else {
                        Style::default()
                    };
                    ListItem::new(Line::from(vec![
                        Span::styled(indicator, style),
                        Span::styled(&disk.model, style),
                        Span::styled(
                            format!("  {}  [{}]", disk.size, disk.transport),
                            t.inactive_style(),
                        ),
                    ]))
                })
                .collect();

            let disk_list = List::new(items).block(
                Block::default()
                    .title(" Available Disks ")
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(t.accent)),
            );
            frame.render_widget(disk_list, chunks[1]);
        }

        let help = Paragraph::new(Text::styled(
            "↑/���: navigate • Enter: select disk • Esc: back",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_confirm(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(5),    // Warning
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("Confirm Installation", t.title_style()))
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
            t.error_style().add_modifier(Modifier::BOLD),
        ))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.error)),
        );
        frame.render_widget(warning, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "Enter: confirm and install • Esc: go back",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_installing(&self, frame: &mut Frame, area: Rect) {
        let t = crate::theme::default();
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
            t.title_style(),
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
                    .border_style(t.inactive_style()),
            )
            .wrap(Wrap { trim: false })
            .scroll((scroll, 0));
        frame.render_widget(output, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "↑/↓: scroll • Esc: cancel",
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
                Constraint::Length(3), // Title
                Constraint::Min(5),    // Message
                Constraint::Length(3), // Help
            ])
            .split(area);

        let title = Paragraph::new(Text::styled("Installation Complete", t.active_style()))
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
            Style::default().fg(t.active),
        ))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(t.active)),
        );
        frame.render_widget(message, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "r: reboot • q: quit to shell",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }

    fn render_failed(&self, frame: &mut Frame, area: Rect, error: &str) {
        let t = crate::theme::default();
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
            t.error_style().add_modifier(Modifier::BOLD),
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
                    .border_style(Style::default().fg(t.error)),
            )
            .wrap(Wrap { trim: false })
            .scroll((scroll, 0));
        frame.render_widget(output, chunks[1]);

        let help = Paragraph::new(Text::styled(
            "↑/↓: scroll • q: quit to shell",
            t.inactive_style(),
        ))
        .alignment(Alignment::Center);
        frame.render_widget(help, chunks[2]);
    }
}

/// Recursively copy a directory tree using async I/O.
async fn copy_dir_recursive_async(src: &Path, dst: &Path) -> Result<(), String> {
    let mut entries = tokio::fs::read_dir(src)
        .await
        .map_err(|e| format!("Failed to read dir {}: {}", src.display(), e))?;

    while let Some(entry) = entries
        .next_entry()
        .await
        .map_err(|e| format!("Failed to read entry: {}", e))?
    {
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());

        if src_path.is_dir() {
            tokio::fs::create_dir_all(&dst_path)
                .await
                .map_err(|e| format!("Failed to create dir {}: {}", dst_path.display(), e))?;
            Box::pin(copy_dir_recursive_async(&src_path, &dst_path)).await?;
        } else {
            // Skip non-nix files that are not the marker files (hostname, username, etc.)
            tokio::fs::copy(&src_path, &dst_path).await.map_err(|e| {
                format!(
                    "Failed to copy {} -> {}: {}",
                    src_path.display(),
                    dst_path.display(),
                    e
                )
            })?;
        }
    }

    Ok(())
}

/// Copy the generated config to the installed system for the first-boot flow.
///
/// Creates the installed system flake directory on the target and copies
/// the config tree with a `.first-boot-pending` marker so the TUI knows
/// to run the first-boot wizard on next login.
async fn copy_config_to_target(
    config_dir: &Path,
    username: &str,
    repo_owner: &str,
    repo_name: &str,
    tx: &mpsc::UnboundedSender<InstallMessage>,
) -> Result<(), String> {
    let target_home = PathBuf::from(format!("/mnt/home/{}", username));
    let repo_dir = target_home
        .join(".keystone")
        .join("repos")
        .join(repo_owner)
        .join(repo_name);

    tokio::fs::create_dir_all(&repo_dir)
        .await
        .map_err(|e| format!("Failed to create config dir: {}", e))?;

    // Copy entire config directory tree (handles both flat and hosts/ layouts)
    copy_dir_recursive_async(config_dir, &repo_dir)
        .await
        .map_err(|e| format!("Failed to copy config files: {}", e))?;

    let embedded_keystone = Path::new(INSTALL_KEYSTONE_PATH);
    if embedded_keystone.exists() {
        let vendored_keystone = repo_dir.join(VENDORED_KEYSTONE_INPUT_DIR);
        copy_repo_to_writable(embedded_keystone, &vendored_keystone).map_err(|e| {
            format!(
                "Failed to copy embedded keystone input to installed repo {}: {}",
                repo_dir.display(),
                e
            )
        })?;
        rewrite_keystone_lock_input(&repo_dir, &vendored_keystone).map_err(|e| {
            format!(
                "Failed to rewrite keystone input in installed repo {}: {}",
                repo_dir.display(),
                e
            )
        })?;
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
    privileged: bool,
) -> Result<(), String> {
    let command = build_command_spec(program, args, privileged);
    let cmd_display = format!("$ {} {}", command.program, command.args.join(" "));
    let _ = tx.send(InstallMessage::Output(cmd_display));

    let child_result = Command::new(&command.program)
        .args(&command.args)
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

fn build_command_spec(program: &str, args: &[&str], privileged: bool) -> CommandSpec {
    if privileged {
        let mut command_args = Vec::with_capacity(args.len() + 2);
        command_args.push("-n".to_string());
        command_args.push(program.to_string());
        command_args.extend(args.iter().map(|arg| (*arg).to_string()));
        return CommandSpec {
            program: "sudo".to_string(),
            args: command_args,
        };
    }

    CommandSpec {
        program: program.to_string(),
        args: args.iter().map(|arg| (*arg).to_string()).collect(),
    }
}

impl Component for InstallScreen {
    fn handle_events(&mut self, event: &Event) -> anyhow::Result<Option<Action>> {
        if let Event::Key(key) = event {
            if key.kind != KeyEventKind::Press {
                return Ok(None);
            }
            return Ok(self.handle_key_event(key.code));
        }
        Ok(None)
    }

    fn draw(&mut self, frame: &mut Frame, area: Rect) -> anyhow::Result<()> {
        self.render(frame, area);
        Ok(())
    }
}

impl InstallScreen {
    /// Handle a key press, returning an optional global Action.
    fn handle_key_event(&mut self, code: KeyCode) -> Option<Action> {
        match self.phase() {
            InstallPhase::HostSelection => match code {
                KeyCode::Up | KeyCode::Char('k') => {
                    self.host_up();
                    None
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    self.host_down();
                    None
                }
                KeyCode::Enter => {
                    self.select_host();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            InstallPhase::Summary => match code {
                KeyCode::Enter => {
                    self.proceed_to_confirm();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            InstallPhase::DiskSelection => match code {
                KeyCode::Up | KeyCode::Char('k') => {
                    self.disk_up();
                    None
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    self.disk_down();
                    None
                }
                KeyCode::Enter => {
                    self.select_disk();
                    None
                }
                KeyCode::Esc => {
                    self.go_back();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            InstallPhase::Confirm => match code {
                KeyCode::Enter => {
                    self.start_install();
                    None
                }
                KeyCode::Esc => {
                    self.go_back();
                    None
                }
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            InstallPhase::Installing => match code {
                KeyCode::Esc => {
                    self.cancel();
                    None
                }
                KeyCode::Up | KeyCode::Char('k') => {
                    self.scroll_up();
                    None
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    self.scroll_down();
                    None
                }
                _ => None,
            },
            InstallPhase::Done => match code {
                KeyCode::Char('r') => Some(Action::Reboot),
                KeyCode::Char('q') => Some(Action::Quit),
                _ => None,
            },
            InstallPhase::Failed(_) => match code {
                KeyCode::Char('q') => Some(Action::Quit),
                KeyCode::Up | KeyCode::Char('k') => {
                    self.scroll_up();
                    None
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    self.scroll_down();
                    None
                }
                _ => None,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config() -> InstallerConfig {
        InstallerConfig {
            source: InstallSource::PrebakedConfig,
            config_dir: PathBuf::from("/etc/keystone/install-config"),
            flake_host: "test-laptop".to_string(),
            hostname: "test-laptop".to_string(),
            username: Some("testuser".to_string()),
            repo_owner: Some("testuser".to_string()),
            github_username: None,
            storage_type: Some("ext4".to_string()),
            disk_device: Some("/dev/disk/by-id/nvme-TEST".to_string()),
            hardware_path: None,
        }
    }

    fn test_config_no_disk() -> InstallerConfig {
        InstallerConfig {
            source: InstallSource::PrebakedConfig,
            config_dir: PathBuf::from("/tmp/keystone-test-config"),
            flake_host: "test-laptop".to_string(),
            hostname: "test-laptop".to_string(),
            username: Some("testuser".to_string()),
            repo_owner: Some("testuser".to_string()),
            github_username: None,
            storage_type: Some("ext4".to_string()),
            disk_device: None,
            hardware_path: None,
        }
    }

    fn test_embedded_repo_config() -> InstallerConfig {
        InstallerConfig {
            source: InstallSource::EmbeddedRepo {
                repo_dir: PathBuf::from("/etc/keystone/install-repo"),
                repo_name: "keystone-config".to_string(),
                targets: vec![
                    InstallTarget {
                        flake_host: "laptop".to_string(),
                        hostname: "keystone".to_string(),
                        system: Some("x86_64-linux".to_string()),
                        storage_type: Some("ext4".to_string()),
                        hardware_path: "hosts/laptop/hardware.nix".to_string(),
                    },
                    InstallTarget {
                        flake_host: "server-ocean".to_string(),
                        hostname: "server-ocean".to_string(),
                        system: Some("x86_64-linux".to_string()),
                        storage_type: Some("zfs".to_string()),
                        hardware_path: "hosts/server-ocean/hardware.nix".to_string(),
                    },
                ],
            },
            config_dir: PathBuf::from("/etc/keystone/install-repo"),
            flake_host: String::new(),
            hostname: String::new(),
            username: Some("noah".to_string()),
            repo_owner: Some("noah".to_string()),
            github_username: None,
            storage_type: None,
            disk_device: None,
            hardware_path: None,
        }
    }

    #[test]
    fn test_initial_phase_is_summary() {
        let screen = InstallScreen::new(test_config());
        assert_eq!(*screen.phase(), InstallPhase::Summary);
    }

    #[test]
    fn test_embedded_repo_initial_phase_is_host_selection() {
        let screen = InstallScreen::new(test_embedded_repo_config());
        assert_eq!(*screen.phase(), InstallPhase::HostSelection);
        assert_eq!(screen.available_hosts().len(), 2);
    }

    #[test]
    fn test_host_navigation() {
        let mut screen = InstallScreen::new(test_embedded_repo_config());
        assert_eq!(screen.selected_host_index(), 0);

        screen.host_down();
        assert_eq!(screen.selected_host_index(), 1);

        screen.host_down();
        assert_eq!(screen.selected_host_index(), 0);

        screen.host_up();
        assert_eq!(screen.selected_host_index(), 1);
    }

    #[tokio::test]
    async fn test_proceed_to_disk_selection() {
        let mut screen = InstallScreen::new(test_config());
        screen.proceed_to_confirm();
        assert_eq!(*screen.phase(), InstallPhase::DiskSelection);
    }

    #[test]
    fn test_go_back_from_confirm() {
        let mut screen = InstallScreen::new(test_config());
        screen.phase = InstallPhase::Confirm;
        screen.go_back();
        assert_eq!(*screen.phase(), InstallPhase::DiskSelection);
    }

    #[test]
    fn test_go_back_from_summary_is_noop() {
        let mut screen = InstallScreen::new(test_config());
        screen.go_back();
        assert_eq!(*screen.phase(), InstallPhase::Summary);
    }

    #[test]
    fn test_go_back_from_summary_returns_to_host_selection_for_embedded_repo() {
        let mut screen = InstallScreen::new(test_embedded_repo_config());
        screen.phase = InstallPhase::Summary;
        screen.go_back();
        assert_eq!(*screen.phase(), InstallPhase::HostSelection);
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

    #[tokio::test]
    async fn test_proceed_with_disk_goes_to_confirm() {
        let mut screen = InstallScreen::new(test_config());
        screen.proceed_to_confirm();
        assert_eq!(*screen.phase(), InstallPhase::DiskSelection);
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

    #[test]
    fn test_poll_preselects_configured_disk() {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut screen = InstallScreen::new_with_channel(test_config(), rx);
        screen.phase = InstallPhase::DiskSelection;
        screen.discovering_disks = true;

        tx.send(InstallMessage::DisksDiscovered(vec![
            DiskEntry {
                by_id_path: "/dev/disk/by-id/ata-other".to_string(),
                model: "Other Disk".to_string(),
                size: "1T".to_string(),
                transport: "sata".to_string(),
            },
            DiskEntry {
                by_id_path: "/dev/disk/by-id/nvme-TEST".to_string(),
                model: "Preferred Disk".to_string(),
                size: "2T".to_string(),
                transport: "nvme".to_string(),
            },
        ]))
        .unwrap();

        screen.poll();
        assert_eq!(screen.selected_disk_index(), 1);
    }

    #[test]
    fn test_build_command_spec_wraps_privileged_commands_in_sudo() {
        let command = build_command_spec("disko", &["--mode", "disko"], true);

        assert_eq!(command.program, "sudo");
        assert_eq!(command.args, vec!["-n", "disko", "--mode", "disko"]);
    }

    #[test]
    fn test_build_command_spec_keeps_non_privileged_commands_direct() {
        let command = build_command_spec("disko", &["--mode", "disko"], false);

        assert_eq!(command.program, "disko");
        assert_eq!(command.args, vec!["--mode", "disko"]);
    }
}
