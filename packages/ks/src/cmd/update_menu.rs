//! `ks menu update ...` — Walker provider backend for the Keystone OS update
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
//! - `dispatch <value>` — handle a Walker activation. Activation values are
//!   restricted to the stable tokens listed in the `Activation values`
//!   block below (`run-update`, `noop`, `blocked-update-unavailable`,
//!   `blocked-keystone-unavailable`, and `open-release-page\t<url>`) so the
//!   Lua provider's single-quoted `%VALUE%` interpolation stays safe.
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
/// inspecting `ks menu update status`) sees the same structure.
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
    // The `root` attribute names the entry node; the legacy bash probe
    // anchored resolution there so the menu is immune to transitive
    // dependencies that happen to pin the same GitHub repo.
    #[serde(default = "default_root")]
    root: String,
}

fn default_root() -> String {
    "root".to_string()
}

#[derive(Debug, Deserialize)]
struct FlakeNode {
    locked: Option<FlakeLocked>,
    original: Option<FlakeOriginal>,
    /// Present on the root node; maps input names to node ids (either a
    /// direct string, or a resolution-path array for `follows` inputs).
    #[serde(default)]
    inputs: std::collections::HashMap<String, InputRef>,
}

/// A root-level input entry points either at a node name (direct input) or a
/// resolution path (a `follows` chain). We only care about the direct case
/// when identifying which input is the keystone one.
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum InputRef {
    Direct(String),
    Path(Vec<String>),
}

impl InputRef {
    fn as_node_name(&self) -> Option<&str> {
        match self {
            InputRef::Direct(name) => Some(name.as_str()),
            InputRef::Path(_) => None,
        }
    }
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
    let bytes =
        std::fs::read(&path).with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_slice(&bytes).with_context(|| format!("failed to parse {}", path.display()))
}

/// Find the consumer flake's direct input that points at
/// `{RELEASE_OWNER}/{RELEASE_REPO}` on GitHub.
///
/// Walks `nodes[<root>].inputs` (the entry node declared by `flake.lock`'s
/// top-level `root` attribute) rather than scanning every node, so a
/// transitive dependency that happens to also depend on `ncrmro/keystone`
/// can't cause us to read the wrong locked revision. Returns the **root
/// input name** (e.g., `"keystone"`) and the resolved node. Errors if zero
/// or multiple root inputs match — the legacy bash probe had the same
/// "exactly one" contract and silent ambiguity would quietly point the
/// menu at an unrelated pin.
fn find_keystone_input(lock: &FlakeLock) -> Result<(String, &FlakeNode)> {
    let root_node = lock
        .nodes
        .get(&lock.root)
        .ok_or_else(|| anyhow!("flake.lock root node '{}' missing", lock.root))?;

    let mut matches: Vec<(String, &FlakeNode)> = Vec::new();
    for (input_name, input_ref) in &root_node.inputs {
        let Some(node_name) = input_ref.as_node_name() else {
            // Skip `follows` paths — those resolve to another input, not a
            // direct GitHub source, so they cannot be the keystone input.
            continue;
        };
        let Some(node) = lock.nodes.get(node_name) else {
            continue;
        };
        let matches_keystone = node
            .original
            .as_ref()
            .map(|o| {
                o.kind.as_deref() == Some("github")
                    && o.owner.as_deref() == Some(RELEASE_OWNER)
                    && o.repo.as_deref() == Some(RELEASE_REPO)
            })
            .unwrap_or(false);
        if matches_keystone {
            matches.push((input_name.clone(), node));
        }
    }

    match matches.len() {
        0 => Err(anyhow!(
            "no root input pins {RELEASE_OWNER}/{RELEASE_REPO} on GitHub"
        )),
        1 => Ok(matches.into_iter().next().unwrap()),
        n => {
            let names: Vec<&str> = matches.iter().map(|(name, _)| name.as_str()).collect();
            Err(anyhow!(
                "found {n} root inputs pinning {RELEASE_OWNER}/{RELEASE_REPO}: {names:?}"
            ))
        }
    }
}

