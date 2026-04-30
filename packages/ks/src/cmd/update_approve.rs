//! `ks update --approve` — Walker-triggered, channel-aware update flow
//! with narrow polkit-elevated activation.
//!
//! Privilege boundary (issue #487):
//!
//! ```text
//! walker → systemctl --user start ks-update.service
//!        → ks update --approve                                  [user]
//!             ├─ pre-flight: refuse if local != origin           [user]
//!             ├─ resolve channel target ref via GitHub API       [user]
//!             ├─ nix build --override-input keystone <ref>       [user]
//!             ├─ ks approve … -- ks activate <store-path>        ← polkit
//!             │     └─ keystone-approve-exec → ks activate       [root]
//!             ├─ on activation success:                          [user]
//!             │     nix flake lock --update-input keystone
//!             │       --override-input keystone github:.../<rev>
//!             ├─ git commit -m "chore: bump keystone to <ref>"   [user]
//!             ├─ git push origin <branch>                        [user]
//!             └─ notify success/failure                          [user]
//! ```
//!
//! In-sync invariant:
//!
//! Before any side effect, the consumer flake's working tree MUST be
//! clean and the current branch MUST equal `origin/<branch>`. The
//! supervised flow refuses to start otherwise. This buys us:
//!
//! - Atomicity at the user layer: a successful update appends exactly
//!   one new commit (the lock bump), so the final `git push` is a
//!   guaranteed fast-forward by exactly one commit. No mid-flow
//!   non-fast-forward errors after the privileged step has already run.
//! - Comprehensibility: when the dialog refuses up front, the user
//!   sees one concrete reason ("ahead of origin", "behind origin",
//!   "uncommitted changes") instead of a partially-applied update
//!   that activated but couldn't push.
//!
//! Atomicity contract (activate-then-mutate):
//!
//! 0. Pre-flight: ensure consumer flake is in sync with origin.
//! 1. Resolve target ref (no filesystem mutation).
//! 2. `nix build --override-input keystone <ref>` — does NOT modify
//!    `flake.lock`. Failure here is a no-op on the consumer flake.
//! 3. polkit → `ks activate <store-path>` via
//!    [`cmd::approve::run_and_wait`]. The orchestrator waits for the
//!    privileged child to exit instead of `exec()`-replacing itself, so
//!    control returns here to gate the next step on the exit status.
//! 4. **Only** on activation success: relock the consumer flake's
//!    `keystone` input, pinned to the exact rev we just built and
//!    activated (`--update-input keystone --override-input
//!    keystone github:ncrmro/keystone/<rev>`). Without the override,
//!    `nix flake update keystone` would re-resolve `github:ncrmro/keystone`
//!    to the default-branch tip — which can disagree with the activated
//!    closure on stable channels (where the target is a tag commit, not
//!    branch tip) or on unstable when a new commit lands between resolve
//!    and relock.
//! 5. Commit the lock change, push (guaranteed fast-forward by exactly
//!    one commit; see the in-sync invariant above), notify.
//!
//! Failure modes:
//!
//! - Step 0 fails → pre-flight refused to start. No side effects on
//!   the host or the consumer flake. The error names the specific
//!   reason (dirty / ahead / behind) so the user can resolve it
//!   without inspecting logs.
//! - Steps 1–3 fail → consumer flake's `flake.lock` and working tree
//!   are untouched. The next Walker click retries from scratch.
//! - Step 3 succeeds, step 4 fails → host is activated against the new
//!   closure but the lock is stale. This is the same end state as
//!   `--dev` activations and resolves on the next successful update.
//! - Step 5 push fails → lock is committed locally; the user pushes by
//!   hand or the next update sweeps it. With the pre-flight in place
//!   the push is fast-forward by exactly one commit, so this failure
//!   is now strictly a network/auth issue, not a divergence issue.
//!
//! Never confuse this code path with `cmd::update::update_locked`. That
//! is the terminal-only `ks update --lock` flow with full-fleet semantics
//! (pull all managed repos, deploy multiple hosts, sudo-cached
//! activation). This module is consumer-OS-style: one host, one channel
//! target, one polkit prompt.

use anyhow::{anyhow, Context, Result};
use std::path::Path;

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

