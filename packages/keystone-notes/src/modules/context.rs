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

    async fn build_files(_lookback: Option<&str>) -> Result<String> {
         Ok("ContextMode::Files not fully implemented yet".to_string())
    }
}
