//! `ks project` — project management with provider overrides and detection.
//!
//! Projects map repos to named entities with priority and per-project
//! provider/model configuration. Detection resolves notifications to
//! projects deterministically (repo match) or heuristically (subject match).

use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};

// ── CLI definition ────────────────────────────────────────────────────

#[derive(Args)]
pub struct ProjectArgs {
    #[command(subcommand)]
    pub command: Option<ProjectCommand>,

    /// Output as JSON.
    #[arg(long)]
    pub json: bool,
}

#[derive(Subcommand)]
pub enum ProjectCommand {
    /// Show full details for a project.
    Show {
        /// Project slug.
        slug: String,
    },

    /// Add a new project.
    Add {
        /// Project slug (kebab-case).
        slug: String,

        /// Display name.
        #[arg(long)]
        name: Option<String>,

        /// Associated repo (repeatable, "owner/repo" format).
        #[arg(long, action = clap::ArgAction::Append)]
        repo: Vec<String>,

        /// Priority (lower = higher priority).
        #[arg(long)]
        priority: Option<u32>,
    },

    /// Remove a project.
    Remove {
        /// Project slug.
        slug: String,
    },

    /// Detect which project a notification belongs to.
    Detect {
        /// Match by repo ("owner/repo" or full URL).
        #[arg(long)]
        repo: Option<String>,

        /// Match by subject text (heuristic).
        #[arg(long)]
        subject: Option<String>,
    },
}

// ── Data model ────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProjectFile {
    pub projects: Vec<Project>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Project {
    pub slug: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub priority: Option<u32>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub repos: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub sources: Vec<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider: Option<ProjectProvider>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProjectProvider {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
}

/// Detection result with confidence level.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DetectionResult {
    pub slug: Option<String>,
    pub confidence: String, // "exact", "heuristic", "none"
    pub method: String,
}

// ── Paths ─────────────────────────────────────────────────────────────

fn projects_file_path() -> PathBuf {
    if let Ok(p) = std::env::var("KS_PROJECTS_FILE") {
        return PathBuf::from(p);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let home_path = PathBuf::from(&home).join("PROJECTS.yaml");
    if home_path.exists() {
        return home_path;
    }
    let cwd_path = PathBuf::from("PROJECTS.yaml");
    if cwd_path.exists() {
        return cwd_path;
    }
    home_path
}

// ── Core operations ───────────────────────────────────────────────────

pub fn load_projects_from(path: &PathBuf) -> Result<ProjectFile> {
    if !path.exists() {
        return Ok(ProjectFile { projects: vec![] });
    }
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let pf: ProjectFile = serde_yaml::from_str(&content)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(pf)
}

pub fn save_projects_to(pf: &ProjectFile, path: &PathBuf) -> Result<()> {
    let content = serde_yaml::to_string(pf)?;
    let output = format!("---\n{content}");
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).ok();
    }
    std::fs::write(path, output).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

/// Add a project. Returns false if slug already exists.
pub fn add_project(pf: &mut ProjectFile, project: Project) -> bool {
    if pf.projects.iter().any(|p| p.slug == project.slug) {
        return false;
    }
    pf.projects.push(project);
    true
}

/// Remove a project by slug. Returns true if found and removed.
pub fn remove_project(pf: &mut ProjectFile, slug: &str) -> bool {
    let before = pf.projects.len();
    pf.projects.retain(|p| p.slug != slug);
    pf.projects.len() < before
}

/// Normalize a repo URL to "owner/repo" format.
/// Handles: https://github.com/owner/repo.git, git@github.com:owner/repo, owner/repo
pub fn normalize_repo(url: &str) -> String {
    let s = url.trim();
    // Strip .git suffix
    let s = s.strip_suffix(".git").unwrap_or(s);
    // SSH format: git@host:owner/repo
    if let Some(after_colon) = s
        .strip_prefix("git@")
        .and_then(|s| s.split_once(':').map(|(_, r)| r))
    {
        return after_colon.to_string();
    }
    // HTTPS format: https://host/owner/repo
    if s.contains("://") {
        let parts: Vec<&str> = s.split('/').collect();
        if parts.len() >= 2 {
            let repo = parts[parts.len() - 1];
            let owner = parts[parts.len() - 2];
            if !owner.is_empty() && !repo.is_empty() {
                return format!("{owner}/{repo}");
            }
        }
    }
    // Already normalized or bare owner/repo
    s.to_string()
}

