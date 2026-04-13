//! `ks notifications` — unified notification fetch with source-level read tracking.
//!
//! Replaces shell-script fetchers (fetch-email-source, fetch-github-sources) with
//! a single Rust subcommand that only returns unseen items and supports marking them
//! as read at the source after successful ingest (ISSUE-REQ-1 through ISSUE-REQ-12).

use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};
use tokio::process::Command;

/// State directory for notification manifests.
fn state_dir() -> PathBuf {
    let base = std::env::var("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            home::home_dir()
                .unwrap_or_else(|| PathBuf::from("/tmp"))
                .join(".local/state")
        });
    base.join("ks/notifications")
}

// ── CLI definitions ────────────────────────────────────────────────────

#[derive(Args)]
pub struct NotificationsArgs {
    #[command(subcommand)]
    pub command: Option<NotificationsCommand>,

    /// Output as JSON instead of human-readable table.
    #[arg(long, global = true)]
    pub json: bool,
}

#[derive(Subcommand)]
pub enum NotificationsCommand {
    /// Fetch unseen notifications, output JSON (machine-readable).
    Fetch {
        /// Write a manifest file for later ack.
        #[arg(long)]
        manifest: bool,

        /// Only fetch from specific sources (comma-separated: email,github).
        #[arg(long)]
        sources: Option<String>,
    },

    /// Mark items in a manifest as read at their source.
    Ack {
        /// Path to the manifest file produced by `fetch --manifest`.
        manifest: PathBuf,
    },

    /// Show configured sources and connection status.
    Sources,
}

// ── Data types ─────────────────────────────────────────────────────────

/// A single source entry in the sources.json array consumed by the task loop.
#[derive(Debug, Serialize, Deserialize)]
pub struct SourceEntry {
    pub source: String,
    pub data: serde_json::Value,
}

