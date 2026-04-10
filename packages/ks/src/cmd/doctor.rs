//! `ks doctor` command — system and fleet health diagnostics.

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use serde::Serialize;

use super::{agent, util};
use crate::repo;

#[derive(Debug, Clone, Serialize)]
pub struct DiagnosticCheck {
    pub name: String,
    pub status: String,
    pub detail: String,
}

#[derive(Debug, Serialize)]
pub struct DoctorReport {
    pub hostname: String,
    pub nixos_generation: Option<String>,
    pub checks: Vec<DiagnosticCheck>,
    pub markdown: String,
}

#[derive(Debug, Clone, Copy)]
struct EphemeralPathCheck {
    relative_path: &'static str,
    threshold_bytes: u64,
    cleanup_suggestion: &'static str,
}

#[derive(Debug, Clone)]
struct HomeDiskPressureWarning {
    path: String,
    size_bytes: u64,
    suggestion: &'static str,
}

#[derive(Debug, Clone)]
struct ZfsPoolHealth {
    pool: String,
    available_bytes: u64,
    snapshot_overhead_bytes: u64,
    status: &'static str,
}

#[derive(Debug, Clone)]
struct ZfsDatasetInfo {
    name: String,
    used_bytes: u64,
    used_by_snapshots_bytes: u64,
    mountpoint: String,
}

#[derive(Debug, Clone)]
struct ZfsDatasetWarning {
    dataset: String,
    refer_bytes: u64,
    used_snapshots_bytes: u64,
    note: String,
}

#[derive(Debug, Clone)]
struct ZfsHealthReport {
    pools: Vec<ZfsPoolHealth>,
    dataset_warnings: Vec<ZfsDatasetWarning>,
}

const KIBIBYTE: u64 = 1024;
const MEBIBYTE: u64 = KIBIBYTE * 1024;
const GIBIBYTE: u64 = MEBIBYTE * 1024;

fn doctor_progress(message: &str) {
    if util::stderr_terminal() {
        eprintln!("ks doctor: {}", message);
    }
}

async fn collect_nixos_generation() -> Option<String> {
    let output = tokio::process::Command::new("nixos-version")
        .output()
        .await
        .ok()?;
    if output.status.success() {
        Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        None
    }
}

async fn collect_failed_units() -> Vec<String> {
    let output = tokio::process::Command::new("systemctl")
        .args(["--failed", "--plain", "--no-legend", "--no-pager"])
        .output()
        .await;

    match output {
        Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter_map(|line| {
                let trimmed = line.trim().trim_start_matches('●').trim();
                let unit = trimmed.split_whitespace().next()?;
                if unit.is_empty() {
                    None
                } else {
                    Some(unit.to_string())
                }
            })
            .collect(),
        _ => Vec::new(),
    }
}

async fn collect_disk_usage() -> String {
    let output = tokio::process::Command::new("df").arg("-h").output().await;
    match output {
        Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout)
            .lines()
            .take(20)
            .collect::<Vec<_>>()
            .join("\n"),
        _ => "unavailable".to_string(),
    }
}

fn format_bytes(bytes: u64) -> String {
    if bytes >= GIBIBYTE {
        format!("{}G", bytes / GIBIBYTE)
    } else if bytes >= MEBIBYTE {
        format!("{}M", bytes / MEBIBYTE)
    } else if bytes >= KIBIBYTE {
        format!("{}K", bytes / KIBIBYTE)
    } else {
        format!("{bytes}B")
    }
}