/// Lock the keystone input to the exact target rev we just built and
/// activated. Run AFTER successful activation so a failed activation
/// never mutates `flake.lock`.
//
// CRITICAL: pin the lock to `github:ncrmro/keystone/<rev>` rather than
// running a bare `nix flake update keystone`. For consumer flakes that
// declare `keystone.url = "github:ncrmro/keystone"`, the bare update
// would re-resolve the input to the default-branch tip, which can drift
// from the channel-resolved rev in two ways:
//   1. Stable channel: the target is a tag commit (often older than
//      `main`); `update keystone` would jump to `main` tip and the lock
//      would diverge from the activated closure.
//   2. Unstable channel: between `resolve_target_ref` and this call,
//      a new commit may land on `main`; `update keystone` would pick
//      it up, locking to a rev we never built.
// `--update-input keystone` forces the lockfile entry to refresh, and
// `--override-input keystone github:.../<rev>` pins it to exactly the
// rev we built — making the lock match the realized closure.
async fn relock_keystone_input(repo_root: &Path, rev: &str) -> Result<()> {
    let pinned = format!("github:ncrmro/keystone/{rev}");
    let status = tokio::process::Command::new("nix")
        .args([
            "flake",
            "lock",
            "--update-input",
            "keystone",
            "--override-input",
            "keystone",
            &pinned,
        ])
        .arg("--flake")
        .arg(repo_root)
        .status()
        .await
        .context("failed to invoke nix flake lock for keystone input")?;
    if !status.success() {
        anyhow::bail!(
            "nix flake lock --update-input keystone --override-input keystone {pinned} exited {:?}",
            status.code()
        );
    }
    Ok(())
}

/// Returns true when `flake.lock` has unstaged or staged changes
/// relative to HEAD. We use this to decide whether the relock actually
/// moved anything; if not, no commit / push is needed.
//
// CRITICAL: fail closed when `git status` itself errors. The previous
// implementation `output.status.success() && !output.stdout.is_empty()`
// silently treated git failures (not a worktree, missing git binary,
// permissions error, …) as "clean" and skipped the commit/push step
// while still letting the orchestrator continue. That hid genuine
// configuration breakage from the user. Bail loudly instead so the
// supervised update fails closed and the dialog reports something
// concrete. The orchestrator's atomicity contract is preserved
// because activation already succeeded — but a stale lock left
// uncommitted is still a regression we want surfaced, not swallowed.
async fn flake_lock_dirty(repo_root: &Path) -> Result<bool> {
    let output = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["status", "--porcelain", "--", "flake.lock"])
        .output()
        .await
        .context("failed to inspect flake.lock status")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!(
            "git status --porcelain -- flake.lock exited {:?} in {}: {}",
            output.status.code(),
            repo_root.display(),
            stderr.trim()
        );
    }
    Ok(!output.stdout.is_empty())
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