/// Manifest tracking fetched item IDs per source for later ack.
#[derive(Debug, Serialize, Deserialize)]
pub struct Manifest {
    pub created_at: String,
    pub sources: Vec<ManifestSource>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ManifestSource {
    pub source: String,
    pub ids: Vec<String>,
}

/// Email envelope from himalaya JSON output.
#[derive(Debug, Serialize, Deserialize)]
struct EmailEnvelope {
    id: String,
    #[serde(flatten)]
    rest: serde_json::Map<String, serde_json::Value>,
}

// ── Entrypoint ─────────────────────────────────────────────────────────

pub async fn execute(args: &NotificationsArgs) -> Result<()> {
    match &args.command {
        Some(NotificationsCommand::Fetch { manifest, sources }) => {
            let filter: Option<Vec<&str>> = sources
                .as_ref()
                .map(|s| s.split(',').map(|s| s.trim()).collect());
            execute_fetch(*manifest, filter.as_deref(), args.json).await
        }
        Some(NotificationsCommand::Ack { manifest }) => execute_ack(manifest).await,
        Some(NotificationsCommand::Sources) => execute_sources(args.json).await,
        None => execute_list(args.json).await,
    }
}

// ── Fetch ──────────────────────────────────────────────────────────────

async fn execute_fetch(
    write_manifest: bool,
    source_filter: Option<&[&str]>,
    _json_output: bool,
) -> Result<()> {
    let mut entries: Vec<SourceEntry> = Vec::new();
    let mut manifest_sources: Vec<ManifestSource> = Vec::new();

    let should_fetch = |name: &str| -> bool {
        source_filter
            .map(|f| f.contains(&name))
            .unwrap_or(true)
    };

    // ISSUE-REQ-2: Email — fetch only UNSEEN via himalaya filter
    if should_fetch("email") {
        match fetch_email().await {
            Ok((entry, ids)) => {
                if !ids.is_empty() {
                    manifest_sources.push(ManifestSource {
                        source: "email".to_string(),
                        ids,
                    });
                }
                if entry.data != serde_json::Value::Array(vec![]) {
                    entries.push(entry);
                }
            }
            Err(e) => eprintln!("warning: email fetch failed: {e}"),
        }
    }

    // ISSUE-REQ-3: GitHub — fetch only unread (no all=true)
    if should_fetch("github") {
        let username = std::env::var("GITHUB_USERNAME").ok();
        if let Some(ref user) = username {
            match fetch_github(user).await {
                Ok((entry, ids)) => {
                    if !ids.is_empty() {
                        manifest_sources.push(ManifestSource {
                            source: "github".to_string(),
                            ids,
                        });
                    }
                    if entry.data != serde_json::json!({}) {
                        entries.push(entry);
                    }
                }
                Err(e) => eprintln!("warning: github fetch failed: {e}"),
            }
        }
    }

    // ISSUE-REQ-8: Write manifest for later ack
    if write_manifest && !manifest_sources.is_empty() {
        let manifest = Manifest {
            created_at: chrono_now(),
            sources: manifest_sources,
        };
        let dir = state_dir();
        tokio::fs::create_dir_all(&dir).await?;
        let path = dir.join(format!("manifest-{}.json", timestamp_slug()));
        let content = serde_json::to_string_pretty(&manifest)?;
        tokio::fs::write(&path, &content).await?;
        eprintln!("manifest: {}", path.display());
    }

    // ISSUE-REQ-5: Output JSON in sources.json schema
    let output = serde_json::to_string_pretty(&entries)?;
    println!("{output}");

    Ok(())
}

// ── Email source ───────────────────────────────────────────────────────

/// Fetch unseen email envelopes and enrich with bodies.
/// ISSUE-REQ-2: Uses `not flag seen` query to exclude already-read messages.
async fn fetch_email() -> Result<(SourceEntry, Vec<String>)> {
    // Fetch only unseen envelopes
    let output = Command::new("himalaya")
        .args(["envelope", "list", "-o", "json", "-s", "50", "not", "flag", "seen"])
        .output()
        .await
        .context("failed to run himalaya")?;

    if !output.status.success() {
        anyhow::bail!(
            "himalaya envelope list failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    let envelopes: Vec<EmailEnvelope> =
        serde_json::from_slice(&output.stdout).unwrap_or_default();

    let ids: Vec<String> = envelopes.iter().map(|e| e.id.clone()).collect();

    // Enrich each envelope with its body
    let mut enriched = Vec::new();
    for env in &envelopes {
        let body = fetch_email_body(&env.id).await.unwrap_or_default();
        let mut obj = serde_json::Map::new();
        obj.insert("id".to_string(), serde_json::Value::String(env.id.clone()));
        for (k, v) in &env.rest {
            obj.insert(k.clone(), v.clone());
        }
        obj.insert("body".to_string(), serde_json::Value::String(body));
        enriched.push(serde_json::Value::Object(obj));
    }

    Ok((
        SourceEntry {
            source: "email".to_string(),
            data: serde_json::Value::Array(enriched),
        },
        ids,
    ))
}

async fn fetch_email_body(id: &str) -> Result<String> {
    let output = Command::new("himalaya")
        .args(["message", "read", "-p", id])
        .output()
        .await?;

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

// ── GitHub source ──────────────────────────────────────────────────────

/// Fetch unread GitHub notifications and enrich with issue/PR details.
/// ISSUE-REQ-3: Does NOT pass `all=true` — only unread notifications.
async fn fetch_github(username: &str) -> Result<(SourceEntry, Vec<String>)> {
    // Phase 1: Fetch unread notifications (no all=true)
    let output = Command::new("gh")
        .args([
            "api",
            "/notifications?participating=true&per_page=100",
        ])
        .output()
        .await
        .context("failed to run gh api")?;

    if !output.status.success() {
        anyhow::bail!(
            "gh api notifications failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    let raw: Vec<serde_json::Value> =
        serde_json::from_slice(&output.stdout).unwrap_or_default();

    // Collect thread IDs for manifest
    let thread_ids: Vec<String> = raw
        .iter()
        .filter_map(|n| n.get("id").and_then(|v| v.as_str()).map(String::from))
        .collect();

    // Deduplicate by subject URL, keep most recent
    let notifications = dedup_notifications(&raw);

    // Phase 2-4: Enrich (issues, PRs, reviews) — mirrors fetch-github-sources
    let mut issues = Vec::new();
    let mut prs = Vec::new();
    let mut reviews = Vec::new();
    let mut issue_comments = Vec::new();

    for notif in &notifications {
        let subject_type = notif
            .get("subject")
            .and_then(|s| s.get("type"))
            .and_then(|t| t.as_str())
            .unwrap_or("");
        let subject_url = notif
            .get("subject")
            .and_then(|s| s.get("url"))
            .and_then(|u| u.as_str())
            .unwrap_or("");
        let repo = notif
            .get("repository")
            .and_then(|r| r.get("full_name"))
            .and_then(|n| n.as_str())
            .unwrap_or("");
        let reason = notif
            .get("reason")
            .and_then(|r| r.as_str())
            .unwrap_or("");

        if subject_url.is_empty() {
            continue;
        }

        match subject_type {
            "Issue" => {
                if let Ok(issue) = enrich_issue(subject_url, repo, notif).await {
                    if let Some(comment) =
                        enrich_issue_comment(notif, repo, &issue).await
                    {
                        issue_comments.push(comment);
                    }
                    issues.push(issue);
                }
            }
            "PullRequest" if reason == "review_requested" => {
                if let Ok(pr) = enrich_pr(subject_url, repo).await {
                    prs.push(pr);
                }
            }
            "PullRequest" if reason == "author" => {
                if let Ok(mut rev) = enrich_reviews(subject_url, repo, username).await {
                    reviews.append(&mut rev);
                }
            }
            _ => {}
        }
    }

    let data = serde_json::json!({
        "github-issues": issues,
        "github-prs": prs,
        "github-pr-reviews": reviews,
        "github-issue-comments": issue_comments,
    });

    Ok((
        SourceEntry {
            source: "github".to_string(),
            data,
        },
        thread_ids,
    ))
}

fn dedup_notifications(raw: &[serde_json::Value]) -> Vec<serde_json::Value> {
    use std::collections::HashMap;
    let mut seen: HashMap<String, &serde_json::Value> = HashMap::new();

    // Sort by updated_at descending is implicit — we just keep first occurrence
    for notif in raw {
        let subject_url = notif
            .get("subject")
            .and_then(|s| s.get("url"))
            .and_then(|u| u.as_str())
            .unwrap_or("");
        let subject_type = notif
            .get("subject")
            .and_then(|s| s.get("type"))
            .and_then(|t| t.as_str())
            .unwrap_or("");

        if subject_type != "Issue" && subject_type != "PullRequest" {
            continue;
        }

        if !subject_url.is_empty() {
            seen.entry(subject_url.to_string()).or_insert(notif);
        }
    }

    seen.into_values().cloned().collect()
}

async fn enrich_issue(
    subject_url: &str,
    repo: &str,
    _notif: &serde_json::Value,
) -> Result<serde_json::Value> {
    let output = Command::new("gh")
        .args(["api", subject_url])
        .output()
        .await?;

    if !output.status.success() {
        anyhow::bail!("gh api failed for {subject_url}");
    }

    let issue: serde_json::Value = serde_json::from_slice(&output.stdout)?;
    let state = issue.get("state").and_then(|s| s.as_str()).unwrap_or("");
    if state != "open" {
        anyhow::bail!("issue is not open");
    }

    Ok(serde_json::json!({
        "repo": repo,
        "number": issue.get("number"),
        "title": issue.get("title"),
        "url": issue.get("html_url"),
        "assignees": issue.get("assignees").and_then(|a| a.as_array()).map(|arr|
            arr.iter().filter_map(|a| a.get("login").and_then(|l| l.as_str())).collect::<Vec<_>>()
        ).unwrap_or_default(),
        "labels": issue.get("labels").and_then(|l| l.as_array()).map(|arr|
            arr.iter().filter_map(|l| l.get("name").and_then(|n| n.as_str())).collect::<Vec<_>>()
        ).unwrap_or_default(),
        "created_at": issue.get("created_at"),
    }))
}

async fn enrich_issue_comment(
    notif: &serde_json::Value,
    repo: &str,
    issue: &serde_json::Value,
) -> Option<serde_json::Value> {
    let comment_url = notif
        .get("subject")
        .and_then(|s| s.get("latest_comment_url"))
        .and_then(|u| u.as_str())?;

    if comment_url == "null" || comment_url.is_empty() {
        return None;
    }

    let output = Command::new("gh")
        .args(["api", comment_url])
        .output()
        .await
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let comment: serde_json::Value = serde_json::from_slice(&output.stdout).ok()?;
    let number = issue.get("number");

    Some(serde_json::json!({
        "repo": repo,
        "issue_number": number,
        "comment_id": comment.get("id"),
        "author": comment.get("user").and_then(|u| u.get("login")),
        "body": comment.get("body"),
        "created_at": comment.get("created_at"),
    }))
}

async fn enrich_pr(subject_url: &str, repo: &str) -> Result<serde_json::Value> {
    let output = Command::new("gh")
        .args(["api", subject_url])
        .output()
        .await?;

    if !output.status.success() {
        anyhow::bail!("gh api failed for {subject_url}");
    }

    let pr: serde_json::Value = serde_json::from_slice(&output.stdout)?;

    Ok(serde_json::json!({
        "repo": repo,
        "number": pr.get("number"),
        "title": pr.get("title"),
        "url": pr.get("html_url"),
        "author": pr.get("user").and_then(|u| u.get("login")),
        "created_at": pr.get("created_at"),
    }))
}

async fn enrich_reviews(
    subject_url: &str,
    repo: &str,
    username: &str,
) -> Result<Vec<serde_json::Value>> {
    let output = Command::new("gh")
        .args(["api", subject_url])
        .output()
        .await?;

    if !output.status.success() {
        anyhow::bail!("gh api failed for {subject_url}");
    }

    let pr: serde_json::Value = serde_json::from_slice(&output.stdout)?;
    let pr_number = pr.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
    let pr_title = pr.get("title").and_then(|t| t.as_str()).unwrap_or("");
    let pr_url = pr.get("html_url").and_then(|u| u.as_str()).unwrap_or("");
    let pr_branch = pr
        .get("head")
        .and_then(|h| h.get("ref"))
        .and_then(|r| r.as_str())
        .unwrap_or("");

    let reviews_url = format!("repos/{repo}/pulls/{pr_number}/reviews");
    let output = Command::new("gh")
        .args(["api", &reviews_url])
        .output()
        .await?;

    let reviews_raw: Vec<serde_json::Value> = if output.status.success() {
        serde_json::from_slice(&output.stdout).unwrap_or_default()
    } else {
        return Ok(vec![]);
    };

    let mut results = Vec::new();

    for review in &reviews_raw {
        let reviewer = review
            .get("user")
            .and_then(|u| u.get("login"))
            .and_then(|l| l.as_str())
            .unwrap_or("");
        let state = review
            .get("state")
            .and_then(|s| s.as_str())
            .unwrap_or("");

        if reviewer == username {
            continue;
        }
        if state != "CHANGES_REQUESTED" && state != "COMMENTED" {
            continue;
        }

        let review_id = review.get("id").and_then(|i| i.as_u64()).unwrap_or(0);

        // Fetch review comments
        let comments_url =
            format!("repos/{repo}/pulls/{pr_number}/reviews/{review_id}/comments");
        let comments = match Command::new("gh")
            .args(["api", &comments_url])
            .output()
            .await
        {
            Ok(out) if out.status.success() => {
                let raw: Vec<serde_json::Value> =
                    serde_json::from_slice(&out.stdout).unwrap_or_default();
                raw.iter()
                    .map(|c| {
                        serde_json::json!({
                            "id": c.get("id"),
                            "path": c.get("path"),
                            "body": c.get("body"),
                        })
                    })
                    .collect::<Vec<_>>()
            }
            _ => vec![],
        };

        results.push(serde_json::json!({
            "repo": repo,
            "pr_number": pr_number,
            "pr_title": pr_title,
            "pr_url": pr_url,
            "pr_branch": pr_branch,
            "review_id": review_id,
            "reviewer": reviewer,
            "review_state": state,
            "comments": comments,
        }));
    }

    Ok(results)
}

// ── Ack ────────────────────────────────────────────────────────────────

/// ISSUE-REQ-6: Mark items as read at the source.
async fn execute_ack(manifest_path: &PathBuf) -> Result<()> {
    let content = tokio::fs::read_to_string(manifest_path)
        .await
        .context("failed to read manifest")?;
    let manifest: Manifest = serde_json::from_str(&content)?;

    for source in &manifest.sources {
        match source.source.as_str() {
            "email" => ack_email(&source.ids).await?,
            "github" => ack_github(&source.ids).await?,
            other => eprintln!("warning: unknown source in manifest: {other}"),
        }
    }

    // Delete manifest after successful ack
    tokio::fs::remove_file(manifest_path).await.ok();
    eprintln!("ack complete, manifest removed");

    Ok(())
}

/// Mark emails as seen via himalaya flag add.
async fn ack_email(ids: &[String]) -> Result<()> {
    for id in ids {
        let status = Command::new("himalaya")
            .args(["flag", "add", id, "Seen"])
            .status()
            .await?;

        if !status.success() {
            eprintln!("warning: failed to mark email {id} as seen");
        }
    }
    Ok(())
}

/// Mark GitHub notification threads as read.
async fn ack_github(thread_ids: &[String]) -> Result<()> {
    for id in thread_ids {
        let url = format!("/notifications/threads/{id}");
        let status = Command::new("gh")
            .args(["api", "-X", "PATCH", &url])
            .status()
            .await?;

        if !status.success() {
            eprintln!("warning: failed to mark GitHub thread {id} as read");
        }
    }
    Ok(())
}

// ── Human-readable list ────────────────────────────────────────────────

/// ISSUE-REQ-11: Display human-readable summary grouped by source.
async fn execute_list(json: bool) -> Result<()> {
    let entries = fetch_all_sources().await;

    if json {
        println!("{}", serde_json::to_string_pretty(&entries)?);
        return Ok(());
    }

    if entries.is_empty() {
        println!("No unread notifications.");
        return Ok(());
    }

    for entry in &entries {
        println!("\n── {} ──", entry.source.to_uppercase());

        match entry.source.as_str() {
            "email" => {
                if let Some(arr) = entry.data.as_array() {
                    for item in arr {
                        let from = item.get("from").and_then(|f| f.as_str()).unwrap_or("unknown");
                        let subject = item.get("subject").and_then(|s| s.as_str()).unwrap_or("(no subject)");
                        let id = item.get("id").and_then(|i| i.as_str()).unwrap_or("");
                        println!("  [{id}] {from}: {subject}");
                    }
                }
            }
            "github" => {
                if let Some(issues) = entry.data.get("github-issues").and_then(|v| v.as_array()) {
                    if !issues.is_empty() {
                        println!("  Issues:");
                        for issue in issues {
                            let repo = issue.get("repo").and_then(|r| r.as_str()).unwrap_or("");
                            let number = issue.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
                            let title = issue.get("title").and_then(|t| t.as_str()).unwrap_or("");
                            println!("    {repo}#{number}: {title}");
                        }
                    }
                }
                if let Some(prs) = entry.data.get("github-prs").and_then(|v| v.as_array()) {
                    if !prs.is_empty() {
                        println!("  PRs requesting review:");
                        for pr in prs {
                            let repo = pr.get("repo").and_then(|r| r.as_str()).unwrap_or("");
                            let number = pr.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
                            let title = pr.get("title").and_then(|t| t.as_str()).unwrap_or("");
                            println!("    {repo}#{number}: {title}");
                        }
                    }
                }
                if let Some(reviews) = entry.data.get("github-pr-reviews").and_then(|v| v.as_array()) {
                    if !reviews.is_empty() {
                        println!("  Reviews on your PRs:");
                        for rev in reviews {
                            let repo = rev.get("repo").and_then(|r| r.as_str()).unwrap_or("");
                            let pr_number = rev.get("pr_number").and_then(|n| n.as_u64()).unwrap_or(0);
                            let reviewer = rev.get("reviewer").and_then(|r| r.as_str()).unwrap_or("");
                            let state = rev.get("review_state").and_then(|s| s.as_str()).unwrap_or("");
                            println!("    {repo}#{pr_number}: {reviewer} ({state})");
                        }
                    }
                }
            }
            _ => {
                println!("  {}", serde_json::to_string_pretty(&entry.data)?);
            }
        }
    }

    Ok(())
}

/// Fetch from all available sources (used by both list and fetch).
async fn fetch_all_sources() -> Vec<SourceEntry> {
    let mut entries = Vec::new();

    if let Ok((entry, _)) = fetch_email().await {
        if entry.data != serde_json::Value::Array(vec![]) {
            entries.push(entry);
        }
    }

    let gh_user = std::env::var("GITHUB_USERNAME").ok().or_else(|| {
        std::process::Command::new("gh")
            .args(["api", "/user", "--jq", ".login"])
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .filter(|s| !s.is_empty())
    });
    if let Some(ref user) = gh_user {
        if let Ok((entry, _)) = fetch_github(user).await {
            if entry.data != serde_json::json!({}) {
                entries.push(entry);
            }
        }
    }

    entries
}

// ── Sources status ─────────────────────────────────────────────────────

/// ISSUE-REQ-12: Show configured sources and connection status.
async fn execute_sources(json: bool) -> Result<()> {
    let mut sources = Vec::new();

    // Check email (himalaya)
    let email_ok = Command::new("himalaya")
        .args(["account", "list", "-o", "json"])
        .output()
        .await
        .map(|o| o.status.success())
        .unwrap_or(false);

    sources.push(serde_json::json!({
        "source": "email",
        "tool": "himalaya",
        "available": email_ok,
    }));

    // Check GitHub (gh)
    let gh_ok = Command::new("gh")
        .args(["auth", "status"])
        .output()
        .await
        .map(|o| o.status.success())
        .unwrap_or(false);

    sources.push(serde_json::json!({
        "source": "github",
        "tool": "gh",
        "available": gh_ok,
        "username": std::env::var("GITHUB_USERNAME").unwrap_or_default(),
    }));

    if json {
        println!("{}", serde_json::to_string_pretty(&sources)?);
    } else {
        println!("Notification sources:\n");
        for s in &sources {
            let name = s.get("source").and_then(|n| n.as_str()).unwrap_or("");
            let tool = s.get("tool").and_then(|t| t.as_str()).unwrap_or("");
            let ok = s.get("available").and_then(|a| a.as_bool()).unwrap_or(false);
            let status = if ok { "connected" } else { "unavailable" };
            println!("  {name:<10} ({tool}) — {status}");
        }
    }

    Ok(())
}

// ── Helpers ────────────────────────────────────────────────────────────

fn chrono_now() -> String {
    // Use system time formatted as ISO 8601
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    format!("{now}")
}

fn timestamp_slug() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    format!("{now}")
}
