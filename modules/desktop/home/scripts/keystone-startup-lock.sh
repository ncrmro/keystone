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
max_lock_attempts="${KEYSTONE_STARTUP_LOCK_MAX_ATTEMPTS:-3}"
retry_delay_seconds="${KEYSTONE_STARTUP_LOCK_RETRY_DELAY:-1}"

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
  hyprlock >/dev/null 2>&1 &
  lock_pid=$!

  for _ in $(seq 1 "$timeout_steps"); do
    if lock_surface_present; then
      log info "startup lock is ready"
      return 0
    fi

    if ! kill -0 "$lock_pid" >/dev/null 2>&1; then
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
  pkill -TERM -x hyprlock >/dev/null 2>&1 || true
  return 1
}

if pgrep -x hyprlock >/dev/null 2>&1; then
  log info "hyprlock is already running"
  exit 0
fi

for attempt in $(seq 1 "$max_lock_attempts"); do
  if try_lock; then
    exit 0
  fi

  if [[ "$attempt" -lt "$max_lock_attempts" ]]; then
    log warning "hyprlock denied on attempt $attempt/$max_lock_attempts (session lock not ready), retrying in ${retry_delay_seconds}s"
    sleep "$retry_delay_seconds"
  fi
done

fail_closed "hyprlock failed to present a startup lock after $max_lock_attempts attempts."
