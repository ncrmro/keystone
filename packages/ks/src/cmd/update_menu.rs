//! `ks update menu ...` — Walker provider backend for the Keystone OS update
//! entry.
//!
//! Subcommands:
//!
//! - `status` — emit the raw state JSON (same shape the bash script used to
//!   produce via `load_state`). Used for diagnostics and consumed by the
//!   other subcommands in-process.
//! - `entries` — emit the Walker JSON entry array.
//! - `preview-summary` — emit the plain-text preview pane for the summary
//!   row.
//! - `preview-release-notes` — emit the plain-text preview pane for the
//!   release-notes row.
//! - `dispatch <value>` — handle a Walker activation. Activation values
//!   include `run-update`, `open-release-page\t<url>`, `blocked\t<title>\t<body>`,
//!   and `noop`.
//!
//! Replaces the previous bash implementation at
//! `modules/desktop/home/scripts/keystone-update-menu.sh`.

use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::repo;

const RELEASE_OWNER: &str = "ncrmro";
const RELEASE_REPO: &str = "keystone";

// -----------------------------------------------------------------------------
// State
// -----------------------------------------------------------------------------

/// Full state emitted when discovery succeeds. Field names match the shape
/// produced by the legacy bash `load_state` so downstream tooling (or humans
/// inspecting `ks update menu status`) sees the same structure.
#[derive(Debug, Serialize)]
struct OkState {
    ok: bool, // always true
    repo_root: String,
    input_name: String,
    current_rev: String,
    current_tag: String,
    latest_tag: String,
    latest_name: String,
    latest_url: String,
    latest_published: String,
    latest_body: String,
    latest_rev: String,
    host_key: String,
    status_kind: String, // "up-to-date" | "behind" | "ahead"
    status_summary: String,
    update_reason: String,
    dirty: bool,
    update_allowed: bool,
}

/// Error state. Partial fields are populated when available so previews can
/// still render something useful.
#[derive(Debug, Serialize, Default)]
struct ErrState {
    ok: bool, // always false
    #[serde(skip_serializing_if = "Option::is_none")]
    repo_root: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    input_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    current_rev: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    current_tag: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_tag: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_published: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    latest_body: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    dirty: Option<bool>,
    error: String,
}

#[derive(Debug, Serialize)]
#[serde(untagged)]
enum MenuState {
    Ok(OkState),
    Err(ErrState),
}

// -----------------------------------------------------------------------------
// Flake.lock parsing
// -----------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct FlakeLock {
    nodes: std::collections::HashMap<String, FlakeNode>,
    // root handling not needed for our purposes
}

#[derive(Debug, Deserialize)]
struct FlakeNode {
    locked: Option<FlakeLocked>,
    original: Option<FlakeOriginal>,
}

#[derive(Debug, Deserialize)]
struct FlakeLocked {
    #[serde(rename = "type")]
    kind: Option<String>,
    rev: Option<String>,
}

#[derive(Debug, Deserialize)]
struct FlakeOriginal {
    #[serde(rename = "type")]
    kind: Option<String>,
    owner: Option<String>,
    repo: Option<String>,
}

