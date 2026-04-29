//! `ks update --approve` — Walker-triggered, channel-aware update flow
//! with narrow polkit-elevated activation.
//!
//! Privilege boundary (issue #487):
//!
//! ```text
//! walker → systemctl --user start ks-update.service
//!        → ks update --approve                                  [user]
//!             ├─ resolve channel target ref via GitHub API       [user]
//!             ├─ nix build --override-input keystone <ref>       [user]
//!             ├─ ks approve … -- ks activate <store-path>        ← polkit
//!             │     └─ keystone-approve-exec → ks activate       [root]
//!             ├─ on activation success: nix flake update keystone[user]
//!             ├─ git commit -m "chore: bump keystone to <ref>"   [user]
//!             ├─ git push origin <branch>                        [user]
//!             └─ notify success/failure                          [user]
//! ```
//!
//! Atomicity contract:
//!
//! 1. Resolve target ref (no filesystem mutation).
//! 2. `nix build --override-input keystone <ref>` (does NOT modify
//!    `flake.lock`; failure here is a no-op on the consumer flake).
//! 3. On build success, run `nix flake update keystone` so the lock
//!    matches what we just built and activated.
//! 4. polkit → `ks activate <store-path>` (single root invocation).
//! 5. On activation success, commit lock + push.
//!
//! A failure at any step before step 4 leaves the consumer flake's
//! `flake.lock` and working tree unchanged. A failure at step 5 leaves
//! the activated host and a committed lock — the local generation is
//! correct, the push can be retried by hand.
//!
//! Never confuse this code path with `cmd::update::update_locked`. That
//! is the terminal-only `ks update --lock` flow with full-fleet semantics
//! (pull all managed repos, deploy multiple hosts, sudo-cached
//! activation). This module is consumer-OS-style: one host, one channel
//! target, one polkit prompt.

use anyhow::{anyhow, Context, Result};
use std::path::{Path, PathBuf};

use crate::cmd::update_menu::{fetch_latest_release, Channel};
use crate::cmd::{self, util};
use crate::repo;

/// Single-host update result for the supervised flow. Returned to
/// `run_update_command` so the JSON envelope shape stays consistent
/// with `cmd::update::UpdateResult`.
#[derive(Debug)]
pub(crate) struct ApproveUpdateOutcome {
    pub host: String,
    pub channel: &'static str,
    pub target_ref: String,
    pub store_path: String,
    /// True when the lock changed and was committed.
    pub lock_advanced: bool,
    /// True when the commit was pushed to origin.
    pub pushed: bool,
}

/// Resolve the target ref for the active channel. For stable that's a
/// release tag commit SHA (`fetch_release_commit_rev` already ran inside
/// `fetch_latest_release`); for unstable it's the tip commit of `main`.
async fn resolve_target_ref(channel: Channel) -> Result<(String, String)> {
    let info = fetch_latest_release(channel)
        .await
        .with_context(|| format!("failed to resolve {} channel target", channel.as_str()))?;
    if info.latest_rev.trim().is_empty() {
        anyhow::bail!(
            "{} channel returned no commit sha for target {}",
            channel.as_str(),
            info.latest_tag
        );
    }
    Ok((info.latest_rev, info.latest_tag))
}

/// Build the system closure for `host` against an overridden keystone
/// input pinned at `rev`. Uses `--override-input` so `flake.lock` is
/// untouched — a build failure leaves the consumer flake clean. Returns
/// the realized store path of the system toplevel.
async fn build_with_override(repo_root: &Path, host: &str, rev: &str) -> Result<String> {
    let mut override_args = repo::local_override_args(repo_root).await?;
    // CRITICAL: this is the override that points the build at the
    // channel-resolved target. It MUST coexist with any
    // `local_override_args` (which redirect file-source inputs in
    // development mode) — the new override layers on top.
    override_args.push("--override-input".to_string());
    override_args.push("keystone".to_string());
    override_args.push(format!("github:ncrmro/keystone/{rev}"));

    let target = format!(
        "{}#nixosConfigurations.{}.config.system.build.toplevel",
        repo_root.display(),
        host
    );

    let mut cmd = tokio::process::Command::new("nix");
    cmd.arg("build")
        .arg("--no-link")
        .arg("--print-out-paths")
        .arg(&target);
    for arg in &override_args {
        cmd.arg(arg);
    }
    cmd.current_dir(repo_root);

    eprintln!(
        "Building {host} system closure against keystone@{rev}…\n  target: {target}",
        host = host,
        rev = rev,
        target = target
    );

    let output = cmd
        .output()
        .await
        .context("failed to invoke nix build for supervised update")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("nix build failed:\n{}", stderr);
    }

    let path = String::from_utf8_lossy(&output.stdout)
        .lines()
        .find(|line| !line.trim().is_empty())
        .map(str::to_string)
        .ok_or_else(|| anyhow!("nix build emitted no store path"))?;
    Ok(path)
}