fn home_disk_checks() -> [EphemeralPathCheck; 9] {
    [
        EphemeralPathCheck {
            relative_path: ".cache",
            threshold_bytes: 10 * GIBIBYTE,
            cleanup_suggestion: "rm -rf ~/.cache/llama.cpp ~/.cache/huggingface ~/.cache/yarn",
        },
        EphemeralPathCheck {
            relative_path: ".local/share/containers",
            threshold_bytes: 20 * GIBIBYTE,
            cleanup_suggestion: "podman system prune -a --volumes",
        },
        EphemeralPathCheck {
            relative_path: ".local/share/docker",
            threshold_bytes: 20 * GIBIBYTE,
            cleanup_suggestion: "docker system prune -a --volumes",
        },
        EphemeralPathCheck {
            relative_path: ".local/share/Steam",
            threshold_bytes: 100 * GIBIBYTE,
            cleanup_suggestion: "Remove unused Steam libraries/games",
        },
        EphemeralPathCheck {
            relative_path: ".local/share/Trash",
            threshold_bytes: GIBIBYTE,
            cleanup_suggestion: "Empty trash",
        },
        EphemeralPathCheck {
            relative_path: ".npm",
            threshold_bytes: 2 * GIBIBYTE,
            cleanup_suggestion: "npm cache clean --force",
        },
        EphemeralPathCheck {
            relative_path: ".local/share/pnpm",
            threshold_bytes: 2 * GIBIBYTE,
            cleanup_suggestion: "pnpm store prune",
        },
        EphemeralPathCheck {
            relative_path: ".cache/yarn",
            threshold_bytes: 2 * GIBIBYTE,
            cleanup_suggestion: "yarn cache clean",
        },
        EphemeralPathCheck {
            relative_path: ".local/share/opencode",
            threshold_bytes: 5 * GIBIBYTE,
            cleanup_suggestion: "Remove stale OpenCode runs under ~/.local/share/opencode",
        },
    ]
}

fn resolve_home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .or_else(home::home_dir)
}

fn parse_du_size_bytes(stdout: &[u8]) -> Option<u64> {
    let output = String::from_utf8_lossy(stdout);
    let first_field = output
        .split_whitespace()
        .next()
        .filter(|value| !value.is_empty())?;
    first_field.parse::<u64>().ok()
}

async fn collect_home_disk_pressure() -> Vec<HomeDiskPressureWarning> {
    let Some(home_dir) = resolve_home_dir() else {
        return Vec::new();
    };

    let mut handles = Vec::new();
    for check in home_disk_checks() {
        let path = home_dir.join(check.relative_path);
        handles.push(tokio::spawn(async move {
            if !path.exists() {
                return None;
            }

            let result = tokio::time::timeout(
                Duration::from_secs(10),
                tokio::process::Command::new("du")
                    .args(["-sb"])
                    .arg(&path)
                    .output(),
            )
            .await
            .ok()?
            .ok()?;

            if !result.status.success() {
                return None;
            }

            let size_bytes = parse_du_size_bytes(&result.stdout)?;
            if size_bytes > check.threshold_bytes {
                Some(HomeDiskPressureWarning {
                    path: format!("~/{}", check.relative_path),
                    size_bytes,
                    suggestion: check.cleanup_suggestion,
                })
            } else {
                None
            }
        }));
    }

    let mut warnings = Vec::new();
    for handle in handles {
        if let Ok(Some(warning)) = handle.await {
            warnings.push(warning);
        }
    }
    warnings.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
    warnings
}

fn parse_zpool_avail(stdout: &[u8]) -> Vec<(String, u64)> {
    String::from_utf8_lossy(stdout)
        .lines()
        .filter_map(|line| {
            let mut parts = line.split('\t');
            let pool = parts.next()?.trim();
            let avail = parts.next()?.trim().parse::<u64>().ok()?;
            if pool.is_empty() {
                None
            } else {
                Some((pool.to_string(), avail))
            }
        })
        .collect()
}

fn parse_zfs_dataset_info(stdout: &[u8]) -> Vec<ZfsDatasetInfo> {
    String::from_utf8_lossy(stdout)
        .lines()
        .filter_map(|line| {
            let mut parts = line.split('\t');
            let name = parts.next()?.trim().to_string();
            let used_bytes = parts.next()?.trim().parse::<u64>().ok()?;
            let used_by_snapshots_bytes = parts.next()?.trim().parse::<u64>().ok()?;
            let mountpoint = parts.next()?.trim().to_string();
            if name.is_empty() {
                None
            } else {
                Some(ZfsDatasetInfo {
                    name,
                    used_bytes,
                    used_by_snapshots_bytes,
                    mountpoint,
                })
            }
        })
        .collect()
}