fn read_flake_lock(repo_root: &Path) -> Result<FlakeLock> {
    let path = repo_root.join("flake.lock");
    let bytes = std::fs::read(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_slice(&bytes).with_context(|| format!("failed to parse {}", path.display()))
}

/// Find the flake node that points at `{owner}/{repo}` on GitHub.
fn find_keystone_input(lock: &FlakeLock) -> Option<(&String, &FlakeNode)> {
    lock.nodes.iter().find(|(_, node)| {
        node.original
            .as_ref()
            .map(|o| {
                o.kind.as_deref() == Some("github")
                    && o.owner.as_deref() == Some(RELEASE_OWNER)
                    && o.repo.as_deref() == Some(RELEASE_REPO)
            })
            .unwrap_or(false)
    })
}

// -----------------------------------------------------------------------------
// Git helpers
// -----------------------------------------------------------------------------

fn git_status_clean(repo_root: &Path) -> bool {
    let checks: [&[&str]; 2] = [&["diff", "--quiet"], &["diff", "--cached", "--quiet"]];
    for args in checks {
        let status = Command::new("git")
            .arg("-C")
            .arg(repo_root)
            .args(args)
            .status();
        match status {
            Ok(s) if s.success() => continue,
            _ => return false,
        }
    }
    true
}

/// Try to resolve `rev` to an exact-match release tag via a local keystone
/// checkout. If no local checkout is available or the rev has no tag, returns
/// an empty string (matching the bash semantics).
fn release_tag_for_rev(rev: &str) -> String {
    let keystone_root = match repo::resolve_keystone_repo() {
        Ok(path) => path,
        Err(_) => return String::new(),
    };
    let output = Command::new("git")
        .arg("-C")
        .arg(&keystone_root)
        .args(["describe", "--tags", "--exact-match", rev])
        .output();
    match output {
        Ok(out) if out.status.success() => {
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        }
        _ => String::new(),
    }
}

fn rev_exists_locally(rev: &str) -> bool {
    let Ok(keystone_root) = repo::resolve_keystone_repo() else {
        return false;
    };
    Command::new("git")
        .arg("-C")
        .arg(&keystone_root)
        .args(["cat-file", "-e", rev])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn rev_is_ancestor_of(ancestor: &str, descendant: &str) -> bool {
    let Ok(keystone_root) = repo::resolve_keystone_repo() else {
        return false;
    };
    Command::new("git")
        .arg("-C")
        .arg(&keystone_root)
        .args(["merge-base", "--is-ancestor", ancestor, descendant])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

// -----------------------------------------------------------------------------
// GitHub release fetch
// -----------------------------------------------------------------------------

async fn fetch_latest_release() -> Result<Value> {
    let url = format!(
        "https://api.github.com/repos/{}/{}/releases/latest",
        RELEASE_OWNER, RELEASE_REPO
    );
    let mut req = reqwest::Client::new()
        .get(&url)
        .header("User-Agent", "ks")
        .header("Accept", "application/vnd.github+json");
    if let Ok(token) = std::env::var("GITHUB_TOKEN") {
        if !token.is_empty() {
            req = req.header("Authorization", format!("Bearer {token}"));
        }
    }
    let response = req.send().await.context("GitHub request failed")?;
    let json = response
        .error_for_status()
        .context("GitHub returned non-success status")?
        .json::<Value>()
        .await
        .context("GitHub response was not valid JSON")?;
    Ok(json)
}

/// Resolve a tag to its commit sha by querying the GitHub refs API.
/// Handles both annotated and lightweight tags.
async fn fetch_release_commit_rev(tag: &str) -> Result<String> {
    let url = format!(
        "https://api.github.com/repos/{}/{}/git/ref/tags/{}",
        RELEASE_OWNER, RELEASE_REPO, tag
    );
    let mut req = reqwest::Client::new()
        .get(&url)
        .header("User-Agent", "ks")
        .header("Accept", "application/vnd.github+json");
    if let Ok(token) = std::env::var("GITHUB_TOKEN") {
        if !token.is_empty() {
            req = req.header("Authorization", format!("Bearer {token}"));
        }
    }
    let response = req.send().await.context("GitHub ref request failed")?;
    let ref_json: Value = response
        .error_for_status()
        .context("GitHub returned non-success for ref")?
        .json()
        .await
        .context("GitHub ref response was not valid JSON")?;

    let obj = ref_json
        .get("object")
        .ok_or_else(|| anyhow!("GitHub ref missing 'object'"))?;
    let kind = obj.get("type").and_then(|v| v.as_str()).unwrap_or("");
    let sha = obj
        .get("sha")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("GitHub ref missing sha"))?;

    if kind == "commit" {
        return Ok(sha.to_string());
    }

    // Annotated tag — follow the tag object to its target commit.
    let tag_url = format!(
        "https://api.github.com/repos/{}/{}/git/tags/{}",
        RELEASE_OWNER, RELEASE_REPO, sha
    );
    let mut tag_req = reqwest::Client::new()
        .get(&tag_url)
        .header("User-Agent", "ks")
        .header("Accept", "application/vnd.github+json");
    if let Ok(token) = std::env::var("GITHUB_TOKEN") {
        if !token.is_empty() {
            tag_req = tag_req.header("Authorization", format!("Bearer {token}"));
        }
    }
    let tag_json: Value = tag_req
        .send()
        .await
        .context("GitHub tag request failed")?
        .error_for_status()
        .context("GitHub returned non-success for tag")?
        .json()
        .await
        .context("GitHub tag response was not valid JSON")?;

    tag_json
        .get("object")
        .and_then(|o| o.get("sha"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| anyhow!("GitHub tag object missing commit sha"))
}

// -----------------------------------------------------------------------------
// Host key resolution
// -----------------------------------------------------------------------------

async fn current_host_key(repo_root: &Path) -> Option<String> {
    match repo::resolve_current_host(repo_root).await {
        Ok(Some(host)) => Some(host),
        _ => None,
    }
}

// -----------------------------------------------------------------------------
// State orchestration
// -----------------------------------------------------------------------------

async fn load_state(flake_override: Option<&Path>) -> MenuState {
    let repo_root = match repo::find_repo(flake_override) {
        Ok(path) => path,
        Err(_) => {
            return MenuState::Err(ErrState {
                ok: false,
                error: "Unable to locate the active system flake.".into(),
                ..Default::default()
            });
        }
    };

    let repo_root_str = repo_root.display().to_string();

    if !repo_root.join("flake.lock").exists() {
        return MenuState::Err(ErrState {
            ok: false,
            repo_root: Some(repo_root_str),
            error: "The active system flake has no flake.lock.".into(),
            ..Default::default()
        });
    }

    let lock = match read_flake_lock(&repo_root) {
        Ok(lock) => lock,
        Err(err) => {
            return MenuState::Err(ErrState {
                ok: false,
                repo_root: Some(repo_root_str),
                error: format!("Unable to read flake.lock: {err}"),
                ..Default::default()
            });
        }
    };

    let Some((input_name, node)) = find_keystone_input(&lock) else {
        return MenuState::Err(ErrState {
            ok: false,
            repo_root: Some(repo_root_str),
            error: "Unable to find a Keystone GitHub input in the active system flake.".into(),
            ..Default::default()
        });
    };
    let input_name = input_name.clone();

    let Some(locked) = node.locked.as_ref() else {
        return MenuState::Err(ErrState {
            ok: false,
            repo_root: Some(repo_root_str),
            input_name: Some(input_name),
            error: "The Keystone input has no locked revision.".into(),
            ..Default::default()
        });
    };

    if locked.kind.as_deref() != Some("github") {
        return MenuState::Err(ErrState {
            ok: false,
            repo_root: Some(repo_root_str),
            input_name: Some(input_name),
            error: "The Keystone input is not locked to a GitHub source.".into(),
            ..Default::default()
        });
    }

    let Some(current_rev) = locked.rev.clone() else {
        return MenuState::Err(ErrState {
            ok: false,
            repo_root: Some(repo_root_str),
            input_name: Some(input_name),
            error: "Unable to read the locked Keystone revision from flake.lock.".into(),
            ..Default::default()
        });
    };

    let current_tag = release_tag_for_rev(&current_rev);
    let dirty = !git_status_clean(&repo_root);

    let release = match fetch_latest_release().await {
        Ok(v) => v,
        Err(err) => {
            return MenuState::Err(ErrState {
                ok: false,
                repo_root: Some(repo_root_str),
                input_name: Some(input_name),
                current_rev: Some(current_rev),
                current_tag: Some(current_tag),
                dirty: Some(dirty),
                error: format!("Unable to fetch the latest Keystone release from GitHub: {err}"),
                ..Default::default()
            });
        }
    };

    let latest_tag = release
        .get("tag_name")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    if latest_tag.is_empty() {
        return MenuState::Err(ErrState {
            ok: false,
            repo_root: Some(repo_root_str),
            input_name: Some(input_name),
            current_rev: Some(current_rev),
            current_tag: Some(current_tag),
            error: "GitHub did not return a latest release tag for Keystone.".into(),
            ..Default::default()
        });
    }

    let latest_name = release
        .get("name")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .unwrap_or(&latest_tag)
        .to_string();
    let latest_url = release
        .get("html_url")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let latest_published = release
        .get("published_at")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let latest_body = release
        .get("body")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("No release notes available.")
        .to_string();

    let latest_rev = match fetch_release_commit_rev(&latest_tag).await {
        Ok(rev) => rev,
        Err(err) => {
            return MenuState::Err(ErrState {
                ok: false,
                repo_root: Some(repo_root_str),
                input_name: Some(input_name),
                current_rev: Some(current_rev),
                current_tag: Some(current_tag),
                latest_tag: Some(latest_tag),
                latest_name: Some(latest_name),
                latest_url: Some(latest_url),
                latest_published: Some(latest_published),
                latest_body: Some(latest_body),
                error: format!(
                    "Unable to resolve the commit for the latest Keystone release tag: {err}"
                ),
                ..Default::default()
            });
        }
    };

    let host_key = current_host_key(&repo_root).await.unwrap_or_default();

    let (status_kind, status_summary) = if current_rev == latest_rev {
        (
            "up-to-date",
            "Locked release matches the latest published Keystone release.",
        )
    } else if !current_tag.is_empty() {
        ("behind", "A newer Keystone release is available on GitHub.")
    } else if rev_exists_locally(&current_rev)
        && rev_exists_locally(&latest_rev)
        && rev_is_ancestor_of(&latest_rev, &current_rev)
    {
        (
            "ahead",
            "The locked revision is newer than the latest published Keystone release.",
        )
    } else {
        (
            "behind",
            "The locked revision does not match the latest published Keystone release.",
        )
    };

    let mut update_allowed = false;
    let update_reason = match status_kind {
        "behind" => {
            if dirty {
                "The active system flake has uncommitted changes.".to_string()
            } else if host_key.is_empty() {
                "Unable to resolve the current host key from hosts.nix.".to_string()
            } else {
                update_allowed = true;
                String::new()
            }
        }
        "up-to-date" => "The current host already uses the latest Keystone release.".to_string(),
        _ => "The current lock is newer than the latest published release, so Walker will not downgrade it automatically.".to_string(),
    };

    MenuState::Ok(OkState {
        ok: true,
        repo_root: repo_root_str,
        input_name,
        current_rev,
        current_tag,
        latest_tag,
        latest_name,
        latest_url,
        latest_published,
        latest_body,
        latest_rev,
        host_key,
        status_kind: status_kind.to_string(),
        status_summary: status_summary.to_string(),
        update_reason,
        dirty,
        update_allowed,
    })
}

// -----------------------------------------------------------------------------
// Rendering
// -----------------------------------------------------------------------------

/// Short sha: first 7 chars, handling short revs gracefully.
fn short(rev: &str) -> &str {
    if rev.len() >= 7 {
        &rev[..7]
    } else {
        rev
    }
}

fn render_preview_summary(state: &MenuState) -> String {
    match state {
        MenuState::Ok(s) => {
            let current_label = if !s.current_tag.is_empty() {
                s.current_tag.clone()
            } else {
                short(&s.current_rev).to_string()
            };
            let update_line = if s.update_allowed {
                "Update command: ks update".to_string()
            } else {
                format!("Update: {}", s.update_reason)
            };
            [
                "Keystone OS update status".to_string(),
                String::new(),
                format!("Consumer flake: {}", s.repo_root),
                format!("Input: {}", s.input_name),
                format!("Current: {} ({})", current_label, short(&s.current_rev)),
                format!("Latest: {} ({})", s.latest_tag, short(&s.latest_rev)),
                format!("Status: {}", s.status_summary),
                update_line,
            ]
            .join("\n")
        }
        MenuState::Err(e) => ["Keystone OS update unavailable", "", &e.error].join("\n"),
    }
}

fn render_preview_release_notes(state: &MenuState) -> String {
    match state {
        MenuState::Ok(s) => {
            let published = if s.latest_published.is_empty() {
                "Published: unknown".to_string()
            } else {
                format!("Published: {}", s.latest_published)
            };
            let name = if s.latest_name.is_empty() {
                s.latest_tag.clone()
            } else {
                s.latest_name.clone()
            };
            [
                name,
                format!("Tag: {}", s.latest_tag),
                published,
                String::new(),
                s.latest_body.clone(),
                String::new(),
                s.latest_url.clone(),
            ]
            .join("\n")
        }
        MenuState::Err(e) => {
            // Try to surface whatever release context we have even in the
            // partial-error case so the preview pane is useful.
            if let Some(latest_tag) = &e.latest_tag {
                let name = e.latest_name.clone().unwrap_or_else(|| latest_tag.clone());
                let published = e
                    .latest_published
                    .clone()
                    .filter(|s| !s.is_empty())
                    .map(|s| format!("Published: {s}"))
                    .unwrap_or_else(|| "Published: unknown".into());
                let body = e
                    .latest_body
                    .clone()
                    .unwrap_or_else(|| "No release notes available.".into());
                let url = e.latest_url.clone().unwrap_or_default();
                return [
                    name,
                    format!("Tag: {latest_tag}"),
                    published,
                    String::new(),
                    body,
                    String::new(),
                    url,
                ]
                .join("\n");
            }
            ["Keystone release notes unavailable", "", &e.error].join("\n")
        }
    }
}

fn render_entries_json(state: &MenuState) -> Result<String> {
    let entries: Vec<Value> = match state {
        MenuState::Ok(s) => {
            let current_label = if !s.current_tag.is_empty() {
                s.current_tag.clone()
            } else {
                short(&s.current_rev).to_string()
            };
            let mut entries = vec![
                serde_json::json!({
                    "Text": format!("Current: {}", current_label),
                    "Subtext": s.status_summary,
                    "Value": "noop",
                    "Icon": "dialog-information-symbolic",
                    "Preview": "ks update menu preview-summary",
                    "PreviewType": "command",
                }),
                serde_json::json!({
                    "Text": format!("Latest: {}", s.latest_tag),
                    "Subtext": "GitHub release notes and changelog",
                    "Value": format!("open-release-page\t{}", s.latest_url),
                    "Icon": "software-update-available-symbolic",
                    "Preview": "ks update menu preview-release-notes",
                    "PreviewType": "command",
                }),
            ];
            if s.update_allowed {
                entries.push(serde_json::json!({
                    "Text": "Update current host",
                    "Subtext": format!("Run ks update to install {} on this host", s.latest_tag),
                    "Value": "run-update",
                    "Icon": "system-software-update-symbolic",
                    "Preview": "ks update menu preview-summary",
                    "PreviewType": "command",
                }));
            } else {
                entries.push(serde_json::json!({
                    "Text": "Update unavailable",
                    "Subtext": s.update_reason,
                    "Value": format!("blocked\tUpdate unavailable\t{}", s.update_reason),
                    "Icon": "dialog-warning-symbolic",
                    "Preview": "ks update menu preview-summary",
                    "PreviewType": "command",
                }));
            }
            entries
        }
        MenuState::Err(e) => vec![serde_json::json!({
            "Text": "Keystone OS unavailable",
            "Subtext": e.error,
            "Value": format!("blocked\tKeystone OS unavailable\t{}", e.error),
            "Icon": "dialog-warning-symbolic",
            "Preview": "ks update menu preview-summary",
            "PreviewType": "command",
        })],
    };
    serde_json::to_string(&entries).context("failed to serialize entries")
}

// -----------------------------------------------------------------------------
// Dispatch
// -----------------------------------------------------------------------------

fn run_notify_send(summary: &str, body: &str) -> Result<()> {
    let status = Command::new("notify-send")
        .args(["--app-name=Keystone", summary, body])
        .status()
        .context("failed to invoke notify-send")?;
    if !status.success() {
        anyhow::bail!("notify-send exited with status {:?}", status.code());
    }
    Ok(())
}

fn xdg_open_detached(url: &str) -> Result<()> {
    // Spawn xdg-open and detach so Walker's dispatch process can exit.
    Command::new("xdg-open")
        .arg(url)
        .spawn()
        .context("failed to spawn xdg-open")?;
    Ok(())
}

/// Start the background update unit via systemd --user. This replaces the
/// previous Ghostty-detach path: the unit handles approval (pkexec via
/// hyprpolkitagent), logging (journal), and completion notification
/// (OnSuccess/OnFailure -> ks-update-notify@.service).
fn start_update_unit() -> Result<()> {
    let status = Command::new("systemctl")
        .args(["--user", "start", "ks-update.service"])
        .status()
        .context("failed to invoke systemctl --user start ks-update.service")?;
    if !status.success() {
        anyhow::bail!(
            "systemctl --user start ks-update.service exited with status {:?}",
            status.code()
        );
    }
    Ok(())
}

fn dispatch(value: &str) -> Result<()> {
    let mut parts = value.splitn(3, '\t');
    let action = parts.next().unwrap_or("");
    let arg1 = parts.next().unwrap_or("");
    let arg2 = parts.next().unwrap_or("");

    match action {
        "" | "noop" => Ok(()),
        "blocked" => run_notify_send(arg1, arg2),
        "open-release-page" => xdg_open_detached(arg1),
        "run-update" => start_update_unit(),
        other => Err(anyhow!("unknown update menu action: {other}")),
    }
}

// -----------------------------------------------------------------------------
// Subcommand entry
// -----------------------------------------------------------------------------

#[derive(Debug, clap::Subcommand)]
pub enum UpdateMenuCommand {
    /// Emit the raw state JSON used by the other subcommands.
    Status,
    /// Emit the Walker entry array as JSON.
    Entries,
    /// Emit the plain-text summary preview pane.
    PreviewSummary,
    /// Emit the plain-text release-notes preview pane.
    PreviewReleaseNotes,
    /// Handle a Walker activation value.
    Dispatch {
        /// Activation value, possibly tab-separated for multi-arg actions.
        #[arg(default_value = "")]
        value: String,
    },
}

pub async fn execute(cmd: UpdateMenuCommand, flake: Option<&Path>) -> Result<()> {
    match cmd {
        UpdateMenuCommand::Status => {
            let state = load_state(flake).await;
            println!("{}", serde_json::to_string_pretty(&state)?);
            Ok(())
        }
        UpdateMenuCommand::Entries => {
            let state = load_state(flake).await;
            println!("{}", render_entries_json(&state)?);
            Ok(())
        }
        UpdateMenuCommand::PreviewSummary => {
            let state = load_state(flake).await;
            println!("{}", render_preview_summary(&state));
            Ok(())
        }
        UpdateMenuCommand::PreviewReleaseNotes => {
            let state = load_state(flake).await;
            println!("{}", render_preview_release_notes(&state));
            Ok(())
        }
        UpdateMenuCommand::Dispatch { value } => dispatch(&value),
    }
}

// Silence dead-code warnings for helpers the linter may not see from tests
// elsewhere in the crate.
#[allow(dead_code)]
fn _keep(_: &PathBuf) {}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn ok_fixture() -> OkState {
        OkState {
            ok: true,
            repo_root: "/etc/nixos-config".into(),
            input_name: "keystone".into(),
            current_rev: "aaaaaaaabbbbbbbbccccccccddddddddeeeeeeee".into(),
            current_tag: "v0.7.0".into(),
            latest_tag: "v0.8.0".into(),
            latest_name: "v0.8.0".into(),
            latest_url: "https://github.com/ncrmro/keystone/releases/tag/v0.8.0".into(),
            latest_published: "2026-04-01T10:00:00Z".into(),
            latest_body: "## Changes\n- Added Walker update menu".into(),
            latest_rev: "bbbbbbbbccccccccddddddddeeeeeeeeffffffff".into(),
            host_key: "mox".into(),
            status_kind: "behind".into(),
            status_summary: "A newer Keystone release is available on GitHub.".into(),
            update_reason: String::new(),
            dirty: false,
            update_allowed: true,
        }
    }

    #[test]
    fn short_returns_first_seven_chars() {
        assert_eq!(short("aaaaaaaabbbbbbbbccccccccddddddddeeeeeeee"), "aaaaaaa");
        assert_eq!(short("abc"), "abc");
        assert_eq!(short(""), "");
    }

    #[test]
    fn entries_ok_state_has_three_entries_with_update_row() {
        let state = MenuState::Ok(ok_fixture());
        let rendered = render_entries_json(&state).unwrap();
        let parsed: Value = serde_json::from_str(&rendered).unwrap();
        let arr = parsed.as_array().unwrap();
        assert_eq!(arr.len(), 3);
        assert_eq!(arr[0]["Text"], "Current: v0.7.0");
        assert_eq!(arr[1]["Text"], "Latest: v0.8.0");
        assert_eq!(arr[2]["Text"], "Update current host");
        assert_eq!(arr[2]["Value"], "run-update");
        assert!(
            arr[1]["Value"]
                .as_str()
                .unwrap()
                .starts_with("open-release-page\t"),
            "latest entry must open the release page on activation"
        );
    }

    #[test]
    fn entries_blocks_when_update_not_allowed() {
        let mut fixture = ok_fixture();
        fixture.update_allowed = false;
        fixture.update_reason = "The active system flake has uncommitted changes.".into();
        let state = MenuState::Ok(fixture);
        let rendered = render_entries_json(&state).unwrap();
        let parsed: Value = serde_json::from_str(&rendered).unwrap();
        let arr = parsed.as_array().unwrap();
        let blocked = &arr[2];
        assert_eq!(blocked["Text"], "Update unavailable");
        let value = blocked["Value"].as_str().unwrap();
        assert!(
            value.starts_with("blocked\t"),
            "blocked entry must use the notify fallback, got {value}"
        );
        assert!(value.contains("uncommitted changes"));
    }

    #[test]
    fn entries_err_state_surfaces_error() {
        let state = MenuState::Err(ErrState {
            ok: false,
            error: "No flake.lock found.".into(),
            ..Default::default()
        });
        let rendered = render_entries_json(&state).unwrap();
        let parsed: Value = serde_json::from_str(&rendered).unwrap();
        let arr = parsed.as_array().unwrap();
        assert_eq!(arr.len(), 1);
        assert_eq!(arr[0]["Text"], "Keystone OS unavailable");
        assert_eq!(arr[0]["Subtext"], "No flake.lock found.");
    }

    #[test]
    fn preview_summary_ok_formats_key_fields() {
        let state = MenuState::Ok(ok_fixture());
        let rendered = render_preview_summary(&state);
        assert!(rendered.contains("Keystone OS update status"));
        assert!(rendered.contains("Consumer flake: /etc/nixos-config"));
        assert!(rendered.contains("Current: v0.7.0 (aaaaaaa)"));
        assert!(rendered.contains("Latest: v0.8.0 (bbbbbbb)"));
        assert!(rendered.contains("Update command: ks update"));
    }

    #[test]
    fn preview_summary_shows_blocker_when_update_not_allowed() {
        let mut fixture = ok_fixture();
        fixture.update_allowed = false;
        fixture.update_reason = "Working tree dirty.".into();
        let rendered = render_preview_summary(&MenuState::Ok(fixture));
        assert!(rendered.contains("Update: Working tree dirty."));
        assert!(!rendered.contains("Update command: ks update"));
    }

    #[test]
    fn preview_release_notes_renders_body_and_url() {
        let state = MenuState::Ok(ok_fixture());
        let rendered = render_preview_release_notes(&state);
        assert!(rendered.contains("v0.8.0"));
        assert!(rendered.contains("Tag: v0.8.0"));
        assert!(rendered.contains("Published: 2026-04-01T10:00:00Z"));
        assert!(rendered.contains("Added Walker update menu"));
        assert!(rendered.contains("https://github.com/ncrmro/keystone/releases/tag/v0.8.0"));
    }

    #[test]
    fn preview_release_notes_uses_partial_err_state_when_available() {
        let state = MenuState::Err(ErrState {
            ok: false,
            latest_tag: Some("v0.8.0".into()),
            latest_body: Some("Release notes body".into()),
            latest_url: Some("https://example/release".into()),
            error: "Could not resolve release commit".into(),
            ..Default::default()
        });
        let rendered = render_preview_release_notes(&state);
        // Partial render should surface the tag even though the overall state
        // is errored out.
        assert!(rendered.contains("Tag: v0.8.0"));
        assert!(rendered.contains("Release notes body"));
        assert!(rendered.contains("https://example/release"));
    }

    #[test]
    fn dispatch_rejects_unknown_actions() {
        let err = dispatch("mystery-action").unwrap_err();
        assert!(
            err.to_string().contains("unknown update menu action"),
            "got: {err}"
        );
    }

    #[test]
    fn dispatch_noop_is_ok() {
        dispatch("").unwrap();
        dispatch("noop").unwrap();
    }
}

