//! `ks approve` command — privileged allowlisted execution.

use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
use std::env;
use std::ffi::OsString;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};

#[derive(Debug, Deserialize)]
struct ApprovalMatch {
    #[serde(rename = "displayName")]
    display_name: String,
    reason: String,
}

fn find_executable(name: &str) -> Option<PathBuf> {
    let path = env::var_os("PATH")?;
    for entry in env::split_paths(&path) {
        let candidate = entry.join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

fn resolve_approval_helper() -> Result<PathBuf> {
    if let Some(helper) = find_executable("keystone-approve-exec") {
        return Ok(helper);
    }

    let fallback = PathBuf::from("/run/current-system/sw/bin/keystone-approve-exec");
    if fallback.is_file() {
        return Ok(fallback);
    }

    Err(anyhow!(
        "keystone-approve-exec is not available in PATH. Enable keystone.security.privilegedApproval on this host first."
    ))
}

fn has_graphical_session() -> bool {
    env::var_os("DISPLAY").is_some()
        || env::var_os("WAYLAND_DISPLAY").is_some()
        || env::var_os("XDG_SESSION_TYPE").is_some()
}

fn is_root_user() -> Result<bool> {
    let output = Command::new("id")
        .arg("-u")
        .output()
        .context("Failed to check effective user id")?;

    if !output.status.success() {
        return Err(anyhow!("Failed to check effective user id"));
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim() == "0")
}

fn validate_request(
    helper: &PathBuf,
    reason: &str,
    requested_argv: &[String],
) -> Result<ApprovalMatch> {
    let output = Command::new(helper)
        .arg("--validate")
        .arg("--reason")
        .arg(reason)
        .arg("--")
        .args(requested_argv)
        .output()
        .context("Failed to validate approval request")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let detail = if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            "Approval request rejected".to_string()
        };
        return Err(anyhow!(detail));
    }

    serde_json::from_slice(&output.stdout).context("Failed to parse approval policy response")
}

fn exec_command(program: PathBuf, args: Vec<OsString>) -> Result<()> {
    let error = Command::new(program)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .exec();
    Err(anyhow!(error)).context("Failed to launch approval helper")
}

pub fn execute(reason: &str, requested_argv: &[String]) -> Result<()> {
    if reason.trim().is_empty() {
        anyhow::bail!("--reason is required")
    }
    if requested_argv.is_empty() {
        anyhow::bail!("Missing command after --")
    }

    let helper = resolve_approval_helper()?;
    let matched = validate_request(&helper, reason, requested_argv)?;

    println!("Approval request: {}", matched.display_name);
    println!("Requested reason: {}", reason);
    println!("Policy reason: {}", matched.reason);

    let mut args = vec![
        OsString::from("--reason"),
        OsString::from(reason),
        OsString::from("--"),
    ];
    args.extend(requested_argv.iter().map(OsString::from));

    if is_root_user()? || env::var_os("KS_APPROVE_EXECUTING").is_some() {
        return exec_command(helper, args);
    }

    if has_graphical_session() && find_executable("pkexec").is_some() {
        let mut pkexec_args = vec![helper.into_os_string()];
        pkexec_args.extend(args);
        return exec_command(PathBuf::from("pkexec"), pkexec_args);
    }

    let mut sudo_args = vec![helper.into_os_string()];
    sudo_args.extend(args);
    exec_command(PathBuf::from("sudo"), sudo_args)
}