// -----------------------------------------------------------------------------
// Git helpers
// -----------------------------------------------------------------------------

/// Mirror the legacy bash `repo_is_clean` check. Uses
/// `git status --porcelain --untracked-files=normal` so a working tree with
/// untracked files is flagged as dirty — matching the previous behaviour and
/// preventing `ks update` from racing against in-flight local work.
fn git_status_clean(repo_root: &Path) -> bool {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["status", "--porcelain", "--untracked-files=normal"])
        .output();

    match output {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).trim().is_empty(),
        _ => false,
    }
}

/// Parse a `v<major>.<minor>.<patch>` tag into a sortable tuple. Returns
/// `None` for any tag that isn't exactly that shape — pre-releases
/// (`v1.2.3-rc1`), build metadata (`v1.2.3+build.42`), and non-release
/// markers (`prod`, `release-candidate`) are deliberately filtered out so
/// `current_tag` only ever reflects a published release.
fn parse_release_tag(tag: &str) -> Option<(u32, u32, u32)> {
    let rest = tag.strip_prefix('v')?;
    let mut parts = rest.split('.');
    let major: u32 = parts.next()?.parse().ok()?;
    let minor: u32 = parts.next()?.parse().ok()?;
    let patch: u32 = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some((major, minor, patch))
}

/// Try to resolve `rev` to a release tag (`v<major>.<minor>.<patch>`) via
/// the local keystone checkout. When multiple release tags point at the
/// same rev, returns the highest-numbered one. Anything not matching the
/// release-tag shape — pre-releases, build metadata, arbitrary tags — is
/// ignored. Matches the legacy bash probe's semantics so `current_tag`
/// cannot be set by unrelated tags pointing at the same commit.
fn release_tag_for_rev(rev: &str) -> String {
    let keystone_root = match repo::resolve_keystone_repo() {
        Ok(path) => path,
        Err(_) => return String::new(),
    };
    let output = Command::new("git")
        .arg("-C")
        .arg(&keystone_root)
        .args(["tag", "--points-at", rev])
        .output();
    let raw = match output {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).to_string(),
        _ => return String::new(),
    };

    raw.lines()
        .map(str::trim)
        .filter_map(|tag| parse_release_tag(tag).map(|ver| (tag.to_string(), ver)))
        .max_by_key(|(_, ver)| *ver)
        .map(|(tag, _)| tag)
        .unwrap_or_default()
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

/// Total budget for any single GitHub API call made by the menu backend.
/// Keep small: Walker calls `ks menu update entries` synchronously on menu
/// open, and a hung fetch stalls the whole desktop menu render. Fail fast
/// and surface an `ErrState` (which renders a visible "Keystone OS
/// unavailable" row) rather than hang.
const GITHUB_REQUEST_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);
const GITHUB_CONNECT_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(5);

/// Build a bounded reqwest client for GitHub API calls. Centralizing so
/// every call site picks up the same timeout + user-agent defaults.
fn github_client() -> Result<reqwest::Client> {
    reqwest::Client::builder()
        .timeout(GITHUB_REQUEST_TIMEOUT)
        .connect_timeout(GITHUB_CONNECT_TIMEOUT)
        .user_agent("ks")
        .build()
        .context("failed to build GitHub reqwest client")
}