/// Detect project from a repo identifier. Exact match against project repos.
pub fn detect_by_repo(pf: &ProjectFile, repo_input: &str) -> DetectionResult {
    let normalized = normalize_repo(repo_input);
    for project in &pf.projects {
        for repo in &project.repos {
            if normalize_repo(repo) == normalized {
                return DetectionResult {
                    slug: Some(project.slug.clone()),
                    confidence: "exact".to_string(),
                    method: "repo-match".to_string(),
                };
            }
        }
    }
    DetectionResult {
        slug: None,
        confidence: "none".to_string(),
        method: "repo-match".to_string(),
    }
}

/// Detect project from subject text. Heuristic substring match.
pub fn detect_by_subject(pf: &ProjectFile, subject: &str) -> DetectionResult {
    let lower = subject.to_lowercase();
    let mut matches: Vec<&str> = Vec::new();

    for project in &pf.projects {
        let slug_match = lower.contains(&project.slug.to_lowercase());
        let name_match = project
            .name
            .as_ref()
            .map(|n| lower.contains(&n.to_lowercase()))
            .unwrap_or(false);

        if slug_match || name_match {
            matches.push(&project.slug);
        }
    }

    match matches.len() {
        1 => DetectionResult {
            slug: Some(matches[0].to_string()),
            confidence: "heuristic".to_string(),
            method: "subject-match".to_string(),
        },
        _ => DetectionResult {
            slug: None,
            confidence: "none".to_string(),
            method: "subject-match".to_string(),
        },
    }
}

/// Build a repo→project mapping for bulk detection.
pub fn build_repo_map(pf: &ProjectFile) -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
    for project in &pf.projects {
        for repo in &project.repos {
            map.insert(normalize_repo(repo), project.slug.clone());
        }
    }
    map
}

// ── Entry point ───────────────────────────────────────────────────────

pub async fn execute(args: &ProjectArgs) -> Result<()> {
    match &args.command {
        None => execute_list(args.json),
        Some(ProjectCommand::Show { slug }) => execute_show(slug, args.json),
        Some(ProjectCommand::Add {
            slug,
            name,
            repo,
            priority,
        }) => execute_add(slug, name.as_deref(), repo, *priority),
        Some(ProjectCommand::Remove { slug }) => execute_remove(slug),
        Some(ProjectCommand::Detect { repo, subject }) => {
            execute_detect(repo.as_deref(), subject.as_deref())
        }
    }
}

// ── List ──────────────────────────────────────────────────────────────

fn execute_list(json: bool) -> Result<()> {
    let path = projects_file_path();
    let pf = load_projects_from(&path)?;

    if json {
        println!("{}", serde_json::to_string_pretty(&pf.projects)?);
        return Ok(());
    }

    if pf.projects.is_empty() {
        println!("No projects.");
        return Ok(());
    }

    for p in &pf.projects {
        let name = p.name.as_deref().unwrap_or(&p.slug);
        let pri = p
            .priority
            .map(|n| format!(" (pri: {n})"))
            .unwrap_or_default();
        let repos = if p.repos.is_empty() {
            String::new()
        } else {
            format!(" — {} repos", p.repos.len())
        };
        println!("  {}{pri}{repos}", name);
    }
    Ok(())
}

// ── Show ──────────────────────────────────────────────────────────────

fn execute_show(slug: &str, json: bool) -> Result<()> {
    let path = projects_file_path();
    let pf = load_projects_from(&path)?;

    match pf.projects.iter().find(|p| p.slug == slug) {
        Some(project) => {
            if json {
                println!("{}", serde_json::to_string_pretty(project)?);
            } else {
                println!(
                    "Project: {}",
                    project.name.as_deref().unwrap_or(&project.slug)
                );
                if let Some(desc) = &project.description {
                    println!("  {desc}");
                }
                if let Some(pri) = project.priority {
                    println!("  Priority: {pri}");
                }
                if !project.repos.is_empty() {
                    println!("  Repos:");
                    for r in &project.repos {
                        println!("    {r}");
                    }
                }
                if let Some(prov) = &project.provider {
                    println!("  Provider: {:?}", prov);
                }
            }
        }
        None => eprintln!("Project '{slug}' not found."),
    }
    Ok(())
}

