//! `ks tasks` — unified task management for humans and agents.
//!
//! Manages TASKS.yaml: add, complete, list, prune, and AI-powered ingest
//! and prioritization. Tasks are created from `ks notifications` sources
//! or manually. Prioritization proposals include rationale and can be
//! reviewed before acceptance.

use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};

// ── CLI definition ────────────────────────────────────────────────────

#[derive(Args)]
pub struct TasksArgs {
    #[command(subcommand)]
    pub command: Option<TasksCommand>,

    /// Output as JSON instead of human-readable table.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand)]
pub enum TasksCommand {
    /// Add a new task.
    Add {
        /// Task description.
        description: String,

        /// Task name (kebab-case). Auto-generated from description if omitted.
        #[arg(long)]
        name: Option<String>,

        /// Source type (email, github-issue, github-pr, manual).
        #[arg(long, default_value = "manual")]
        source: String,

        /// Source reference for deduplication.
        #[arg(long)]
        source_ref: Option<String>,

        /// Associated project.
        #[arg(long)]
        project: Option<String>,
    },

    /// Mark a task as completed.
    Done {
        /// Task name to complete.
        name: String,
    },

    /// Mark a task as blocked.
    Block {
        /// Task name to block.
        name: String,

        /// Reason for blocking.
        #[arg(long)]
        reason: Option<String>,
    },

    /// Remove completed tasks older than a threshold.
    Prune {
        /// Remove all completed tasks (default: only those older than 30 days).
        #[arg(long)]
        all: bool,
    },

    /// Show prioritization proposal from last `prioritize` run.
    Proposal {
        /// Accept the current proposal and apply the new ordering.
        #[arg(long)]
        accept: bool,
    },
}

// ── Data model ────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskFile {
    pub tasks: Vec<Task>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub name: String,
    pub description: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub project: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_ref: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workflow: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub needs: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub blocked_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub started_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<String>,
}

/// A prioritization proposal from the AI, with rationale per task.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrioritizationProposal {
    pub proposed_at: String,
    pub items: Vec<ProposalItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProposalItem {
    pub rank: u32,
    pub name: String,
    pub rationale: String,
}

// ── Paths ─────────────────────────────────────────────────────────────

fn tasks_file_path() -> PathBuf {
    // TASKS.yaml lives in $HOME for agents, or current dir for humans
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let home_path = PathBuf::from(&home).join("TASKS.yaml");
    if home_path.exists() {
        return home_path;
    }
    // Fall back to current directory
    let cwd_path = PathBuf::from("TASKS.yaml");
    if cwd_path.exists() {
        return cwd_path;
    }
    // Default to home
    home_path
}

fn proposal_path() -> PathBuf {
    let state_dir = std::env::var("XDG_STATE_HOME")
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
            format!("{home}/.local/state")
        });
    PathBuf::from(state_dir).join("ks/tasks/proposal.json")
}

// ── File I/O ──────────────────────────────────────────────────────────