async fn fetch_latest_release() -> Result<Value> {
    let url = format!(
        "https://api.github.com/repos/{}/{}/releases/latest",
        RELEASE_OWNER, RELEASE_REPO
    );
    let mut req = github_client()?
        .get(&url)
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
    let mut req = github_client()?
        .get(&url)
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
    let mut tag_req = github_client()?
        .get(&tag_url)
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

/// Local-only precondition check used by dispatch to close the TOCTOU
/// window between entries-render and activation. Returns `Ok(())` when
/// the menu's update action can proceed, or `Err(reason)` with the same
/// user-facing text `load_state` would produce for the same failure
/// mode. Does **not** fetch from GitHub — `latest_tag` is stale by design
/// between render and dispatch, and a network hiccup should not block a
/// user whose local state is actually fine.
fn evaluate_local_gate(flake_override: Option<&Path>) -> Result<(), String> {
    let repo_root = repo::find_repo(flake_override)
        .map_err(|_| "Unable to locate the active system flake.".to_string())?;

    if !repo_root.join("flake.lock").exists() {
        return Err("The active system flake has no flake.lock.".into());
    }

    let lock =
        read_flake_lock(&repo_root).map_err(|err| format!("Unable to read flake.lock: {err}"))?;

    find_keystone_input(&lock).map_err(|err| {
        format!("Unable to find a Keystone GitHub input in the active system flake: {err}")
    })?;

    if !git_status_clean(&repo_root) {
        return Err("The active system flake has uncommitted changes.".into());
    }

    Ok(())
}

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

    let (input_name, node) = match find_keystone_input(&lock) {
        Ok(pair) => pair,
        Err(err) => {
            return MenuState::Err(ErrState {
                ok: false,
                repo_root: Some(repo_root_str),
                error: format!(
                    "Unable to find a Keystone GitHub input in the active system flake: {err}"
                ),
                ..Default::default()
            });
        }
    };

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

    // `host_key` is retained for state inspection (surfaced by
    // `ks menu update status`) but is no longer a gating precondition for
    // offering the update entry. The dispatch path is `ks update` with no
    // explicit host, and ks resolves the current host on its own via the
    // keystone-system-flake pointer — so a hosts.nix that can't be read
    // here would still succeed at deploy time, and blocking the menu purely
    // on that lookup would produce spurious "Update unavailable" entries.
    let mut update_allowed = false;
    let update_reason = match status_kind {
        "behind" => {
            if dirty {
                "The active system flake has uncommitted changes.".to_string()
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

// -----------------------------------------------------------------------------
// Activation values
// -----------------------------------------------------------------------------
//
// Walker's Lua provider single-quotes `%VALUE%` into a shell command. Free-
// form text containing a single quote, backslash, or control character would
// either break shell quoting or let an attacker inject into the dispatch
// argv. The activation values below are restricted to a fixed set of tokens
// so the Lua layer stays quoting-safe without encoding/decoding.
//
// For actions that carry a payload (currently only `open-release-page`), the
// payload must either:
//   (a) be a well-formed URL with no single quotes / whitespace, or
//   (b) be a stable tag that `dispatch` looks up fresh from `load_state`.
//
// Free-form error or reason strings MUST NOT be embedded in Values —
// `dispatch` re-reads state when it needs to render the text.

/// Activation tokens. Keep these stable; the Lua provider file and any
/// external callers rely on them being shell-safe single words.
const ACT_NOOP: &str = "noop";
const ACT_RUN_UPDATE: &str = "run-update";
const ACT_BLOCKED_UPDATE: &str = "blocked-update-unavailable";
const ACT_BLOCKED_KEYSTONE: &str = "blocked-keystone-unavailable";
const ACT_OPEN_RELEASE: &str = "open-release-page";

/// A URL is considered shell-safe for Walker dispatch if it contains only
/// characters that are always literal under both single-quote and no-quote
/// shell parsing: ASCII letters, digits, and a small set of URL punctuation.
/// GitHub release URLs always satisfy this; anything outside the allowlist
/// falls back to an empty value so the entry is filtered instead of
/// risking a quoting break.
fn url_is_shell_safe(url: &str) -> bool {
    !url.is_empty()
        && url.chars().all(|c| {
            c.is_ascii_alphanumeric()
                || matches!(
                    c,
                    ':' | '/' | '.' | '-' | '_' | '~' | '%' | '?' | '=' | '&' | '#' | '+'
                )
        })
}

fn render_entries_json(state: &MenuState) -> Result<String> {
    let entries: Vec<Value> = match state {
        MenuState::Ok(s) => {
            let current_label = if !s.current_tag.is_empty() {
                s.current_tag.clone()
            } else {
                short(&s.current_rev).to_string()
            };
            let mut entries = vec![serde_json::json!({
                "Text": format!("Current: {}", current_label),
                "Subtext": s.status_summary,
                "Value": ACT_NOOP,
                "Icon": "dialog-information-symbolic",
                "Preview": "ks menu update preview-summary",
                "PreviewType": "command",
            })];
            if url_is_shell_safe(&s.latest_url) {
                entries.push(serde_json::json!({
                    "Text": format!("Latest: {}", s.latest_tag),
                    "Subtext": "GitHub release notes and changelog",
                    "Value": format!("{ACT_OPEN_RELEASE}\t{}", s.latest_url),
                    "Icon": "software-update-available-symbolic",
                    "Preview": "ks menu update preview-release-notes",
                    "PreviewType": "command",
                }));
            }
            if s.update_allowed {
                entries.push(serde_json::json!({
                    "Text": "Update current host",
                    // Don't promise that `ks update` lands the host exactly on
                    // `latest_tag` — it relocks the consumer flake's inputs
                    // and the result may advance past the published release
                    // depending on how the input is configured. Describe the
                    // action, not the target revision.
                    "Subtext": "Run ks update to relock inputs and update this host",
                    "Value": ACT_RUN_UPDATE,
                    "Icon": "system-software-update-symbolic",
                    "Preview": "ks menu update preview-summary",
                    "PreviewType": "command",
                }));
            } else {
                entries.push(serde_json::json!({
                    "Text": "Update unavailable",
                    "Subtext": s.update_reason,
                    "Value": ACT_BLOCKED_UPDATE,
                    "Icon": "dialog-warning-symbolic",
                    "Preview": "ks menu update preview-summary",
                    "PreviewType": "command",
                }));
            }
            entries
        }
        MenuState::Err(e) => vec![serde_json::json!({
            "Text": "Keystone OS unavailable",
            "Subtext": e.error,
            "Value": ACT_BLOCKED_KEYSTONE,
            "Icon": "dialog-warning-symbolic",
            "Preview": "ks menu update preview-summary",
            "PreviewType": "command",
        })],
    };
    serde_json::to_string(&entries).context("failed to serialize entries")
}

// -----------------------------------------------------------------------------
// Dispatch
// -----------------------------------------------------------------------------

fn run_notify_send(summary: &str, body: &str) -> Result<()> {
    // `--` stops notify-send's option parsing so a summary / body that
    // starts with `-` (e.g., a reason string carrying a CLI flag) isn't
    // misread as a flag.
    let status = Command::new("notify-send")
        .args(["--app-name=Keystone", "--", summary, body])
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

/// Start the background update unit via systemd --user. Delegates to
/// `ks run-background` so the systemctl spawn plus error-surface
/// translation lives in one place — the next Walker provider that needs
/// a background-unit trigger can call the same verb instead of
/// re-implementing this function.
///
/// The unit handles approval (pkexec via hyprpolkitagent), logging
/// (journal), and completion notification (OnSuccess/OnFailure ->
/// ks-update-notify@.service).
fn start_update_unit() -> Result<()> {
    crate::cmd::run_background::execute("ks-update.service")
}

/// Look up the current blocker text from fresh state. Called when the user
/// activates a blocked-* token and we need to render a meaningful notification
/// without having embedded the reason in the activation value.
async fn blocked_update_notification(flake: Option<&Path>) -> (String, String) {
    let state = load_state(flake).await;
    match &state {
        MenuState::Ok(s) if !s.update_allowed => (
            "Keystone update unavailable".to_string(),
            if s.update_reason.is_empty() {
                s.status_summary.clone()
            } else {
                s.update_reason.clone()
            },
        ),
        MenuState::Ok(_) => (
            "Keystone update unavailable".to_string(),
            "Status changed since the menu was rendered — open the Update menu to refresh."
                .to_string(),
        ),
        MenuState::Err(e) => ("Keystone OS unavailable".to_string(), e.error.clone()),
    }
}

async fn blocked_keystone_notification(flake: Option<&Path>) -> (String, String) {
    let state = load_state(flake).await;
    match &state {
        MenuState::Err(e) => ("Keystone OS unavailable".to_string(), e.error.clone()),
        MenuState::Ok(_) => (
            "Keystone OS unavailable".to_string(),
            "Status recovered — reopen the Update menu to refresh.".to_string(),
        ),
    }
}

async fn dispatch(value: &str, flake: Option<&Path>) -> Result<()> {
    // Activation values are restricted to a small set of stable tokens
    // (see the Activation values section above). `open-release-page` is the
    // only action that carries a payload, and its payload is a URL that has
    // already passed `url_is_shell_safe` at entries-render time.
    let mut parts = value.splitn(2, '\t');
    let action = parts.next().unwrap_or("");
    let payload = parts.next().unwrap_or("");

    match action {
        "" | ACT_NOOP => Ok(()),
        ACT_BLOCKED_UPDATE => {
            let (title, body) = blocked_update_notification(flake).await;
            run_notify_send(&title, &body)
        }
        ACT_BLOCKED_KEYSTONE => {
            let (title, body) = blocked_keystone_notification(flake).await;
            run_notify_send(&title, &body)
        }
        ACT_OPEN_RELEASE => {
            if !url_is_shell_safe(payload) {
                anyhow::bail!("open-release-page payload failed safety check");
            }
            xdg_open_detached(payload)
        }
        ACT_RUN_UPDATE => {
            // Close the TOCTOU window between entries-render and click: if
            // the user dirtied the tree after opening the menu, refuse
            // before firing the polkit popup (otherwise the approval
            // round-trip ends with `ks update` failing — strictly worse
            // UX than refusing up front with the same reason).
            match evaluate_local_gate(flake) {
                Ok(()) => {
                    // If `systemctl --user start` itself fails (unit not
                    // loaded, user bus unavailable, systemctl not on PATH),
                    // the error propagates out of `dispatch` → Walker. But
                    // Walker doesn't surface stderr to the user, so this
                    // would be a silent failure. Catch and surface via
                    // notify-send with a pointer at the journal so the user
                    // has something actionable.
                    if let Err(err) = start_update_unit() {
                        run_notify_send(
                            "Keystone update failed to start",
                            &format!("{err}\n\nSee journalctl --user -u ks-update.service -b"),
                        )
                    } else {
                        Ok(())
                    }
                }
                Err(reason) => run_notify_send("Keystone update unavailable", &reason),
            }
        }
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
        UpdateMenuCommand::Dispatch { value } => dispatch(&value, flake).await,
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
    fn parse_release_tag_accepts_plain_semver() {
        assert_eq!(parse_release_tag("v0.8.0"), Some((0, 8, 0)));
        assert_eq!(parse_release_tag("v1.2.3"), Some((1, 2, 3)));
        assert_eq!(parse_release_tag("v10.20.300"), Some((10, 20, 300)));
    }

    #[test]
    fn parse_release_tag_rejects_prereleases_and_metadata() {
        // Pre-releases and build metadata must not be treated as release
        // tags — they'd spuriously flag the menu as "behind" against a
        // stable release that doesn't yet exist.
        assert_eq!(parse_release_tag("v1.2.3-rc1"), None);
        assert_eq!(parse_release_tag("v1.2.3+build.42"), None);
        assert_eq!(parse_release_tag("v1.2.3.4"), None);
    }

    #[test]
    fn parse_release_tag_rejects_non_release_names() {
        assert_eq!(parse_release_tag("prod"), None);
        assert_eq!(parse_release_tag("release-candidate"), None);
        assert_eq!(parse_release_tag(""), None);
        assert_eq!(parse_release_tag("v"), None);
        assert_eq!(parse_release_tag("v1.2"), None);
        assert_eq!(parse_release_tag("1.2.3"), None); // no leading 'v'
        assert_eq!(parse_release_tag("vAbC.1.2"), None);
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
        assert_eq!(arr[2]["Value"], ACT_RUN_UPDATE);
        assert!(
            arr[1]["Value"]
                .as_str()
                .unwrap()
                .starts_with(&format!("{ACT_OPEN_RELEASE}\t")),
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
        // The Value MUST be a stable token — blocker text is rendered at
        // dispatch time by re-reading state (see the `Activation values`
        // block). Embedding free-form text here would break Lua's single-
        // quoted shell wrapping when the text contains a quote.
        assert_eq!(blocked["Value"], ACT_BLOCKED_UPDATE);
        assert_eq!(
            blocked["Subtext"],
            "The active system flake has uncommitted changes."
        );
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
        assert_eq!(arr[0]["Value"], ACT_BLOCKED_KEYSTONE);
    }

    #[test]
    fn entries_skip_release_row_when_url_is_unsafe() {
        // A release URL with a shell metachar (e.g. a single quote from a
        // hypothetical GitHub glitch) must not be embedded into the Value —
        // render_entries_json should drop that entry rather than risk
        // breaking Lua's single-quoted Action.
        let mut fixture = ok_fixture();
        fixture.latest_url = "https://github.com/owner/repo/releases/tag/v0'8".into();
        let state = MenuState::Ok(fixture);
        let rendered = render_entries_json(&state).unwrap();
        let parsed: Value = serde_json::from_str(&rendered).unwrap();
        let arr = parsed.as_array().unwrap();
        // Current + Update entries remain, but the Latest (release-page)
        // entry is filtered because the URL failed the safety check.
        assert_eq!(arr.len(), 2);
        assert_eq!(arr[0]["Text"], "Current: v0.7.0");
        assert_eq!(arr[1]["Value"], ACT_RUN_UPDATE);
    }

    #[test]
    fn url_is_shell_safe_accepts_real_release_urls() {
        assert!(url_is_shell_safe(
            "https://github.com/ncrmro/keystone/releases/tag/v0.8.0"
        ));
        assert!(url_is_shell_safe(
            "https://github.com/owner/repo/releases/tag/v1.2.3-rc1+build.42"
        ));
    }

    #[test]
    fn url_is_shell_safe_rejects_quote_and_space() {
        assert!(!url_is_shell_safe("https://github.com/owner/repo/tag/v0'8"));
        assert!(!url_is_shell_safe("https://github.com/a b"));
        assert!(!url_is_shell_safe(""));
        assert!(!url_is_shell_safe("https://github.com/owner/repo\n"));
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

    fn parse_lock(raw: &str) -> FlakeLock {
        serde_json::from_str(raw).expect("test fixture must be valid flake.lock JSON")
    }

    #[test]
    fn find_keystone_input_walks_root_inputs_and_ignores_transitive() {
        // Simulates a consumer flake whose direct input `keystone` is the
        // real ncrmro/keystone pin, while `other/keystone-fork` is an
        // unrelated node that *also* has original.owner=ncrmro repo=keystone
        // (as could happen with a transitive dep that pins the same repo).
        let raw = r#"{
            "root": "root",
            "version": 7,
            "nodes": {
                "root": {
                    "inputs": {
                        "keystone": "keystone",
                        "nixpkgs": "nixpkgs"
                    }
                },
                "keystone": {
                    "locked": {"type": "github", "rev": "aaaaaaaa"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                },
                "transitive_keystone": {
                    "locked": {"type": "github", "rev": "ffffffff"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                },
                "nixpkgs": {
                    "locked": {"type": "github", "rev": "cccccccc"},
                    "original": {"type": "github", "owner": "NixOS", "repo": "nixpkgs"}
                }
            }
        }"#;
        let lock = parse_lock(raw);
        let (name, node) = find_keystone_input(&lock).expect("should find exactly one root match");
        assert_eq!(name, "keystone");
        assert_eq!(
            node.locked.as_ref().unwrap().rev.as_deref(),
            Some("aaaaaaaa")
        );
    }

    #[test]
    fn find_keystone_input_errors_when_no_root_input_matches() {
        // Root declares only a nixpkgs input; the keystone node exists only
        // as a transitive dep. We must not silently return it.
        let raw = r#"{
            "root": "root",
            "version": 7,
            "nodes": {
                "root": {"inputs": {"nixpkgs": "nixpkgs"}},
                "transitive_keystone": {
                    "locked": {"type": "github", "rev": "ffffffff"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                },
                "nixpkgs": {
                    "locked": {"type": "github", "rev": "cccccccc"},
                    "original": {"type": "github", "owner": "NixOS", "repo": "nixpkgs"}
                }
            }
        }"#;
        let lock = parse_lock(raw);
        let err = find_keystone_input(&lock).unwrap_err();
        assert!(err.to_string().contains("no root input pins"), "got: {err}");
    }

    #[test]
    fn find_keystone_input_errors_when_multiple_root_inputs_match() {
        // Pathological but possible: the user declared two direct inputs
        // both pinning ncrmro/keystone under different names. We must
        // refuse rather than pick one arbitrarily.
        let raw = r#"{
            "root": "root",
            "version": 7,
            "nodes": {
                "root": {
                    "inputs": {
                        "keystone": "keystone",
                        "keystone_alt": "keystone_alt"
                    }
                },
                "keystone": {
                    "locked": {"type": "github", "rev": "aaaaaaaa"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                },
                "keystone_alt": {
                    "locked": {"type": "github", "rev": "bbbbbbbb"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                }
            }
        }"#;
        let lock = parse_lock(raw);
        let err = find_keystone_input(&lock).unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("found 2 root inputs"), "got: {msg}");
    }

    #[test]
    fn find_keystone_input_skips_follows_inputs() {
        // A `follows` input appears as an array value in root.inputs.
        // That path cannot be a direct GitHub source, so we must skip it
        // when looking for the keystone pin.
        let raw = r#"{
            "root": "root",
            "version": 7,
            "nodes": {
                "root": {
                    "inputs": {
                        "keystone": "keystone",
                        "nixpkgs": ["keystone", "nixpkgs"]
                    }
                },
                "keystone": {
                    "locked": {"type": "github", "rev": "aaaaaaaa"},
                    "original": {"type": "github", "owner": "ncrmro", "repo": "keystone"}
                }
            }
        }"#;
        let lock = parse_lock(raw);
        let (name, _) = find_keystone_input(&lock).expect("should resolve");
        assert_eq!(name, "keystone");
    }

    #[tokio::test]
    async fn dispatch_rejects_unknown_actions() {
        let err = dispatch("mystery-action", None).await.unwrap_err();
        assert!(
            err.to_string().contains("unknown update menu action"),
            "got: {err}"
        );
    }

    #[tokio::test]
    async fn dispatch_noop_is_ok() {
        dispatch("", None).await.unwrap();
        dispatch("noop", None).await.unwrap();
    }

    #[test]
    fn evaluate_local_gate_rejects_missing_flake() {
        // With a guaranteed-nonexistent flake override, the gate must
        // refuse rather than silently pretend local preconditions are
        // met. Exact message is user-facing copy; keep the test loose
        // on wording and strict on rejection.
        let err = evaluate_local_gate(Some(Path::new("/nonexistent/path/used/only/in/unit/tests")))
            .unwrap_err();
        assert!(!err.is_empty(), "gate must return a non-empty reason");
    }

    #[tokio::test]
    async fn dispatch_rejects_unsafe_open_release_payload() {
        // Defense in depth: even if entries were tampered with, dispatch
        // must refuse to hand an unsafe URL to xdg-open.
        let err = dispatch(
            &format!("{ACT_OPEN_RELEASE}\thttps://example.com/a'b"),
            None,
        )
        .await
        .unwrap_err();
        assert!(
            err.to_string().contains("failed safety check"),
            "got: {err}"
        );
    }
}