fn zfs_pool_status(avail_bytes: u64) -> &'static str {
    if avail_bytes < 10 * GIBIBYTE {
        "error"
    } else if avail_bytes < 50 * GIBIBYTE {
        "warning"
    } else {
        "ok"
    }
}

fn build_zfs_health_report(
    pools: Vec<(String, u64)>,
    datasets: Vec<ZfsDatasetInfo>,
    home_warnings: &[HomeDiskPressureWarning],
    home_dir: Option<&Path>,
) -> ZfsHealthReport {
    let mut snapshot_overhead_by_pool = std::collections::BTreeMap::<String, u64>::new();
    for dataset in &datasets {
        if let Some(pool) = dataset.name.split('/').next() {
            *snapshot_overhead_by_pool
                .entry(pool.to_string())
                .or_default() += dataset.used_by_snapshots_bytes;
        }
    }

    let pools = pools
        .into_iter()
        .map(|(pool, available_bytes)| ZfsPoolHealth {
            snapshot_overhead_bytes: snapshot_overhead_by_pool.get(&pool).copied().unwrap_or(0),
            status: zfs_pool_status(available_bytes),
            pool,
            available_bytes,
        })
        .collect::<Vec<_>>();

    let mut dataset_warnings = datasets
        .iter()
        .filter_map(|dataset| {
            if dataset.used_bytes == 0 {
                return None;
            }
            // Check if snapshots exceed 25% of dataset usage (used_by_snapshots * 4 > used).
            if dataset.used_by_snapshots_bytes.saturating_mul(4) > dataset.used_bytes {
                Some(ZfsDatasetWarning {
                    dataset: dataset.name.clone(),
                    refer_bytes: dataset.used_bytes,
                    used_snapshots_bytes: dataset.used_by_snapshots_bytes,
                    note: "Snapshot overhead above 25%".to_string(),
                })
            } else {
                None
            }
        })
        .collect::<Vec<_>>();

    if let Some(home_dir) = home_dir {
        for warning in home_warnings {
            let path = home_dir.join(warning.path.trim_start_matches("~/"));
            if let Some(dataset) = datasets
                .iter()
                .filter(|dataset| {
                    !dataset.mountpoint.is_empty()
                        && dataset.mountpoint != "-"
                        && dataset.mountpoint != "none"
                        && path.starts_with(&dataset.mountpoint)
                        && dataset.used_by_snapshots_bytes > 0
                })
                .max_by_key(|dataset| dataset.mountpoint.len())
            {
                dataset_warnings.push(ZfsDatasetWarning {
                    dataset: dataset.name.clone(),
                    refer_bytes: dataset.used_bytes,
                    used_snapshots_bytes: dataset.used_by_snapshots_bytes,
                    note: format!(
                        "Ephemeral dir {} is in snapshot surface; consider a no-snapshot child dataset",
                        warning.path
                    ),
                });
            }
        }
    }

    let mut seen = std::collections::HashSet::new();
    dataset_warnings.retain(|warning| seen.insert((warning.dataset.clone(), warning.note.clone())));
    dataset_warnings.sort_by(|a, b| b.used_snapshots_bytes.cmp(&a.used_snapshots_bytes));

    ZfsHealthReport {
        pools,
        dataset_warnings,
    }
}

async fn collect_zfs_health(home_warnings: &[HomeDiskPressureWarning]) -> Option<ZfsHealthReport> {
    let _ = util::find_executable("zfs")?;

    let pool_output = tokio::process::Command::new("zpool")
        .args(["list", "-H", "-p", "-o", "name,free"])
        .output()
        .await
        .ok()?;
    if !pool_output.status.success() {
        return None;
    }

    let pools = parse_zpool_avail(&pool_output.stdout);
    if pools.is_empty() {
        return None;
    }

    let dataset_output = tokio::process::Command::new("zfs")
        .args([
            "list",
            "-H",
            "-p",
            "-t",
            "filesystem,volume",
            "-o",
            "name,used,usedbysnapshots,mountpoint",
        ])
        .output()
        .await
        .ok()?;

    let datasets = if dataset_output.status.success() {
        parse_zfs_dataset_info(&dataset_output.stdout)
    } else {
        Vec::new()
    };

    let home_dir = resolve_home_dir();
    Some(build_zfs_health_report(
        pools,
        datasets,
        home_warnings,
        home_dir.as_deref(),
    ))
}