/// Pre-flight gate for the supervised update flow. Refuse to start
/// unless the consumer flake is in sync with origin.
///
/// CRITICAL invariant: before we touch anything, `local == remote`. The
/// supervised flow's only mutation is exactly one new commit (the
/// keystone lock bump) on the activation-success branch, so the final
/// `git push` is a guaranteed fast-forward by exactly one commit. This
/// removes the failure mode where the orchestrator activated against
/// the new closure but then tripped on a non-fast-forward push because
/// `master` was ahead of `origin/master` — leaving the host updated
/// and the consumer flake out of sync from the perspective of any
/// other agent that goes to relock.
///
/// Refusing up front is also the only error mode the user can act on
/// without inspecting logs: the dialog can name a single concrete
/// reason ("uncommitted changes", "ahead of origin", "behind origin"),
/// and the user knows what command to run before retrying.
///
/// Three sub-checks, in order:
///
/// 1. Working tree is clean. `git status --porcelain` exits 0 and
///    produces no output.
/// 2. `git fetch origin <branch>` is non-fatal — offline use is OK,
///    we just compare against the cached ref. If the fetch succeeds,
///    the next check uses fresh data.
/// 3. `<branch>` and `origin/<branch>` resolve to the same commit. If
///    not equal, bail with both shas in the error so the user can tell
///    whether they're ahead (push) or behind (pull).
async fn ensure_in_sync(repo_root: &Path) -> Result<()> {
    let branch = current_branch(repo_root).await?;

    // Sub-check 1: clean working tree. We use the bare
    // `git status --porcelain` (no path filter) because ANY uncommitted
    // change — not just to flake.lock — would either get mixed into the
    // bump commit or block the commit altogether. Refuse and let the
    // user clean up.
    let status_output = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["status", "--porcelain"])
        .output()
        .await
        .context("failed to inspect consumer flake working tree")?;
    if !status_output.status.success() {
        let stderr = String::from_utf8_lossy(&status_output.stderr);
        anyhow::bail!(
            "git status --porcelain exited {:?} in {}: {}",
            status_output.status.code(),
            repo_root.display(),
            stderr.trim()
        );
    }
    if !status_output.stdout.is_empty() {
        let porcelain = String::from_utf8_lossy(&status_output.stdout);
        anyhow::bail!(
            "consumer flake has uncommitted changes at {}; commit or stash before updating:\n{}",
            repo_root.display(),
            porcelain.trim_end()
        );
    }

    // Sub-check 2: refresh origin/<branch> so the comparison below
    // sees the current remote tip. Non-fatal: if the user is offline
    // we still want to compare against whatever ref we have cached —
    // refusing the update entirely on a transient network blip would
    // be more frustrating than the staleness risk it guards.
    let fetch_status = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["fetch", "origin"])
        .arg(&branch)
        .status()
        .await;
    match fetch_status {
        Ok(s) if !s.success() => {
            eprintln!(
                "Warning: git fetch origin {branch} exited {:?}; comparing against cached ref",
                s.code()
            );
        }
        Err(e) => {
            eprintln!(
                "Warning: failed to spawn git fetch origin {branch}: {e:#}; comparing against cached ref"
            );
        }
        _ => {}
    }

    // Sub-check 3: local branch == origin/<branch>. Both sides must
    // resolve. A missing origin ref is a hard error here because we
    // have no defensible way to push a fast-forward into a branch we
    // don't know exists.
    let local_sha = rev_parse(repo_root, &branch).await?;
    let remote_ref = format!("origin/{branch}");
    let remote_sha = rev_parse(repo_root, &remote_ref).await.with_context(|| {
        format!(
            "could not resolve {remote_ref}; ensure the branch is published before running supervised update"
        )
    })?;
    if local_sha != remote_sha {
        anyhow::bail!(
            "consumer flake branch {branch} ({local_sha}) is out of sync with origin/{branch} ({remote_sha}); pull or push before updating"
        );
    }
    Ok(())
}

