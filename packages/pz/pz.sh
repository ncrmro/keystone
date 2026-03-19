#!/usr/bin/env bash
# pz — Projctl Zellij session manager
#
# Usage: pz [--help] <command> [args]
#        pz <project>
#
# Commands:
#   <project>   Create or attach to a Zellij session for the given project slug
#   list        List active project sessions
#
# Options:
#   --help, -h  Show this help message
#
# Environment:
#   VAULT_ROOT  Root directory containing projects/ subdirectory
#               Defaults to $HOME/notes
#
# Session naming:
#   Sessions are created with the prefix "obs-" followed by the project slug.
#   Example: "pz backend-api" creates/attaches to session "obs-backend-api"
#
# Project validation:
#   A project is considered valid when
#   $VAULT_ROOT/projects/<slug>/README.md exists.
#
# Environment variables set inside the session:
#   PROJECT_NAME    The project slug
#   PROJECT_PATH    Absolute path to the project directory
#   PROJECT_README  Absolute path to the project README.md
#   VAULT_ROOT      Root directory for all projects

set -euo pipefail

SESSION_PREFIX="obs"
VAULT_ROOT="${VAULT_ROOT:-$HOME/notes}"

usage() {
  cat <<'EOF'
pz — Projctl Zellij session manager

Usage:
  pz <project>    Create or attach to a Zellij session for <project>
  pz list         List active project sessions
  pz --help       Show this help message

Options:
  -h, --help      Show this help message

Environment:
  VAULT_ROOT      Root directory containing projects/ subdirectory (default: ~/notes)
EOF
}

# list active project sessions (those matching obs-* prefix)
cmd_list() {
  local sessions
  sessions=$(zellij list-sessions --no-formatting 2>/dev/null || true)
  if [[ -z "$sessions" ]]; then
    echo "(no active project sessions)"
    return 0
  fi

  echo "SLUG                          STATUS"
  echo "------------------------------  --------"
  while IFS= read -r line; do
    local name status
    name=$(echo "$line" | awk '{print $1}')
    # Filter to only sessions starting with the project prefix
    if [[ "$name" == "${SESSION_PREFIX}-"* ]]; then
      local slug="${name#${SESSION_PREFIX}-}"
      # Extract status if present in the line, otherwise mark as active
      if echo "$line" | grep -q "EXITED"; then
        status="exited"
      else
        status="active"
      fi
      printf "%-32s  %s\n" "$slug" "$status"
    fi
  done <<< "$sessions"
}

# create or attach to a project session
cmd_session() {
  local slug="$1"

  # Validate slug: only alphanumeric characters, hyphens, and underscores allowed
  if [[ ! "$slug" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "error: invalid project slug '${slug}'" >&2
    echo "slugs must contain only letters, digits, hyphens, and underscores" >&2
    exit 1
  fi

  local project_path="${VAULT_ROOT}/projects/${slug}"
  local project_readme="${project_path}/README.md"
  local session_name="${SESSION_PREFIX}-${slug}"

  # Validate project exists
  if [[ ! -f "$project_readme" ]]; then
    echo "error: project '${slug}' not found" >&2
    echo "expected: ${project_readme}" >&2
    exit 1
  fi

  # Check if session already exists
  local existing
  existing=$(zellij list-sessions --no-formatting 2>/dev/null | awk '{print $1}' | grep -x "${session_name}" || true)

  if [[ -n "$existing" ]]; then
    # Attach to existing session
    exec zellij attach "${session_name}"
  else
    # Create new session in the project directory with project env vars set
    export PROJECT_NAME="${slug}"
    export PROJECT_PATH="${project_path}"
    export PROJECT_README="${project_readme}"
    export VAULT_ROOT="${VAULT_ROOT}"
    exec zellij --session "${session_name}" options --default-cwd "${project_path}"
  fi
}

# --- Argument parsing ---
if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  list)
    cmd_list
    ;;
  -*)
    echo "error: unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
  *)
    cmd_session "$1"
    ;;
esac