fn append_home_disk_pressure_section(
    markdown: &mut String,
    checks: &mut Vec<DiagnosticCheck>,
    home_pressure_warnings: &[HomeDiskPressureWarning],
) {
    markdown.push_str("### Disk pressure warnings\n");
    if home_pressure_warnings.is_empty() {
        markdown.push_str("_No high-usage ephemeral directories detected_\n\n");
        checks.push(DiagnosticCheck {
            name: "disk-pressure-home".to_string(),
            status: "ok".to_string(),
            detail: "No ephemeral directories above thresholds".to_string(),
        });
        return;
    }

    markdown.push_str("| Path | Size | Suggestion |\n");
    markdown.push_str("|---|---|---|\n");
    for warning in home_pressure_warnings {
        markdown.push_str(&format!(
            "| {} | {} | {} |\n",
            warning.path,
            format_bytes(warning.size_bytes),
            warning.suggestion
        ));
        checks.push(DiagnosticCheck {
            name: format!("disk-pressure:{}", warning.path),
            status: "warning".to_string(),
            detail: format!(
                "{} exceeds threshold ({})",
                warning.path,
                format_bytes(warning.size_bytes)
            ),
        });
    }
    markdown.push('\n');
}

fn append_zfs_health_section(
    markdown: &mut String,
    checks: &mut Vec<DiagnosticCheck>,
    zfs_health: &Option<ZfsHealthReport>,
) {
    let Some(zfs_health) = zfs_health else {
        return;
    };

    markdown.push_str("### ZFS pool health\n");
    markdown.push_str("| Pool | Available | Snapshot overhead | Status |\n");
    markdown.push_str("|---|---|---|---|\n");
    for pool in &zfs_health.pools {
        markdown.push_str(&format!(
            "| {} | {} | {} | {} |\n",
            pool.pool,
            format_bytes(pool.available_bytes),
            format_bytes(pool.snapshot_overhead_bytes),
            pool.status
        ));
        checks.push(DiagnosticCheck {
            name: format!("zfs-pool:{}", pool.pool),
            status: pool.status.to_string(),
            detail: format!(
                "Pool available {} (snapshot overhead {})",
                format_bytes(pool.available_bytes),
                format_bytes(pool.snapshot_overhead_bytes)
            ),
        });
    }
    markdown.push('\n');

    if zfs_health.dataset_warnings.is_empty() {
        return;
    }

    markdown.push_str("### Snapshot overhead by dataset\n");
    markdown.push_str("| Dataset | REFER | USEDSNAP | Note |\n");
    markdown.push_str("|---|---|---|---|\n");
    for warning in &zfs_health.dataset_warnings {
        markdown.push_str(&format!(
            "| {} | {} | {} | {} |\n",
            warning.dataset,
            format_bytes(warning.refer_bytes),
            format_bytes(warning.used_snapshots_bytes),
            warning.note
        ));
        checks.push(DiagnosticCheck {
            name: format!("zfs-dataset:{}", warning.dataset),
            status: "warning".to_string(),
            detail: format!(
                "{} ({} snapshot usage)",
                warning.note,
                format_bytes(warning.used_snapshots_bytes)
            ),
        });
    }
    markdown.push('\n');
}

fn append_summary_section(markdown: &mut String, checks: &[DiagnosticCheck]) {
    let warning_count = checks
        .iter()
        .filter(|check| check.status == "warning")
        .count();
    let error_count = checks
        .iter()
        .filter(|check| check.status == "error")
        .count();
    markdown.push_str("### Summary\n");
    markdown.push_str(&format!(
        "- warnings: **{}**\n- errors: **{}**\n\n",
        warning_count, error_count
    ));
}