fn load_tasks() -> Result<TaskFile> {
    let path = tasks_file_path();
    if !path.exists() {
        return Ok(TaskFile { tasks: vec![] });
    }
    let content = std::fs::read_to_string(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let tasks: TaskFile = serde_yaml::from_str(&content)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(tasks)
}

fn save_tasks(task_file: &TaskFile) -> Result<()> {
    let path = tasks_file_path();
    let content = serde_yaml::to_string(task_file)?;
    // Write with --- header for clean YAML
    let output = format!("---\n{content}");
    std::fs::write(&path, output)
        .with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

// ── Entry point ───────────────────────────────────────────────────────

pub async fn execute(args: &TasksArgs) -> Result<()> {
    match &args.command {
        None => execute_list(args.json),
        Some(TasksCommand::Add {
            description,
            name,
            source,
            source_ref,
            project,
        }) => execute_add(description, name.as_deref(), source, source_ref.as_deref(), project.as_deref()),
        Some(TasksCommand::Done { name }) => execute_done(name),
        Some(TasksCommand::Block { name, reason }) => execute_block(name, reason.as_deref()),
        Some(TasksCommand::Prune { all }) => execute_prune(*all),
        Some(TasksCommand::Proposal { accept }) => execute_proposal(*accept),
    }
}

// ── List ──────────────────────────────────────────────────────────────

fn execute_list(json: bool) -> Result<()> {
    let task_file = load_tasks()?;

    if json {
        println!("{}", serde_json::to_string_pretty(&task_file.tasks)?);
        return Ok(());
    }

    if task_file.tasks.is_empty() {
        println!("No tasks.");
        return Ok(());
    }

    let pending: Vec<_> = task_file.tasks.iter().filter(|t| t.status == "pending").collect();
    let in_progress: Vec<_> = task_file.tasks.iter().filter(|t| t.status == "in_progress").collect();
    let blocked: Vec<_> = task_file.tasks.iter().filter(|t| t.status == "blocked").collect();
    let completed: Vec<_> = task_file.tasks.iter().filter(|t| t.status == "completed").collect();

    if !in_progress.is_empty() {
        println!("In Progress ({}):", in_progress.len());
        for t in &in_progress {
            print_task(t);
        }
        println!();
    }

    if !pending.is_empty() {
        println!("Pending ({}):", pending.len());
        for t in &pending {
            print_task(t);
        }
        println!();
    }

    if !blocked.is_empty() {
        println!("Blocked ({}):", blocked.len());
        for t in &blocked {
            let reason = t.blocked_reason.as_deref().unwrap_or("");
            println!("  {} — {}", t.name, t.description);
            if !reason.is_empty() {
                println!("    reason: {reason}");
            }
        }
        println!();
    }

    println!("Completed: {}", completed.len());

    Ok(())
}

fn print_task(task: &Task) {
    let project = task.project.as_deref().unwrap_or("");
    let source = task.source.as_deref().unwrap_or("");
    let prefix = if !project.is_empty() {
        format!("[{project}] ")
    } else if !source.is_empty() {
        format!("({source}) ")
    } else {
        String::new()
    };
    println!("  {} {}{}", task.name, prefix, task.description);
}

// ── Add ───────────────────────────────────────────────────────────────

fn execute_add(
    description: &str,
    name: Option<&str>,
    source: &str,
    source_ref: Option<&str>,
    project: Option<&str>,
) -> Result<()> {
    let mut task_file = load_tasks()?;

    let task_name = match name {
        Some(n) => n.to_string(),
        None => slugify(description),
    };

    // Check for duplicate source_ref
    if let Some(ref sref) = source_ref {
        if task_file.tasks.iter().any(|t| t.source_ref.as_deref() == Some(sref)) {
            eprintln!("Task with source_ref '{sref}' already exists, skipping.");
            return Ok(());
        }
    }

    // Check for duplicate name
    if task_file.tasks.iter().any(|t| t.name == task_name) {
        eprintln!("Task '{task_name}' already exists.");
        return Ok(());
    }

    let now = iso_now();
    task_file.tasks.push(Task {
        name: task_name.clone(),
        description: description.to_string(),
        status: "pending".to_string(),
        project: project.map(String::from),
        source: Some(source.to_string()),
        source_ref: source_ref.map(String::from),
        model: None,
        workflow: None,
        needs: None,
        blocked_reason: None,
        created_at: Some(now),
        started_at: None,
        completed_at: None,
    });

    save_tasks(&task_file)?;
    println!("Added: {task_name}");
    Ok(())
}

// ── Done ──────────────────────────────────────────────────────────────

fn execute_done(name: &str) -> Result<()> {
    let mut task_file = load_tasks()?;

    let task = task_file.tasks.iter_mut().find(|t| t.name == name);
    match task {
        Some(t) => {
            t.status = "completed".to_string();
            t.completed_at = Some(iso_now());
            save_tasks(&task_file)?;
            println!("Completed: {name}");
        }
        None => {
            eprintln!("Task '{name}' not found.");
        }
    }
    Ok(())
}

// ── Block ─────────────────────────────────────────────────────────────

fn execute_block(name: &str, reason: Option<&str>) -> Result<()> {
    let mut task_file = load_tasks()?;

    let task = task_file.tasks.iter_mut().find(|t| t.name == name);
    match task {
        Some(t) => {
            t.status = "blocked".to_string();
            t.blocked_reason = reason.map(String::from);
            save_tasks(&task_file)?;
            println!("Blocked: {name}");
        }
        None => {
            eprintln!("Task '{name}' not found.");
        }
    }
    Ok(())
}

// ── Prune ─────────────────────────────────────────────────────────────

fn execute_prune(all: bool) -> Result<()> {
    let mut task_file = load_tasks()?;
    let before = task_file.tasks.len();

    if all {
        task_file.tasks.retain(|t| t.status != "completed");
    } else {
        // Keep completed tasks from the last 30 days
        let cutoff = chrono_days_ago(30);
        task_file.tasks.retain(|t| {
            if t.status != "completed" {
                return true;
            }
            // Keep if no completed_at or if within cutoff
            match &t.completed_at {
                Some(ts) => ts.as_str() >= cutoff.as_str(),
                None => true,
            }
        });
    }

    let removed = before - task_file.tasks.len();
    save_tasks(&task_file)?;
    println!("Pruned {removed} completed tasks ({} remaining).", task_file.tasks.len());
    Ok(())
}

// ── Proposal ──────────────────────────────────────────────────────────

fn execute_proposal(accept: bool) -> Result<()> {
    let path = proposal_path();

    if accept {
        if !path.exists() {
            eprintln!("No proposal to accept. Run prioritization first.");
            return Ok(());
        }

        let content = std::fs::read_to_string(&path)?;
        let proposal: PrioritizationProposal = serde_json::from_str(&content)?;

        let mut task_file = load_tasks()?;

        // Reorder pending tasks according to proposal
        let mut pending: Vec<Task> = task_file.tasks.drain(..).collect();
        let mut non_pending: Vec<Task> = Vec::new();
        let mut reordered_pending: Vec<Task> = Vec::new();

        // Separate pending from non-pending
        let mut pending_tasks: Vec<Task> = Vec::new();
        for task in pending.drain(..) {
            if task.status == "pending" {
                pending_tasks.push(task);
            } else {
                non_pending.push(task);
            }
        }

        // Reorder pending by proposal rank
        for item in &proposal.items {
            if let Some(idx) = pending_tasks.iter().position(|t| t.name == item.name) {
                reordered_pending.push(pending_tasks.remove(idx));
            }
        }
        // Append any pending tasks not in the proposal
        reordered_pending.append(&mut pending_tasks);

        // Reconstruct: in_progress first, then reordered pending, then blocked, then completed
        task_file.tasks = non_pending
            .iter()
            .filter(|t| t.status == "in_progress")
            .cloned()
            .chain(reordered_pending.into_iter())
            .chain(non_pending.iter().filter(|t| t.status == "blocked").cloned())
            .chain(non_pending.iter().filter(|t| t.status == "completed").cloned())
            .collect();

        save_tasks(&task_file)?;
        std::fs::remove_file(&path).ok();
        println!("Accepted prioritization. {} pending tasks reordered.", proposal.items.len());
        return Ok(());
    }

    // Show current proposal
    if !path.exists() {
        println!("No pending proposal.");
        return Ok(());
    }

    let content = std::fs::read_to_string(&path)?;
    let proposal: PrioritizationProposal = serde_json::from_str(&content)?;

    println!("Prioritization proposal ({})\n", proposal.proposed_at);
    for item in &proposal.items {
        println!("  {}. {} — {}", item.rank, item.name, item.rationale);
    }
    println!("\nAccept with: ks tasks proposal --accept");

    Ok(())
}

// ── Helpers ───────────────────────────────────────────────────────────

fn slugify(text: &str) -> String {
    text.to_lowercase()
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("-")
        .chars()
        .take(60)
        .collect()
}

fn iso_now() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    // Format as ISO 8601 (approximate — no chrono dependency)
    let secs_per_day = 86400u64;
    let days = now / secs_per_day;
    let time_of_day = now % secs_per_day;
    let hours = time_of_day / 3600;
    let minutes = (time_of_day % 3600) / 60;
    let seconds = time_of_day % 60;

    // Days since epoch to Y-M-D (simplified Gregorian)
    let (year, month, day) = epoch_days_to_ymd(days);
    format!("{year:04}-{month:02}-{day:02}T{hours:02}:{minutes:02}:{seconds:02}Z")
}

fn epoch_days_to_ymd(days: u64) -> (u64, u64, u64) {
    // Algorithm from https://howardhinnant.github.io/date_algorithms.html
    let z = days + 719468;
    let era = z / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

fn chrono_days_ago(days: u64) -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let past = now.saturating_sub(days * 86400);
    let (year, month, day) = epoch_days_to_ymd(past / 86400);
    format!("{year:04}-{month:02}-{day:02}")
}
