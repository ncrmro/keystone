use crate::modules::config::ContextMode;
use anyhow::{Context, Result};
use tokio::process::Command;

pub struct ContextBuilder;

impl ContextBuilder {
    pub async fn build(mode: ContextMode, lookback: Option<&str>) -> Result<String> {
        match mode {
            ContextMode::Diff => Self::build_diff(lookback).await,
            ContextMode::Files => Self::build_files(lookback).await,
        }
    }

    async fn build_diff(lookback: Option<&str>) -> Result<String> {
        let args = if let Some(lb) = lookback {
            if lb.contains(':') {
                let parts: Vec<&str> = lb.split(':').collect();
                if parts.len() > 1 && parts[0] == "commits" {
                    vec!["log", "-p", "-n", parts[1]]
                } else {
                    vec!["log", "-p", "-n", "1"]
                }
            } else if lb.chars().any(|c| c.is_alphabetic()) {
                vec!["log", "-p", "--since", lb]
            } else {
                 vec!["log", "-p", "-n", lb]
            }
        } else {
            vec!["log", "-p", "-n", "1"]
        };

        let output = Command::new("git")
            .args(&args)
            .output()
            .await
            .context("Failed to run git log")?;
            
        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }

    async fn build_files(lookback: Option<&str>) -> Result<String> {
        // Implementation: Find files changed in recent commits (filtered by regex if provided in lookback)
        // For now, let's assume lookback is "commits:X" or just "X"
        let n = if let Some(lb) = lookback {
            if lb.starts_with("commits:") {
                lb.strip_prefix("commits:").unwrap().parse::<usize>().unwrap_or(1)
            } else {
                lb.parse::<usize>().unwrap_or(1)
            }
        } else {
            1
        };

        // Get list of files changed in last N commits
        let output = Command::new("git")
            .args(&["log", "-n", &n.to_string(), "--pretty=format:", "--name-only"])
            .output()
            .await
            .context("Failed to get changed files from git")?;

        let files_str = String::from_utf8_lossy(&output.stdout);
        let mut files: Vec<&str> = files_str.lines()
            .filter(|l| !l.is_empty())
            .collect();
        files.sort();
        files.dedup();

        let mut context = String::new();
        for file in files {
            if std::path::Path::new(file).exists() {
                let content = tokio::fs::read_to_string(file).await;
                if let Ok(c) = content {
                    context.push_str(&format!("--- File: {} ---\n", file));
                    context.push_str(&c);
                    context.push_str("\n\n");
                }
            }
        }

        Ok(context)
    }
}