async fn collect_flake_lock_age(repo_root: &Path) -> String {
    let lock_path = repo_root.join("flake.lock");
    if !lock_path.is_file() {
        return "flake.lock not found".to_string();
    }

    let output = tokio::process::Command::new("git")
        .args(["-C"])
        .arg(repo_root)
        .args(["log", "-1", "--format=%ar", "--", "flake.lock"])
        .output()
        .await;

    match output {
        Ok(output) if output.status.success() => {
            let age = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if age.is_empty() {
                "unknown".to_string()
            } else {
                format!("Last updated: {}", age)
            }
        }
        _ => "unknown".to_string(),
    }
}

fn known_agents_list() -> Result<Vec<String>> {
    let output = Command::new("agentctl")
        .output()
        .context("agentctl is not available in PATH")?;

    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let Some(line) = combined
        .lines()
        .find_map(|line| line.strip_prefix("Known agents: "))
    else {
        return Ok(Vec::new());
    };

    Ok(line
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .collect())
}

fn safe_agentctl_state(agent: &str, unit: &str) -> String {
    Command::new("agentctl")
        .arg(agent)
        .args(["is-active", unit])
        .output()
        .ok()
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "unknown".to_string())
}

fn count_status_matches(yaml: &str, status: &str) -> usize {
    yaml.lines()
        .filter(|line| line.trim() == format!("status: {}", status))
        .count()
}

async fn gather_ollama_diagnostics(repo_root: &Path, current_host: Option<&str>) -> String {
    let mut lines = vec!["### Ollama diagnostics".to_string()];
    let configured_host = if let Ok(host) = std::env::var("OLLAMA_HOST") {
        host
    } else if let Some(current_host) = current_host {
        match repo::resolve_current_hm_user(repo_root, current_host).await {
            Ok(Some(user)) => repo::resolve_ollama_host(repo_root, current_host, Some(&user))
                .await
                .unwrap_or_default(),
            _ => String::new(),
        }
    } else {
        String::new()
    };

    if configured_host.is_empty() {
        lines.push("- API endpoint: _not configured_".to_string());
        lines.push("- Available models:".to_string());
        lines.push("  - _API endpoint not configured_".to_string());
        return lines.join("\n");
    }

    lines.push(format!("- API endpoint: {}", configured_host));
    lines.push("- Available models:".to_string());

    let url = format!("{}/api/tags", configured_host.trim_end_matches('/'));
    match reqwest::get(&url).await {
        Ok(response) if response.status().is_success() => {
            match response.json::<serde_json::Value>().await {
                Ok(json) => {
                    let mut found = false;
                    if let Some(models) = json.get("models").and_then(serde_json::Value::as_array) {
                        for model in models.iter().filter_map(|model| {
                            model.get("name").and_then(serde_json::Value::as_str)
                        }) {
                            found = true;
                            lines.push(format!("  - {}", model));
                        }
                    }
                    if !found {
                        lines.push("  - _No models found_".to_string());
                    }
                }
                Err(_) => lines.push("  - _API response could not be parsed_".to_string()),
            }
        }
        _ => lines.push("  - _API unreachable_".to_string()),
    }

    lines.join("\n")
}

async fn ssh_probe(target: &str, timeout_seconds: &str) -> bool {
    tokio::process::Command::new("ssh")
        .args([
            "-o",
            &format!("ConnectTimeout={timeout_seconds}"),
            "-o",
            "BatchMode=yes",
        ])
        .arg(format!("root@{}", target))
        .arg("true")
        .status()
        .await
        .map(|status| status.success())
        .unwrap_or(false)
}

async fn remote_nixos_generation(target: &str) -> String {
    tokio::process::Command::new("ssh")
        .args(["-o", "ConnectTimeout=5", "-o", "BatchMode=yes"])
        .arg(format!("root@{}", target))
        .arg("nixos-version")
        .output()
        .await
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "unknown".to_string())
}

