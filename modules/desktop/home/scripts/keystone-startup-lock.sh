#!/usr/bin/env bash
set -u -o pipefail

# SECURITY: This script is the fail-closed gate for the desktop session.
# If hyprlock does not present a lock surface within the timeout, the
# entire session is terminated rather than exposing an unlocked desktop.
#
# Do NOT increase the timeout to work around rendering issues — fix the
# rendering instead. A longer timeout means a longer window where the
# desktop could be exposed without a lock screen.
poll_interval_seconds="${KEYSTONE_STARTUP_LOCK_POLL_INTERVAL_SECONDS:-0.1}"
timeout_steps="${KEYSTONE_STARTUP_LOCK_TIMEOUT_STEPS:-50}"

# SECURITY: During session startup (greetd → uwsm → Hyprland), the
# compositor may deny the session lock while outputs are being
# reconfigured. hyprlock reports this as "yeeten" and exits non-zero.
# We retry a limited number of times to handle this transient denial,
# but still fail closed if all attempts are exhausted. Each retry is
# a full hyprlock launch + surface poll cycle — the retry count does
# NOT extend the per-attempt timeout.
max_lock_attempts="${KEYSTONE_STARTUP_LOCK_MAX_ATTEMPTS:-6}"
retry_delay_seconds="${KEYSTONE_STARTUP_LOCK_RETRY_DELAY:-2}"
# Poll monitor availability every 100ms for up to 12s by default:
# 120 steps × 0.1s = 12s.
session_ready_max_poll_attempts="${KEYSTONE_STARTUP_LOCK_SESSION_READY_TIMEOUT_STEPS:-120}"
session_ready_poll_interval_seconds="${KEYSTONE_STARTUP_LOCK_SESSION_READY_POLL_INTERVAL_SECONDS:-0.1}"
use_hyprctl_dispatch="${KEYSTONE_STARTUP_LOCK_USE_HYPRCTL_DISPATCH:-true}"
lock_dispatch_timeout_status=2

log() {
  local priority="$1"
  shift
  local message="$*"

  printf 'keystone-startup-lock: %s\n' "$message" >&2

  if command -v systemd-cat >/dev/null 2>&1; then
    printf '%s\n' "$message" | systemd-cat -t keystone-startup-lock -p "$priority"
  fi
}

lock_surface_present() {
  hyprctl layers -j 2>/dev/null | jq -e '
    .. | objects | select(
      (.namespace? // "") == "hyprlock"
      or (.class? // "") == "hyprlock"
      or (.name? // "") == "hyprlock"
    )
  ' >/dev/null
}

session_lock_prereqs_ready() {
  hyprctl monitors -j 2>/dev/null | jq -e '
    type == "array" and length > 0
  ' >/dev/null
}

wait_for_session_lock_prereqs() {
  local i
  for ((i = 1; i <= session_ready_max_poll_attempts; i++)); do
    if session_lock_prereqs_ready; then
      return 0
    fi
    sleep "$session_ready_poll_interval_seconds"
  done

  log warning "timed out waiting for Hyprland monitor readiness after ${session_ready_max_poll_attempts} polls"
  return 1
}

can_use_hyprctl_dispatch() {
  [[ "$use_hyprctl_dispatch" == "true" ]] || return 1
  command -v hyprctl >/dev/null 2>&1
}

fail_closed() {
  local reason="$1"

  log err "$reason"
  log err "Terminating the desktop session instead of exposing an unlocked desktop."

  pkill -TERM -x hyprlock >/dev/null 2>&1 || true

  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl dispatch exit >/dev/null 2>&1 || true
  fi

  if command -v uwsm >/dev/null 2>&1; then
    uwsm stop >/dev/null 2>&1 || true
  fi

  if [[ -n "${XDG_SESSION_ID:-}" ]] && command -v loginctl >/dev/null 2>&1; then
    loginctl terminate-session "$XDG_SESSION_ID" >/dev/null 2>&1 || true
  fi

  exit 1
}

try_lock() {
  local lock_pid=""
  local used_dispatch=false

  # dispatch success is advisory only; actual success is lock surface detection.
  if can_use_hyprctl_dispatch && hyprctl dispatch lockscreen >/dev/null 2>&1; then
    used_dispatch=true
    log info "requested lockscreen via hyprctl dispatch"
  else
    if [[ "$use_hyprctl_dispatch" == "true" ]]; then
      log warning "hyprctl dispatch lockscreen failed; falling back to direct hyprlock"
    fi
    # --immediate-render is a best-effort optimization to reduce compositor
    # startup races where the lock surface appears too late.
    hyprlock --immediate-render >/dev/null 2>&1 &
    lock_pid=$!
  fi

  for _ in $(seq 1 "$timeout_steps"); do
    if lock_surface_present; then
      log info "startup lock is ready"
      return 0
    fi

    if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" >/dev/null 2>&1; then
      wait "$lock_pid"
      lock_status=$?
      # hyprlock exit 0 means successful authentication — the user
      # unlocked before we polled. This is not a failure.
      if [[ "$lock_status" -eq 0 ]]; then
        log info "hyprlock exited cleanly (user authenticated)"
        return 0
      fi
      # Non-zero exit: hyprlock was denied the session lock ("yeeten")
      # or crashed. Return the status for the retry logic.
      return "$lock_status"
    fi

    sleep "$poll_interval_seconds"
  done

  # Timeout — hyprlock is running but never presented a surface.
  if [[ -n "$lock_pid" ]]; then
    kill -TERM "$lock_pid" >/dev/null 2>&1 || true
  elif [[ "$used_dispatch" == "true" ]]; then
    # Nothing to kill here: dispatch is compositor-managed and this branch only
    # happens when no lock surface appeared in time.
    log warning "hyprctl dispatch did not produce a lock surface before timeout"
    # Return code 2: dispatch path timed out without a lock surface.
    # The caller uses this to disable dispatch and fall back to direct hyprlock.
    return "$lock_dispatch_timeout_status"
  else
    pkill -TERM -x hyprlock >/dev/null 2>&1 || true
  fi
  return 1
}

if pgrep -x hyprlock >/dev/null 2>&1; then
  log info "hyprlock is already running"
  exit 0
fi

if ! wait_for_session_lock_prereqs; then
  fail_closed "Hyprland did not expose monitors before startup lock timeout."
fi

for attempt in $(seq 1 "$max_lock_attempts"); do
  try_lock
  lock_status=$?

  if [[ "$lock_status" -eq 0 ]]; then
    exit 0
  fi

  if [[ "$lock_status" -eq "$lock_dispatch_timeout_status" ]]; then
    use_hyprctl_dispatch=false
    log warning "falling back to direct hyprlock launch for subsequent attempts"
  fi

  if [[ "$attempt" -lt "$max_lock_attempts" ]]; then
    log warning "hyprlock denied on attempt $attempt/$max_lock_attempts (session lock not ready), retrying in ${retry_delay_seconds}s"
    sleep "$retry_delay_seconds"
  fi
done

fail_closed "hyprlock failed to present a startup lock after $max_lock_attempts attempts."
