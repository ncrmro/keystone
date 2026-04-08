//! `ks doctor` command — system and fleet health diagnostics.

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

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
    let generation = collect_nixos_generation().await;
    let failed_units = collect_failed_units().await;
    let disk_usage = collect_disk_usage().await;
    let lock_age = collect_flake_lock_age(repo_root).await;

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
}
