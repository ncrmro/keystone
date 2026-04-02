#!/usr/bin/env bash
# keystone-ssh-health — Shared SSH key health check for software-key sessions.
#
# Classifies the SSH agent state into one of three categories:
#   unlocked          — ssh-agent is reachable and has at least one loaded identity
#   locked            — ssh-agent is reachable but no identities are loaded
#   agent-unreachable — SSH_AUTH_SOCK is unset, missing, or ssh-add -l fails
#
# Exit codes:
#   0 — unlocked
#   1 — locked
#   2 — agent-unreachable
#
# Usage:
#   keystone-ssh-health            # prints state and exits with code
#   keystone-ssh-health --quiet    # exit code only, no output

set -euo pipefail

quiet="false"
for arg in "$@"; do
  case "$arg" in
    --quiet | -q) quiet="true" ;;
    *) ;;
  esac
done

report() {
  if [[ "$quiet" == "false" ]]; then
    printf "%s\n" "$1"
  fi
}

# Check if SSH_AUTH_SOCK is set and points to a valid socket
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
  report "agent-unreachable"
  exit 2
fi

if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
  report "agent-unreachable"
  exit 2
fi

# Query the agent for loaded identities
# ssh-add -l exits 0 when identities are loaded, 1 when none are loaded,
# and 2 when the agent is unreachable.
ssh_add_exit=0
ssh-add -l >/dev/null 2>&1 || ssh_add_exit=$?

case "$ssh_add_exit" in
  0)
    report "unlocked"
    exit 0
    ;;
  1)
    report "locked"
    exit 1
    ;;
  *)
    report "agent-unreachable"
    exit 2
    ;;
esac