async fn fleet_status_row(
    repo_root: &Path,
    hosts_nix: &Path,
    current_hostname: &str,
    host: &str,
    local_gen: Option<&str>,
) -> Option<String> {
    let info = repo::host_info(hosts_nix, host).await.ok()?;

    if info.hostname == current_hostname {
        return Some(format!(
            "| {} | local | {} | ← current |",
            host,
            local_gen.unwrap_or("unknown")
        ));
    }

    let ssh_target = repo::resolve_ssh_target(repo_root, host, &info)
        .await
        .ok()??;
    let mut resolved = ssh_target.clone();
    let mut reachable = "no".to_string();

    if ssh_probe(&ssh_target, "3").await {
        reachable = "yes".to_string();
    } else if let Some(fallback_ip) = info
        .fallback_ip
        .as_deref()
        .filter(|value| !value.is_empty())
    {
        if ssh_probe(fallback_ip, "3").await {
            reachable = "yes (LAN)".to_string();
            resolved = fallback_ip.to_string();
        }
    }

    if reachable == "no" {
        return Some(format!("| {} | {} | — | unreachable |", host, reachable));
    }

    let remote_gen = remote_nixos_generation(&resolved).await;
    let status = if Some(remote_gen.as_str()) == local_gen {
        "ok"
    } else if remote_gen == "unknown" {
        "unknown"
    } else {
        "drift"
    };

    Some(format!(
        "| {} | {} | {} | {} |",
        host, reachable, remote_gen, status
    ))
}

async fn gather_fleet_health(repo_root: &Path, local_gen: Option<&str>) -> String {
    let hosts_nix = repo_root.join("hosts.nix");
    let output = tokio::process::Command::new("nix")
        .args(["eval", "-f"])
        .arg(&hosts_nix)
        .args(["--json", "--apply", "builtins.attrNames"])
        .output()
        .await;
    let Ok(output) = output else {
        return String::new();
    };
    if !output.status.success() {
        return String::new();
    }

    let hosts: Vec<String> = serde_json::from_slice(&output.stdout).unwrap_or_default();
    if hosts.is_empty() {
        return String::new();
    }

    let current_hostname = hostname::get()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let mut lines = vec![
        "### Fleet status".to_string(),
        "| Host | Reachable | NixOS Generation | Status |".to_string(),
        "|------|-----------|------------------|--------|".to_string(),
    ];

    for host in hosts {
        if let Some(row) =
            fleet_status_row(repo_root, &hosts_nix, &current_hostname, &host, local_gen).await
        {
            lines.push(row);
        } else {
            lines.push(format!("| {} | — | — | no sshTarget |", host));
        }
    }

    lines.join("\n")
}

fn gather_agent_health() -> String {
    let agents = known_agents_list().unwrap_or_default();
    if agents.is_empty() {
        return "### Agent status\n_No agents configured_".to_string();
    }

    let mut lines = vec![
        "### Agent status".to_string(),
        "| Agent | Task Loop | Notes Sync | SSH Agent | Status |".to_string(),
        "|-------|-----------|------------|-----------|--------|".to_string(),
    ];

    for agent in agents {
        let task_loop = safe_agentctl_state(&agent, &format!("agent-{}-task-loop.timer", agent));
        let notes_sync = safe_agentctl_state(&agent, &format!("agent-{}-notes-sync.timer", agent));
        let ssh_agent = safe_agentctl_state(&agent, &format!("agent-{}-ssh-agent.service", agent));
        let status = if task_loop == "active" && notes_sync == "active" && ssh_agent == "active" {
            "ok"
        } else if task_loop == "unknown" && notes_sync == "unknown" {
            "unreachable"
        } else {
            "degraded"
        };
        lines.push(format!(
            "| {} | {} | {} | {} | {} |",
            agent, task_loop, notes_sync, ssh_agent, status
        ));
    }

    lines.join("\n")
}

