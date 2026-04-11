#!/usr/bin/env bash
set -u -o pipefail

poll_interval_seconds="${KEYSTONE_STARTUP_LOCK_POLL_INTERVAL_SECONDS:-0.1}"
timeout_steps="${KEYSTONE_STARTUP_LOCK_TIMEOUT_STEPS:-50}"

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

if pgrep -x hyprlock >/dev/null 2>&1; then
  log info "hyprlock is already running"
  exit 0
fi

hyprlock >/dev/null 2>&1 &
lock_pid=$!

for _ in $(seq 1 "$timeout_steps"); do
  if ! kill -0 "$lock_pid" >/dev/null 2>&1; then
    wait "$lock_pid"
    lock_status=$?
    fail_closed "hyprlock exited before presenting the startup lock (status $lock_status)."
  fi

  if lock_surface_present; then
    log info "startup lock is ready"
    exit 0
  fi

  sleep "$poll_interval_seconds"
done

fail_closed "hyprlock did not present a startup lock surface within the expected time."