// ── Add ───────────────────────────────────────────────────────────────

fn execute_add(
    slug: &str,
    name: Option<&str>,
    repos: &[String],
    priority: Option<u32>,
) -> Result<()> {
    // Validate slug: kebab-case (lowercase alphanumeric + hyphens, no leading/trailing hyphen)
    let valid = !slug.is_empty()
        && slug
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        && !slug.starts_with('-')
        && !slug.ends_with('-')
        && !slug.contains("--");
    if !valid {
        anyhow::bail!("Invalid slug '{slug}': must be kebab-case (e.g., 'my-project')");
    }

    let path = projects_file_path();
    let mut pf = load_projects_from(&path)?;

    let project = Project {
        slug: slug.to_string(),
        name: name.map(String::from),
        description: None,
        priority,
        repos: repos.iter().map(|r| normalize_repo(r)).collect(),
        sources: vec![],
        provider: None,
    };

    if add_project(&mut pf, project) {
        save_projects_to(&pf, &path)?;
        println!("Added: {slug}");
    } else {
        eprintln!("Project '{slug}' already exists.");
    }
    Ok(())
}

// ── Remove ────────────────────────────────────────────────────────────

fn execute_remove(slug: &str) -> Result<()> {
    let path = projects_file_path();
    let mut pf = load_projects_from(&path)?;

    if remove_project(&mut pf, slug) {
        save_projects_to(&pf, &path)?;
        println!("Removed: {slug}");
    } else {
        eprintln!("Project '{slug}' not found.");
    }
    Ok(())
}

// ── Detect ────────────────────────────────────────────────────────────

fn execute_detect(repo: Option<&str>, subject: Option<&str>) -> Result<()> {
    let path = projects_file_path();
    let pf = load_projects_from(&path)?;

    let result = if let Some(r) = repo {
        detect_by_repo(&pf, r)
    } else if let Some(s) = subject {
        detect_by_subject(&pf, s)
    } else {
        anyhow::bail!("Provide --repo or --subject for detection");
    };

    println!("{}", serde_json::to_string_pretty(&result)?);
    Ok(())
}

