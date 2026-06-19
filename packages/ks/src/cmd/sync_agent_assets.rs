//! `ks sync-agent-assets` command — refresh generated agent assets.

use anyhow::{anyhow, Context, Result};
use std::env;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

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

/// Run `keystone-sync-agent-assets`, inheriting the parent's stdio.
fn run_sync_binary() -> Result<()> {
    let Some(program) = find_executable("keystone-sync-agent-assets") else {
        return Err(anyhow!(
            "keystone-sync-agent-assets is not available in PATH. Refresh the home-manager profile before using this command."
        ));
    };

    let status = Command::new(program)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .context("Failed to run keystone-sync-agent-assets")?;

    if !status.success() {
        std::process::exit(status.code().unwrap_or(1));
    }

    Ok(())
}

pub fn execute() -> Result<()> {
    run_sync_binary()
}

/// Decide whether the canonical skill tree under `<consumer-flake>/agents/skills/`
/// needs a first-time populate. Returns `true` when the directory is absent or
/// holds no entries.
///
/// CRITICAL: this is the *only* condition under which a deploy is allowed to
/// run the sync script. A populated tree is the user's committed git working
/// tree (conventions/tool.cli-coding-agents.md rule 14); rewriting it on every
/// switch would produce spurious diffs and silently clobber a tree the user
/// reviews via git. We only fill an *empty* tree — the failure mode where a
/// fresh rebuild leaves `~/.agents/skills` / `~/.claude/skills` resolving to
/// nothing because sync was never run.
fn skills_tree_is_empty(consumer_flake: &Path) -> bool {
    let skills_dir = consumer_flake.join("agents").join("skills");
    match std::fs::read_dir(&skills_dir) {
        Ok(mut entries) => entries.next().is_none(),
        // Missing directory (or unreadable) counts as empty — the populate path
        // will create it. An unreadable dir is rare and the sync script surfaces
        // its own error, so treating it as empty is safe.
        Err(_) => true,
    }
}

/// Auto-populate agent assets after a deploy that touched a local host, but only
/// when the canonical skill tree is empty.
///
/// This is the *workflow* automation requested over the manual-only model: a
/// fresh host (or one where the consumer flake was never synced) ends a
/// `ks switch` / `ks update` with a populated tree instead of empty symlink
/// targets. It deliberately stops short of an unconditional sync so the
/// steady-state committed tree is never rewritten behind the user's back.
///
/// `deployed_local` gates the work to deploys that actually activated this
/// machine's home-manager profile — a remote-only deploy writes no local
/// symlinks, so there is nothing to populate here.
pub fn populate_after_deploy(consumer_flake: &Path, deployed_local: bool) {
    if !deployed_local {
        return;
    }
    if !skills_tree_is_empty(consumer_flake) {
        return;
    }
    eprintln!(
        "Agent assets at {}/agents/skills are empty — populating (one-time) via sync-agent-assets...",
        consumer_flake.display()
    );
    if let Err(err) = run_sync_binary() {
        // Non-fatal: the deploy itself succeeded. Surface the reason and the
        // manual recovery path rather than failing the whole switch.
        eprintln!(
            "Warning: auto-populate of agent assets failed: {err}\n  \
             Run 'ks sync-agent-assets' manually once the profile is available."
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_when_skills_dir_missing() {
        let dir = tempfile::tempdir().unwrap();
        // No agents/skills created at all.
        assert!(skills_tree_is_empty(dir.path()));
    }

    #[test]
    fn empty_when_skills_dir_present_but_empty() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("agents").join("skills")).unwrap();
        assert!(skills_tree_is_empty(dir.path()));
    }

    #[test]
    fn not_empty_when_skills_dir_has_entries() {
        let dir = tempfile::tempdir().unwrap();
        let skills = dir.path().join("agents").join("skills");
        std::fs::create_dir_all(&skills).unwrap();
        std::fs::create_dir_all(skills.join("ks-system")).unwrap();
        assert!(!skills_tree_is_empty(dir.path()));
    }

    #[test]
    fn populate_skips_remote_only_deploy() {
        let dir = tempfile::tempdir().unwrap();
        // deployed_local = false must short-circuit before touching the FS or
        // looking for the sync binary, so an empty tree stays untouched.
        populate_after_deploy(dir.path(), false);
        assert!(!dir.path().join("agents").join("skills").exists());
    }
}