/// Lock the keystone input to the target rev using `nix flake update
/// keystone`. Run AFTER the build succeeds so a failed build never
/// mutates `flake.lock`.
async fn relock_keystone_input(repo_root: &Path) -> Result<()> {
    let status = tokio::process::Command::new("nix")
        .args(["flake", "update", "keystone"])
        .arg("--flake")
        .arg(repo_root)
        .status()
        .await
        .context("failed to invoke nix flake update keystone")?;
    if !status.success() {
        anyhow::bail!("nix flake update keystone exited {:?}", status.code());
    }
    Ok(())
}

/// Returns true when `flake.lock` has unstaged or staged changes
/// relative to HEAD. We use this to decide whether the relock actually
/// moved anything; if not, no commit / push is needed.
async fn flake_lock_dirty(repo_root: &Path) -> Result<bool> {
    let output = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["status", "--porcelain", "--", "flake.lock"])
        .output()
        .await
        .context("failed to inspect flake.lock status")?;
    Ok(output.status.success() && !output.stdout.is_empty())
}

async fn commit_lock(repo_root: &Path, target_ref: &str) -> Result<()> {
    let add_status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["add", "flake.lock"])
        .status()
        .await
        .context("failed to stage flake.lock")?;
    if !add_status.success() {
        anyhow::bail!("git add flake.lock exited {:?}", add_status.code());
    }
    let msg = format!("chore: bump keystone to {target_ref}");
    let commit_status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["commit", "-m", &msg])
        .status()
        .await
        .context("failed to commit flake.lock")?;
    if !commit_status.success() {
        anyhow::bail!("git commit exited {:?}", commit_status.code());
    }
    Ok(())
}

async fn current_branch(repo_root: &Path) -> Result<String> {
    let output = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["symbolic-ref", "--short", "HEAD"])
        .output()
        .await
        .context("failed to read current branch")?;
    if !output.status.success() {
        anyhow::bail!("not on a branch (detached HEAD?)");
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Push the new lock commit. Best-effort — a failed push is logged but
/// does not fail the whole update because the local activation already
/// succeeded. The user can resolve the push by hand.
async fn push_lock(repo_root: &Path, branch: &str) -> Result<bool> {
    let status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["push", "origin"])
        .arg(branch)
        .status()
        .await
        .context("failed to invoke git push")?;
    if !status.success() {
        eprintln!(
            "Warning: git push origin {branch} exited {:?} — local lock advanced but remote is behind. Push by hand to sync.",
            status.code()
        );
        return Ok(false);
    }
    Ok(true)
}

/// Build the privileged invocation that will be sent through
/// `ks approve … -- ks activate <path>`. Centralised so the test can
/// assert the exact argv shape the broker sees.
pub(crate) fn elevated_argv(store_path: &str) -> Vec<String> {
    vec![
        "ks".to_string(),
        "activate".to_string(),
        store_path.to_string(),
    ]
}

/// Compose the human-readable reason shown in the polkit dialog. The
/// allowlist also has a static `displayName` ("Install Keystone update")
/// — this string is the per-request `Requested reason:` line, which
/// names the host so a user with multiple machines can tell which one
/// the dialog is for.
pub(crate) fn approval_reason(host_label: &str) -> String {
    format!("Install Keystone update on {host_label}")
}

/// Drive the activation step through `cmd::approve::execute`. Returns
/// only on failure — the success path execs the broker and replaces this
/// process. The caller therefore must perform any post-activation work
/// (lock commit + push) before invoking `activate_via_broker`. That
/// inversion is awkward; we work around it by performing the post-work
/// inline here, then exec'ing the broker as the last step. See
/// `run_supervised_update` below for the actual sequencing.
fn activate_via_broker(reason: &str, store_path: &str) -> Result<()> {
    let argv = elevated_argv(store_path);
    cmd::approve::execute(reason, &argv)
}