// ── Tests ─────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    fn make_project(slug: &str, repos: &[&str]) -> Project {
        Project {
            slug: slug.to_string(),
            name: Some(slug.replace('-', " ").to_string()),
            description: None,
            priority: None,
            repos: repos.iter().map(|r| r.to_string()).collect(),
            sources: vec![],
            provider: None,
        }
    }

    // ── YAML round-trip ───────────────────────────────────────────

    #[test]
    fn test_yaml_round_trip() {
        let pf = ProjectFile {
            projects: vec![make_project("keystone", &["ncrmro/keystone"])],
        };
        let tmp = NamedTempFile::new().unwrap();
        save_projects_to(&pf, &tmp.path().to_path_buf()).unwrap();
        let loaded = load_projects_from(&tmp.path().to_path_buf()).unwrap();
        assert_eq!(loaded.projects.len(), 1);
        assert_eq!(loaded.projects[0].slug, "keystone");
    }

    #[test]
    fn test_load_missing_file() {
        let path = PathBuf::from("/tmp/nonexistent-ks-projects.yaml");
        let result = load_projects_from(&path).unwrap();
        assert!(result.projects.is_empty());
    }

    // ── add / remove ──────────────────────────────────────────────

    #[test]
    fn test_add_project() {
        let mut pf = ProjectFile { projects: vec![] };
        assert!(add_project(&mut pf, make_project("keystone", &[])));
        assert_eq!(pf.projects.len(), 1);
    }

    #[test]
    fn test_add_project_dedup() {
        let mut pf = ProjectFile {
            projects: vec![make_project("keystone", &[])],
        };
        assert!(!add_project(&mut pf, make_project("keystone", &[])));
        assert_eq!(pf.projects.len(), 1);
    }

    #[test]
    fn test_remove_project() {
        let mut pf = ProjectFile {
            projects: vec![make_project("keystone", &[])],
        };
        assert!(remove_project(&mut pf, "keystone"));
        assert!(pf.projects.is_empty());
    }

    #[test]
    fn test_remove_project_not_found() {
        let mut pf = ProjectFile { projects: vec![] };
        assert!(!remove_project(&mut pf, "missing"));
    }

    // ── normalize_repo ────────────────────────────────────────────

    #[test]
    fn test_normalize_bare() {
        assert_eq!(normalize_repo("ncrmro/keystone"), "ncrmro/keystone");
    }

    #[test]
    fn test_normalize_https() {
        assert_eq!(
            normalize_repo("https://github.com/ncrmro/keystone.git"),
            "ncrmro/keystone"
        );
    }

    #[test]
    fn test_normalize_ssh() {
        assert_eq!(
            normalize_repo("git@github.com:ncrmro/keystone.git"),
            "ncrmro/keystone"
        );
    }

    #[test]
    fn test_normalize_https_no_git() {
        assert_eq!(
            normalize_repo("https://github.com/ncrmro/keystone"),
            "ncrmro/keystone"
        );
    }

    // ── detect_by_repo ────────────────────────────────────────────

    #[test]
    fn test_detect_repo_exact() {
        let pf = ProjectFile {
            projects: vec![make_project(
                "keystone",
                &["ncrmro/keystone", "ncrmro/nixos-config"],
            )],
        };
        let result = detect_by_repo(&pf, "ncrmro/keystone");
        assert_eq!(result.slug, Some("keystone".to_string()));
        assert_eq!(result.confidence, "exact");
    }

    #[test]
    fn test_detect_repo_normalized_url() {
        let pf = ProjectFile {
            projects: vec![make_project("keystone", &["ncrmro/keystone"])],
        };
        let result = detect_by_repo(&pf, "https://github.com/ncrmro/keystone.git");
        assert_eq!(result.slug, Some("keystone".to_string()));
        assert_eq!(result.confidence, "exact");
    }

    #[test]
    fn test_detect_repo_no_match() {
        let pf = ProjectFile {
            projects: vec![make_project("keystone", &["ncrmro/keystone"])],
        };
        let result = detect_by_repo(&pf, "other/repo");
        assert_eq!(result.slug, None);
        assert_eq!(result.confidence, "none");
    }

    // ── detect_by_subject ─────────────────────────────────────────

    #[test]
    fn test_detect_subject_single_match() {
        let pf = ProjectFile {
            projects: vec![
                make_project("keystone", &[]),
                make_project("plant-caravan", &[]),
            ],
        };
        let result = detect_by_subject(&pf, "Fix keystone build failure");
        assert_eq!(result.slug, Some("keystone".to_string()));
        assert_eq!(result.confidence, "heuristic");
    }

    #[test]
    fn test_detect_subject_ambiguous() {
        // Use names that both substring-match the subject
        let mut p1 = make_project("proj-a", &[]);
        p1.name = Some("Cloud Platform".to_string());
        let mut p2 = make_project("proj-b", &[]);
        p2.name = Some("Cloud Storage".to_string());
        let pf = ProjectFile {
            projects: vec![p1, p2],
        };
        // "cloud" matches both names
        let result = detect_by_subject(&pf, "cloud migration plan");
        assert_eq!(result.slug, None);
        assert_eq!(result.confidence, "none");
    }

    #[test]
    fn test_detect_subject_no_match() {
        let pf = ProjectFile {
            projects: vec![make_project("keystone", &[])],
        };
        let result = detect_by_subject(&pf, "unrelated topic");
        assert_eq!(result.slug, None);
        assert_eq!(result.confidence, "none");
    }

    #[test]
    fn test_detect_subject_by_name() {
        let mut p = make_project("pc", &[]);
        p.name = Some("Plant Caravan".to_string());
        let pf = ProjectFile { projects: vec![p] };
        let result = detect_by_subject(&pf, "Plant Caravan sensor issue");
        assert_eq!(result.slug, Some("pc".to_string()));
        assert_eq!(result.confidence, "heuristic");
    }

    // ── build_repo_map ────────────────────────────────────────────

    #[test]
    fn test_build_repo_map() {
        let pf = ProjectFile {
            projects: vec![
                make_project("keystone", &["ncrmro/keystone", "ncrmro/nixos-config"]),
                make_project("caravan", &["ncrmro/plant-caravan"]),
            ],
        };
        let map = build_repo_map(&pf);
        assert_eq!(map.get("ncrmro/keystone"), Some(&"keystone".to_string()));
        assert_eq!(
            map.get("ncrmro/plant-caravan"),
            Some(&"caravan".to_string())
        );
        assert_eq!(map.len(), 3);
    }
}