fn gather_agent_tasks() -> String {
    let agents = known_agents_list().unwrap_or_default();
    if agents.is_empty() {
        return String::new();
    }

    let mut lines = vec![
        "### Agent tasks".to_string(),
        "| Agent | Pending | In Progress | Blocked | Completed |".to_string(),
        "|-------|---------|-------------|---------|-----------|".to_string(),
    ];

    for agent in agents {
        let yaml = Command::new("agentctl")
            .arg(&agent)
            .args([
                "exec",
                "cat",
                &format!("/home/agent-{agent}/notes/TASKS.yaml"),
            ])
            .output()
            .ok()
            .filter(|output| output.status.success())
            .map(|output| String::from_utf8_lossy(&output.stdout).to_string())
            .unwrap_or_default();

        if yaml.is_empty() {
            lines.push(format!("| {} | — | — | — | — |", agent));
            continue;
        }

        lines.push(format!(
            "| {} | {} | {} | {} | {} |",
            agent,
            count_status_matches(&yaml, "pending"),
            count_status_matches(&yaml, "in_progress"),
            count_status_matches(&yaml, "blocked"),
            count_status_matches(&yaml, "completed")
        ));
    }

    lines.join("\n")
}

pub async fn gather_report(repo_root: &Path) -> Result<DoctorReport> {
    let hostname = hostname::get()
        .context("Failed to get hostname")?
        .to_string_lossy()
        .to_string();
    let current_host = repo::resolve_current_host(repo_root).await?;

    doctor_progress("collecting local system state");
    let (generation, failed_units, disk_usage, lock_age, home_pressure_warnings) = tokio::join!(
        collect_nixos_generation(),
        collect_failed_units(),
        collect_disk_usage(),
        collect_flake_lock_age(repo_root),
        collect_home_disk_pressure(),
    );
    let zfs_health = collect_zfs_health(&home_pressure_warnings).await;

    let mut checks = Vec::new();
    let mut markdown = String::from("## System State\n\n");

    if let Some(generation) = &generation {
        markdown.push_str(&format!("**NixOS generation**: {}\n\n", generation));
    }

    markdown.push_str("### Failed systemd units\n");
    if failed_units.is_empty() {
        markdown.push_str("_None_\n\n");
        checks.push(DiagnosticCheck {
            name: "systemd-units".to_string(),
            status: "ok".to_string(),
            detail: "No failed units".to_string(),
        });
    } else {
        for unit in &failed_units {
            markdown.push_str(&format!("- {}\n", unit));
        }
        markdown.push('\n');
        checks.push(DiagnosticCheck {
            name: "systemd-units".to_string(),
            status: "error".to_string(),
            detail: format!("{} failed unit(s)", failed_units.len()),
        });
    }

    markdown.push_str("### Disk usage\n```\n");
    markdown.push_str(&disk_usage);
    markdown.push_str("\n```\n\n");
    checks.push(DiagnosticCheck {
        name: "disk-usage".to_string(),
        status: "ok".to_string(),
        detail: "Disk usage collected".to_string(),
    });

    markdown.push_str("### flake.lock age\n");
    markdown.push_str(&format!("_{}_\n\n", lock_age));
    checks.push(DiagnosticCheck {
        name: "flake-lock-age".to_string(),
        status: "ok".to_string(),
        detail: lock_age,
    });

    append_home_disk_pressure_section(&mut markdown, &mut checks, &home_pressure_warnings);
    append_zfs_health_section(&mut markdown, &mut checks, &zfs_health);
    append_summary_section(&mut markdown, &checks);

    doctor_progress("checking Ollama diagnostics");
    markdown.push_str(&gather_ollama_diagnostics(repo_root, current_host.as_deref()).await);
    markdown.push_str("\n\n");

    doctor_progress("checking fleet health");
    let fleet = gather_fleet_health(repo_root, generation.as_deref()).await;
    if !fleet.is_empty() {
        markdown.push_str(&fleet);
        markdown.push_str("\n\n");
    }

    doctor_progress("checking agent health");
    markdown.push_str(&gather_agent_health());
    markdown.push_str("\n\n");

    doctor_progress("checking agent tasks");
    let tasks = gather_agent_tasks();
    if !tasks.is_empty() {
        markdown.push_str(&tasks);
        markdown.push('\n');
    }

    Ok(DoctorReport {
        hostname,
        nixos_generation: generation,
        checks,
        markdown,
    })
}

pub async fn execute() -> Result<DoctorReport> {
    let repo_root = repo::find_repo()?;
    gather_report(&repo_root).await
}

