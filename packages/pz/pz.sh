#!/usr/bin/env bash
# pz — Projctl Zellij session manager
#
# Usage: pz [--help] <command> [args]
#        pz <project> [--layout <name>]
#
# Commands:
#   <project>   Create or attach to a Zellij session for the given project slug
#   list        List active project sessions
#   agent       Run agentctl within the project context
#
# Options:
#   --help, -h           Show this help message
#   --layout <name>      Use a named zellij layout (dev, ops, write) on session creation
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
  pz <project> [--layout <name>]  Create or attach to a Zellij session for <project>
  pz list [--project <slug>]      List active project sessions
  pz agent <agent> <cmd> [args]   Run agentctl within the project context
  pz --help                       Show this help message

Options:
  -h, --help           Show this help message
  --layout <name>      Use a named zellij layout on session creation (dev, ops, write)

Environment:
  VAULT_ROOT      Root directory containing projects/ subdirectory (default: ~/notes)
EOF
}

discover_projects() {
  local projects_dir="${VAULT_ROOT}/projects"

  if [[ ! -d "$projects_dir" ]]; then
    return 0
  fi

  find "$projects_dir" -mindepth 2 -maxdepth 2 -type f -name README.md -print 2>/dev/null \
    | while IFS= read -r readme; do
        local project_dir slug
        project_dir=$(dirname "$readme")
        slug=$(basename "$project_dir")
        case "$slug" in
          _* )
            continue
            ;;
        esac
        printf "%s\n" "$slug"
      done \
    | sort -u
}

session_status_from_line() {
  local line="$1"

  if [[ "$line" == *"(current)"* ]]; then
    printf "attached\n"
  elif [[ "$line" == *"EXITED"* ]]; then
    printf "exited\n"
  else
    printf "detached\n"
  fi
}

match_registered_project_slug() {
  local session_name="$1"
  shift

  local suffix="${session_name#"${SESSION_PREFIX}"-}"
  local project_slug=""

  for candidate in "$@"; do
    if [[ "$suffix" == "$candidate" || "$suffix" == "${candidate}-"* ]]; then
      if [[ -z "$project_slug" || ${#candidate} -gt ${#project_slug} ]]; then
        project_slug="$candidate"
      fi
    fi
  done

  if [[ -n "$project_slug" ]]; then
    printf "%s\n" "$project_slug"
  fi
}

# list active project sessions for registered projects only
cmd_list() {
  local project_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        if [[ $# -lt 2 ]]; then
          echo "error: --project requires a slug argument" >&2
          exit 1
        fi
        project_filter="$2"
        shift 2
        ;;
      *)
        echo "error: unknown option for 'list': $1" >&2
        exit 1
        ;;
    esac
  done

  mapfile -t projects < <(discover_projects)

  echo "PROJECT                       SESSION                       STATUS"
  echo "----------------------------  ----------------------------  --------"

  if [[ ${#projects[@]} -eq 0 ]]; then
    return 0
  fi

  local sessions
  sessions=$(zellij list-sessions --no-formatting 2>/dev/null || true)
  if [[ -z "$sessions" ]]; then
    return 0
  fi

  while IFS= read -r line; do
    local name project_slug session_slug status suffix
    [[ -z "$line" ]] && continue

    name=$(printf "%s\n" "$line" | awk '{print $1}')
    if [[ "$name" != "${SESSION_PREFIX}-"* ]]; then
      continue
    fi

    project_slug=$(match_registered_project_slug "$name" "${projects[@]}")
    if [[ -z "$project_slug" ]]; then
      continue
    fi

    if [[ -n "$project_filter" && "$project_slug" != "$project_filter" ]]; then
      continue
    fi

    suffix="${name#"${SESSION_PREFIX}"-"${project_slug}"}"
    if [[ -z "$suffix" ]]; then
      session_slug="main"
    else
      session_slug="${suffix#-}"
      [[ -z "$session_slug" ]] && session_slug="main"
    fi

    status=$(session_status_from_line "$line")
    printf "%-28s  %-28s  %s\n" "$project_slug" "$session_slug" "$status"
  done <<< "$sessions"
}

# create or attach to a project session
cmd_session() {
  local slug="$1"
  local layout="${2:-}"

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
    # Attach to existing session — layout only applies to new sessions
    exec zellij attach "${session_name}"
  else
    # Create new session in the project directory with project env vars set
    export PROJECT_NAME="${slug}"
    export PROJECT_PATH="${project_path}"
    export PROJECT_README="${project_readme}"
    export VAULT_ROOT="${VAULT_ROOT}"

    local layout_args=()
    if [[ -n "$layout" ]]; then
      layout_args=(--layout "$layout")
    fi

    exec zellij --session "${session_name}" "${layout_args[@]}" options --default-cwd "${project_path}"
  fi
}

# Run agentctl with project context
cmd_agent() {
  if ! command -v agentctl >/dev/null 2>&1; then
    echo "error: agentctl command not found. Ensure you are in a keystone environment." >&2
    exit 1
  fi

  if [[ $# -lt 2 ]]; then
    echo "error: 'agent' requires <agent_name> and <cmd>" >&2
    echo "Usage: pz agent <agent_name> <cmd> [args]" >&2
    exit 1
  fi

  local agent_name="$1"; shift
  local agent_cmd="$1"; shift

  if [[ -z "${PROJECT_NAME:-}" ]]; then
    echo "error: not in a project session. Use 'pz <project>' first." >&2
    exit 1
  fi

  exec agentctl "$agent_name" "$agent_cmd" --project "$PROJECT_NAME" "$@"
}

# --- Argument parsing ---
if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

# Extract --layout flag from anywhere in args
LAYOUT=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --layout)
      if [[ $# -lt 2 ]]; then
        echo "error: --layout requires a name argument" >&2
        exit 1
      fi
      LAYOUT="$2"
      shift 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]}"

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
    shift
    cmd_list "$@"
    ;;
  agent)
    shift
    cmd_agent "$@"
    ;;
  -*)
    echo "error: unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
  *)
    cmd_session "$1" "$LAYOUT"
    ;;
esac
