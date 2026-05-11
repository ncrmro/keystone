//! Progress emission for the `ks update --approve` supervised flow.
//!
//! When run with `--emit-progress`, `ks update --approve` writes
//! JSON-Lines to stdout at every phase boundary so a consumer
//! (Walker, future TUI, CI log scraper) can render real-time status.
//!
//! Draft for issue #508. The schema here is the *minimum* needed to
//! distinguish phases and report duration; consumer work (Walker
//! widget, layer-shell renderer) is out of scope and follows in a
//! separate PR.
//!
//! ## Schema
//!
//! One JSON object per line, written to stdout. Required fields:
//!
//! - `phase`: one of [`Phase`] values — the supervised-flow step
//! - `status`: `"start"` | `"done"` | `"error"`
//! - `ts_ms`: emitter-side monotonic-ish timestamp (unix epoch ms)
//!
//! Status-conditional fields:
//!
//! - `target` (optional, on most `start` events): the resolved
//!   keystone ref (e.g. `main@06bf415`). Empty in pre-resolve phases.
//! - `duration_ms` (on `done` and `error`): elapsed since the matching
//!   `start`.
//! - `error` (on `error`): one-line message; the full chain still
//!   goes to stderr in the existing log format.
//!
//! ## Backwards-compat
//!
//! Without `--emit-progress`, emission is a no-op — existing stderr
//! log lines are unchanged. This is so the supervised flow stays
//! quiet for users invoking `ks update --approve` directly.

use serde::Serialize;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

/// Phases of the supervised update flow. The names match the steps
/// documented in `run_supervised_update`'s docstring so changes here
/// flag a mismatch.
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    /// Step 1: `ensure_in_sync` — pre-flight git fetch + branch
    /// divergence check against origin.
    Preflight,
    /// Step 2: `resolve_target` — GitHub release / branch SHA lookup
    /// (skipped in override mode).
    Resolve,
    /// Step 3: `warm_polkit_cache` — early polkit prompt so the
    /// activation step can reuse the cached credential.
    Warm,
    /// Step 5: `bump_lock_and_commit` / `relock_keystone_input` —
    /// `nix flake update keystone`.
    Lock,
    /// Step 6: `build_locked` — `nix build` of the system closure.
    /// Typically the longest phase (60–180s).
    Build,
    /// Step 7: `activate_via_broker` — second pkexec → `ks activate`.
    /// Silent if the polkit cache from Warm holds (see PR #507).
    Activate,
    /// Step 8: `push_lock` — best-effort `git push` of the lock bump
    /// commit (channel mode only).
    Push,
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    Start,
    Done,
    Error,
}

#[derive(Serialize)]
struct Event<'a> {
    phase: Phase,
    status: Status,
    ts_ms: u128,
    #[serde(skip_serializing_if = "Option::is_none")]
    target: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    duration_ms: Option<u128>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<&'a str>,
}

/// Module-level enable flag. Set once at the start of
/// `run_supervised_update` when `--emit-progress` was passed; unset
/// otherwise. Atomic so `emit*` calls don't need a mutex.
static ENABLED: AtomicBool = AtomicBool::new(false);

pub fn enable() {
    ENABLED.store(true, Ordering::Relaxed);
}

fn now_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0)
}

fn write_line(event: &Event<'_>) {
    if !ENABLED.load(Ordering::Relaxed) {
        return;
    }
    // Errors writing to stdout are not actionable here — the consumer
    // pipe may be gone, we still want to keep running the update.
    if let Ok(line) = serde_json::to_string(event) {
        println!("{line}");
    }
}

pub fn emit_start(phase: Phase, target: Option<&str>) {
    write_line(&Event {
        phase,
        status: Status::Start,
        ts_ms: now_ms(),
        target,
        duration_ms: None,
        error: None,
    });
}

pub fn emit_done(phase: Phase, duration_ms: u128) {
    write_line(&Event {
        phase,
        status: Status::Done,
        ts_ms: now_ms(),
        target: None,
        duration_ms: Some(duration_ms),
        error: None,
    });
}

pub fn emit_error(phase: Phase, duration_ms: u128, error: &str) {
    write_line(&Event {
        phase,
        status: Status::Error,
        ts_ms: now_ms(),
        target: None,
        duration_ms: Some(duration_ms),
        error: Some(error),
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn emit_no_op_when_disabled() {
        // Default state: ENABLED is false → write_line returns without
        // panicking. We can't easily assert stdout absence here, but
        // exercising the path catches any future regressions that
        // would panic on the unset state.
        emit_start(Phase::Build, Some("test@deadbeef"));
        emit_done(Phase::Build, 1234);
        emit_error(Phase::Build, 5678, "oh no");
    }

    #[test]
    fn event_serializes_with_snake_case_phases() {
        let ev = Event {
            phase: Phase::Activate,
            status: Status::Start,
            ts_ms: 1000,
            target: Some("main@06bf415"),
            duration_ms: None,
            error: None,
        };
        let json = serde_json::to_string(&ev).unwrap();
        assert!(json.contains(r#""phase":"activate""#));
        assert!(json.contains(r#""status":"start""#));
        assert!(json.contains(r#""target":"main@06bf415""#));
        assert!(!json.contains("duration_ms"));
        assert!(!json.contains("\"error\""));
    }
}