/// Resolve `<refspec>` to a commit SHA via `git rev-parse`. Pulled out
/// so `ensure_in_sync` can compare local and remote tips with a single
/// helper that produces a comparable string (vs. parsing porcelain
/// output).
async fn rev_parse(repo_root: &Path, refspec: &str) -> Result<String> {
    let output = tokio::process::Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["rev-parse", refspec])
        .output()
        .await
        .with_context(|| format!("failed to invoke git rev-parse {refspec}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!(
            "git rev-parse {refspec} exited {:?} in {}: {}",
            output.status.code(),
            repo_root.display(),
            stderr.trim()
        );
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

/// Decide whether the orchestrator should proceed to the post-activation
/// (lock-mutation) phase, given the privileged child's exit status.
///
/// Returns `true` only when the child exited with a zero status. Any
/// non-zero exit (including signal termination, reported by `code()` as
/// `None`) MUST keep the lock untouched — this is the atomicity guarantee
/// the activate-then-mutate ordering buys us.
///
/// Pulled out as a pure function so the activation-failure branch is
/// unit-testable without mocking pkexec/keystone-approve-exec.
fn should_advance_lock(status: &std::process::ExitStatus) -> bool {
    status.success()
}

/// Drive the activation step through `cmd::approve::run_and_wait`. The
/// orchestrator-callable variant of the broker spawns the helper and
/// waits for it to exit, so we can inspect the [`std::process::ExitStatus`]
/// and gate post-activation work (relock, commit, push) on actual
/// activation success. The interactive `cmd::approve::execute` path
/// would `exec()`-replace this process and force us to perform that
/// follow-up work *before* the privileged step — which is exactly the
/// atomicity bug this commit fixes.
fn activate_via_broker(reason: &str, store_path: &str) -> Result<bool> {
    let argv = elevated_argv(store_path);
    let status = cmd::approve::run_and_wait(reason, &argv)?;
    if !should_advance_lock(&status) {
        eprintln!(
            "ks activate failed (exit {:?}) — leaving flake.lock unchanged.",
            status.code()
        );
        return Ok(false);
    }
    Ok(true)
}

/// Top-level entry. Resolves channel target → builds (no lock change)
/// → activates (privileged, awaited) → on success, relocks pinned to
/// the activated rev → commits → pushes.
///
/// Sequencing invariant: `relock_keystone_input` and `commit_lock` MUST
/// only run on the activation-success branch. A failed activation must
/// leave `flake.lock` and the working tree untouched so the next Walker
/// click retries cleanly.
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

    // Step 0: refuse to run unless the consumer flake is in sync with
    // origin. See `ensure_in_sync` for the invariant — this is the
    // only way to make the post-activation push a guaranteed
    // fast-forward.
    ensure_in_sync(&repo_root).await?;

    // Step 1: resolve the target ref via GitHub API. Runs in the
    // user's session — token + DNS available.
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
    let target_rev = info.latest_rev.clone();
    let target_tag = info.latest_tag.clone();
    // CRITICAL: use `latest_name` for the audit-trail commit message.
    // For unstable, `latest_tag` is the literal "main" — losing the
    // resolved SHA — while `latest_name` is `main@<shortsha>` and
    // preserves traceability. For stable, both coincide on the tag,
    // so this is a no-op there.
    let target_label = if info.latest_name.is_empty() {
        target_tag.clone()
    } else {
        info.latest_name.clone()
    };
    eprintln!(
        "Resolved {} channel target: {target_label} ({target_rev})",
        channel.as_str()
    );

    // Step 2: build the closure with the override. flake.lock untouched
    // up to this point; a failure here is a no-op on the consumer
    // flake's state.
    let store_path = build_with_override(&repo_root, &host, &target_rev).await?;
    eprintln!("Built closure: {store_path}");

    // Step 3: activate via the privileged broker. We *wait* for the
    // child to exit so we can decide whether to mutate the lock based
    // on whether activation actually succeeded. If it failed, return
    // an outcome that records what we built but leave the lock alone.
    let host_label = util::hostname_label();
    let reason = approval_reason(&host_label);
    eprintln!("Requesting approval to activate {store_path}…");
    let activated = activate_via_broker(&reason, &store_path)?;
    if !activated {
        return Ok(ApproveUpdateOutcome {
            host: host.clone(),
            channel: channel.as_str(),
            target_ref: target_label,
            store_path: store_path.clone(),
            lock_advanced: false,
            pushed: false,
        });
    }

    // Step 4: relock pinned to the rev we just built and activated.
    // See `relock_keystone_input` for why we use `--override-input`
    // instead of a bare `nix flake update keystone`.
    relock_keystone_input(&repo_root, &target_rev).await?;

    // Step 5: commit the lock change. If the relock didn't move the
    // lock (consumer was already on this rev), there's nothing to
    // commit and we skip straight to the push decision.
    let lock_advanced = if flake_lock_dirty(&repo_root).await? {
        commit_lock(&repo_root, &target_label).await?;
        true
    } else {
        eprintln!("flake.lock already pinned at {target_rev} — no commit needed.");
        false
    };

    // Step 6: push best-effort. A network blip post-activation
    // shouldn't fail the whole flow — the local generation is already
    // promoted to /run/current-system and the lock is committed
    // locally, so the user can recover by pushing by hand.
    let pushed = if lock_advanced {
        let branch = current_branch(&repo_root).await?;
        match push_lock(&repo_root, &branch).await {
            Ok(p) => p,
            Err(e) => {
                eprintln!(
                    "Warning: git push for branch {branch} failed to spawn: {e:#} — local lock advanced but remote is behind. Push by hand to sync.",
                );
                false
            }
        }
    } else {
        false
    };

    Ok(ApproveUpdateOutcome {
        host,
        channel: channel.as_str(),
        target_ref: target_label,
        store_path,
        lock_advanced,
        pushed,
    })
}

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
    fn should_advance_lock_only_on_zero_exit() {
        // CRITICAL atomicity guard for issue #487: the orchestrator
        // MUST NOT mutate flake.lock unless the privileged ks-activate
        // child returned a zero exit status. ExitStatus has no
        // public constructor, so we shell out to /usr/bin/env true /
        // false (or `sh -c "exit N"`) to manufacture the two cases.
        //
        // Without this guard, a polkit-declined or ks-activate-failed
        // run would leave flake.lock advanced to a rev that was never
        // promoted to /run/current-system, contradicting the
        // activate-then-mutate contract documented at the top of
        // this module.
        let success = std::process::Command::new("sh")
            .args(["-c", "exit 0"])
            .status()
            .expect("spawn `sh -c 'exit 0'` for atomicity test");
        assert!(
            should_advance_lock(&success),
            "zero exit should permit lock advance"
        );

        let failure = std::process::Command::new("sh")
            .args(["-c", "exit 7"])
            .status()
            .expect("spawn `sh -c 'exit 7'` for atomicity test");
        assert!(
            !should_advance_lock(&failure),
            "non-zero exit MUST block lock advance (atomicity invariant for issue #487)"
        );
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

    /// Build a working consumer-flake fixture: a bare "remote" repo
    /// alongside a "local" repo that has cloned + tracked it. Returns
    /// the (TempDir, local-repo-path, remote-repo-path) — TempDir keeps
    /// both alive for the test's duration. The local repo is on
    /// branch `master` with one commit, in sync with origin.
    ///
    /// CRITICAL: tests MUST pass `--initial-branch=master` to git init
    /// and rely on the bare remote's HEAD pointing there. Some host
    /// environments default to `main`; pinning the branch keeps the
    /// fixture deterministic.
    fn make_in_sync_fixture() -> (tempfile::TempDir, std::path::PathBuf, std::path::PathBuf) {
        let tmp = tempfile::tempdir().expect("create tempdir for in-sync fixture");
        let local = tmp.path().join("local");
        let remote = tmp.path().join("remote.git");

        // Remote: bare repo on `master`.
        let s = std::process::Command::new("git")
            .args(["init", "--bare", "--initial-branch=master"])
            .arg(&remote)
            .status()
            .expect("git init --bare");
        assert!(s.success(), "git init --bare failed");

        // Local: regular repo on `master`, with one commit.
        let s = std::process::Command::new("git")
            .args(["init", "--initial-branch=master"])
            .arg(&local)
            .status()
            .expect("git init local");
        assert!(s.success(), "git init local failed");

        // Identity, lest commit refuse on hosts without global config.
        for (k, v) in [
            ("user.email", "test@example.invalid"),
            ("user.name", "Test"),
            ("commit.gpgsign", "false"),
        ] {
            let s = std::process::Command::new("git")
                .arg("-C")
                .arg(&local)
                .args(["config", k, v])
                .status()
                .expect("git config");
            assert!(s.success(), "git config {k} failed");
        }

        std::fs::write(local.join("flake.lock"), "{}").expect("write flake.lock");
        for args in [
            vec!["add", "flake.lock"],
            vec!["commit", "-m", "init"],
            vec!["remote", "add", "origin"],
        ] {
            let mut cmd = std::process::Command::new("git");
            cmd.arg("-C").arg(&local).args(&args);
            if args == vec!["remote", "add", "origin"] {
                cmd.arg(&remote);
            }
            let s = cmd.status().expect("git command");
            assert!(s.success(), "git {args:?} failed");
        }
        let s = std::process::Command::new("git")
            .arg("-C")
            .arg(&local)
            .args(["push", "-u", "origin", "master"])
            .status()
            .expect("git push");
        assert!(s.success(), "git push -u origin master failed");

        (tmp, local, remote)
    }

    #[tokio::test]
    async fn ensure_in_sync_passes_when_clean_and_matching_origin() {
        // Happy path. Working tree clean, local == origin/<branch>.
        // ensure_in_sync MUST return Ok so the orchestrator can proceed
        // to channel resolution and build.
        let (_tmp, local, _remote) = make_in_sync_fixture();
        ensure_in_sync(&local)
            .await
            .expect("clean + in-sync should pass");
    }

    #[tokio::test]
    async fn ensure_in_sync_refuses_dirty_working_tree() {
        // CRITICAL: refuse if the working tree has uncommitted changes.
        // Otherwise, either the bump commit would absorb them (silent
        // data loss into a chore commit) or the commit would fail
        // partway and leave the host activated against a closure whose
        // lock isn't recorded anywhere.
        let (_tmp, local, _remote) = make_in_sync_fixture();
        std::fs::write(local.join("dirty.txt"), "uncommitted\n").expect("write dirty file");

        let err = ensure_in_sync(&local)
            .await
            .expect_err("dirty working tree must be rejected");
        let msg = format!("{err:#}");
        assert!(
            msg.contains("uncommitted changes"),
            "error should name the failure mode: {msg}"
        );
    }

    #[tokio::test]
    async fn ensure_in_sync_refuses_when_local_is_ahead_of_origin() {
        // The exact failure mode that motivated this commit: local
        // master had two cherry-picked commits beyond origin/master, so
        // the supervised flow's post-activation `git push` tripped on a
        // non-fast-forward. Refuse up front instead.
        let (_tmp, local, _remote) = make_in_sync_fixture();

        // Add a commit locally without pushing.
        std::fs::write(local.join("ahead.txt"), "ahead\n").expect("write ahead file");
        for args in [vec!["add", "ahead.txt"], vec!["commit", "-m", "ahead"]] {
            let s = std::process::Command::new("git")
                .arg("-C")
                .arg(&local)
                .args(&args)
                .status()
                .expect("git command");
            assert!(s.success(), "git {args:?} failed");
        }

        let err = ensure_in_sync(&local)
            .await
            .expect_err("ahead-of-origin must be rejected");
        let msg = format!("{err:#}");
        assert!(
            msg.contains("out of sync"),
            "error should name the failure mode: {msg}"
        );
        assert!(
            msg.contains("master"),
            "error should name the branch: {msg}"
        );
    }

    #[tokio::test]
    async fn ensure_in_sync_refuses_when_local_is_behind_origin() {
        // Symmetric to the ahead case: if origin has commits the local
        // doesn't, the lock-bump commit would be on a stale base. The
        // user almost certainly wants `git pull --rebase` first.
        let (_tmp, local, remote) = make_in_sync_fixture();

        // Make a parallel clone, push a new commit, then cleanup.
        let other = local.parent().unwrap().join("other");
        let s = std::process::Command::new("git")
            .args(["clone"])
            .arg(&remote)
            .arg(&other)
            .status()
            .expect("git clone other");
        assert!(s.success(), "git clone failed");
        for (k, v) in [
            ("user.email", "test@example.invalid"),
            ("user.name", "Test"),
            ("commit.gpgsign", "false"),
        ] {
            std::process::Command::new("git")
                .arg("-C")
                .arg(&other)
                .args(["config", k, v])
                .status()
                .expect("git config")
                .success()
                .then_some(())
                .expect("git config failed");
        }
        std::fs::write(other.join("behind.txt"), "behind\n").expect("write behind file");
        for args in [
            vec!["add", "behind.txt"],
            vec!["commit", "-m", "remote-ahead"],
            vec!["push", "origin", "master"],
        ] {
            let s = std::process::Command::new("git")
                .arg("-C")
                .arg(&other)
                .args(&args)
                .status()
                .expect("git command");
            assert!(s.success(), "git {args:?} failed");
        }

        // Now `local` is behind `origin/master`. ensure_in_sync should
        // refuse. The fetch inside ensure_in_sync will refresh
        // origin/master to the new tip.
        let err = ensure_in_sync(&local)
            .await
            .expect_err("behind-origin must be rejected");
        let msg = format!("{err:#}");
        assert!(
            msg.contains("out of sync"),
            "error should name the failure mode: {msg}"
        );
    }
}