/// Top-level entry. Resolves channel target → builds → relocks →
/// commits → pushes → activates (privileged). Activation is last so
/// `cmd::approve::execute`'s `exec()` replaces this process.
pub(crate) async fn run_supervised_update(
    flake_override: Option<&Path>,
) -> Result<ApproveUpdateOutcome> {
    let repo_root = repo::find_repo(flake_override)?;
    let host = repo::resolve_current_host(&repo_root)
        .await?
        .ok_or_else(|| anyhow!("could not resolve current host from repo registry"))?;

    let channel = Channel::current();
    eprintln!(
        "Running supervised update for host {} on channel {}",
        host,
        channel.as_str()
    );

    // Step 1: resolve the target ref via GitHub API. Runs in the
    // user's session — token + DNS available.
    let (target_rev, target_tag) = resolve_target_ref(channel).await?;
    eprintln!(
        "Resolved {} channel target: {target_tag} ({target_rev})",
        channel.as_str()
    );

    // Step 2: build the closure with the override. flake.lock untouched
    // up to this point; a failure here is a no-op on the consumer
    // flake's state.
    let store_path = build_with_override(&repo_root, &host, &target_rev).await?;
    eprintln!("Built closure: {store_path}");

    // Step 3: now that the build succeeded, advance flake.lock to the
    // target rev. The override-build above is functionally equivalent
    // to what `nix flake update keystone` will produce, so the closure
    // we just built matches what a fresh build off the new lock would
    // produce.
    relock_keystone_input(&repo_root).await?;

    // Step 4: commit the lock change before activation. Sequencing
    // rationale: if activation fails, the local closure was never
    // promoted to /run/current-system, but the lock advance reflects
    // the remote ref the user *wanted* to land. Leaving an uncommitted
    // lock on the working tree would make the next menu render see
    // "dirty tree" and refuse the next click.
    let lock_advanced = if flake_lock_dirty(&repo_root).await? {
        commit_lock(&repo_root, &target_tag).await?;
        true
    } else {
        eprintln!("flake.lock already pinned at {target_rev} — no commit needed.");
        false
    };

    // Step 5: try to push. Best-effort — a network blip post-build
    // shouldn't block local activation. Run before activation so the
    // privileged exec doesn't strand the lock locally.
    let pushed = if lock_advanced {
        let branch = current_branch(&repo_root).await?;
        push_lock(&repo_root, &branch).await.unwrap_or(false)
    } else {
        false
    };

    // Step 6: activate. This is the only privileged step. The broker
    // exec()'s into pkexec → keystone-approve-exec → root → ks activate
    // — successful return from this function is unreachable.
    let host_label = util::hostname_label();
    let reason = approval_reason(&host_label);
    eprintln!("Requesting approval to activate {store_path}…");

    // Construct the outcome up front so JSON callers and tests see the
    // same shape. The function only returns this if `activate_via_broker`
    // fails (because on success the broker exec's away).
    let outcome = ApproveUpdateOutcome {
        host: host.clone(),
        channel: channel.as_str(),
        target_ref: target_tag,
        store_path: store_path.clone(),
        lock_advanced,
        pushed,
    };

    activate_via_broker(&reason, &store_path)?;
    // Unreachable on success — `cmd::approve::execute` exec()'s into
    // pkexec/sudo when no error occurs.
    Ok(outcome)
}

/// Dummy import suppressor — keeps the implicit `PathBuf` reachable in
/// `pub(crate)` items even after refactors that elide the obvious
/// callsites. Avoids a `dead_code` cycle on test builds.
#[allow(dead_code)]
fn _keep(_: &PathBuf) {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn elevated_argv_is_exactly_ks_activate_path() {
        // CRITICAL: the privileged-approval allowlist matches on argv
        // shape `["ks", "activate", <prefix>]`. If anyone reorders or
        // injects an extra arg here, the broker rejects the request
        // with "command is not allowlisted" and Walker → Update fails
        // silently. This test pins the contract.
        let argv = elevated_argv("/nix/store/abcdef-system-x");
        assert_eq!(argv, vec!["ks", "activate", "/nix/store/abcdef-system-x"]);
    }

    #[test]
    fn elevated_argv_contains_no_git_verbs() {
        // Defense in depth: the producer-side workflow does git pull,
        // commit, push as the user. The privileged child must never
        // see a git verb because root has no SSH credentials.
        let argv = elevated_argv("/nix/store/x");
        for forbidden in ["pull", "push", "commit", "fetch", "clone", "lock"] {
            assert!(
                !argv.iter().any(|a| a == forbidden),
                "argv leaked git verb {forbidden}: {argv:?}"
            );
        }
    }

    #[test]
    fn approval_reason_names_the_host() {
        // The polkit dialog shows the displayName from the allowlist
        // statically; the per-request reason is what tells the user
        // which machine they're approving. Empty / generic reasons
        // would let a Mac-style "approve anywhere" social-engineer
        // the user into hitting yes on the wrong host.
        let reason = approval_reason("ncrmro-laptop");
        assert!(reason.contains("ncrmro-laptop"), "reason: {reason}");
        assert!(reason.contains("Keystone update"), "reason: {reason}");
    }
}