fn report_file_path() -> PathBuf {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    std::env::temp_dir().join(format!("ks-doctor-{}-{timestamp}.md", std::process::id()))
}

fn render_report(markdown: &str) -> Result<()> {
    if util::interactive_terminal() {
        if let Some(glow) = util::find_executable("glow") {
            let report_file = report_file_path();
            fs::write(&report_file, markdown)
                .with_context(|| format!("Failed to write {}", report_file.display()))?;
            let status = util::run_inherited(
                Command::new(glow).arg(&report_file),
                "Failed to launch glow for doctor report",
            )?;
            let _ = fs::remove_file(&report_file);
            return util::finish_status(status);
        }
    }

    print!("{}", markdown);
    Ok(())
}

pub async fn render_and_maybe_launch(
    local_model: Option<&str>,
    passthrough_args: &[String],
) -> Result<()> {
    let report = execute().await?;
    render_report(&report.markdown)?;

    if !util::interactive_terminal() {
        return Ok(());
    }

    print!("\nLaunch the default agent to review this doctor report? [y/N] ");
    io::stdout().flush().ok();

    let mut reply = String::new();
    io::stdin().read_line(&mut reply).ok();
    match reply.trim() {
        "y" | "Y" | "yes" | "YES" => agent::execute(local_model, passthrough_args).await,
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn doctor_report_serialization() {
        let report = DoctorReport {
            hostname: "test-host".to_string(),
            nixos_generation: Some("25.05.20260401.abc1234".to_string()),
            checks: vec![DiagnosticCheck {
                name: "systemd-units".to_string(),
                status: "ok".to_string(),
                detail: "No failed units".to_string(),
            }],
            markdown: "## System State\n".to_string(),
        };
        let json = serde_json::to_value(&report).unwrap();
        assert_eq!(json["hostname"], "test-host");
        assert_eq!(json["checks"][0]["status"], "ok");
    }

    #[test]
    fn format_bytes_uses_human_units() {
        assert_eq!(format_bytes(512), "512B");
        assert_eq!(format_bytes(2 * KIBIBYTE), "2K");
        assert_eq!(format_bytes(3 * MEBIBYTE), "3M");
        assert_eq!(format_bytes(4 * GIBIBYTE), "4G");
    }

    #[test]
    fn parse_du_size_bytes_reads_first_field() {
        assert_eq!(
            parse_du_size_bytes(b"1048576\t/home/user/.cache\n"),
            Some(1_048_576)
        );
        assert_eq!(parse_du_size_bytes(b"invalid"), None);
    }

    #[test]
    fn build_zfs_health_report_flags_pool_and_snapshot_overhead() {
        let report = build_zfs_health_report(
            vec![("rpool".to_string(), 8 * GIBIBYTE)],
            vec![ZfsDatasetInfo {
                name: "rpool/home".to_string(),
                used_bytes: 100 * GIBIBYTE,
                used_by_snapshots_bytes: 30 * GIBIBYTE,
                mountpoint: "/home/test".to_string(),
            }],
            &[],
            Some(Path::new("/home/test")),
        );

        assert_eq!(report.pools[0].status, "error");
        assert_eq!(report.dataset_warnings.len(), 1);
        assert_eq!(report.dataset_warnings[0].dataset, "rpool/home");
    }

    #[test]
    fn build_zfs_health_report_flags_ephemeral_dir_in_snapshot_surface() {
        let report = build_zfs_health_report(
            vec![("rpool".to_string(), 80 * GIBIBYTE)],
            vec![ZfsDatasetInfo {
                name: "rpool/home".to_string(),
                used_bytes: 100 * GIBIBYTE,
                used_by_snapshots_bytes: 10 * GIBIBYTE,
                mountpoint: "/home/test".to_string(),
            }],
            &[HomeDiskPressureWarning {
                path: "~/.cache".to_string(),
                size_bytes: 11 * GIBIBYTE,
                suggestion: "cleanup",
            }],
            Some(Path::new("/home/test")),
        );

        assert!(report.dataset_warnings.iter().any(|warning| {
            warning
                .note
                .contains("Ephemeral dir ~/.cache is in snapshot surface")
        }));
    }
}
