#!/usr/bin/env bash
# pz — Projctl Zellij session manager
#
# Usage: pz [--help] <command> [args]
#        pz <project> [<session>] [--layout <name>]
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
#   VAULT_ROOT  Root zk notebook directory
#               Defaults to $HOME/notes
#
# Session naming:
#   Default sessions are named after the project slug directly.
#   Named sub-sessions append the session slug with a hyphen.
#   Example: "pz backend-api" creates/attaches to session "backend-api"
#   Example: "pz backend-api review" creates/attaches to session "backend-api-review"
#
# Project validation:
#   A project is considered valid when an active hub note exists in the zk
#   notebook with matching `project: <slug>` frontmatter and/or `project/<slug>`
#   tag.
#
# Environment variables set inside the session:
#   PROJECT_NAME    The project slug
#   PROJECT_PATH    Absolute path to the legacy project directory
#   PROJECT_README  Absolute path to the legacy project README.md
#   VAULT_ROOT      Root directory for all projects

set -euo pipefail

VAULT_ROOT="${VAULT_ROOT:-$HOME/notes}"

usage() {
  cat <<'EOF'
pz — Projctl Zellij session manager

Usage:
  pz <project> [<session>] [--layout <name>]  Create or attach to a Zellij session
  pz list [--project <slug>]      List active project sessions
  pz agent <agent> <cmd> [args]   Run agentctl within the project context
  pz --help                       Show this help message

Options:
  -h, --help           Show this help message
  --layout <name>      Use a named zellij layout on session creation (dev, ops, write)

Environment:
  VAULT_ROOT      Root zk notebook directory (default: ~/notes)
EOF
}

valid_slug() {
  local slug="$1"
  [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

discover_projects() {
  local zk_json
  local -A seen=()
  local row note_path frontmatter_project tag_projects resolved_project

  if ! zk_json=$(zk --notebook-dir "$VAULT_ROOT" list index/ --tag status/active --format json --quiet); then
    echo "error: failed to discover active projects via zk in ${VAULT_ROOT}" >&2
    return 1
  fi

  while IFS= read -r row; do
    IFS=$'\t' read -r note_path frontmatter_project tag_projects <<< "$row"

    resolved_project=""
    if [[ -n "$frontmatter_project" ]]; then
      resolved_project="$frontmatter_project"
    fi

    if [[ -n "$tag_projects" ]]; then
      IFS=',' read -r -a project_tags <<< "$tag_projects"
      if [[ -z "$resolved_project" ]]; then
        if [[ ${#project_tags[@]} -ne 1 ]]; then
          echo "error: active project hub ${note_path} has ambiguous project tags: ${tag_projects}" >&2
          return 1
        fi
        resolved_project="${project_tags[0]}"
      else
        for tag_project in "${project_tags[@]}"; do
          if [[ "$tag_project" != "$resolved_project" ]]; then
            echo "error: active project hub ${note_path} disagrees between frontmatter project '${resolved_project}' and tag project '${tag_project}'" >&2
            return 1
          fi
        done
      fi
    fi

    if [[ -z "$resolved_project" ]]; then
      continue
    fi

    if ! valid_slug "$resolved_project"; then
      echo "error: active project hub ${note_path} uses invalid project slug '${resolved_project}'" >&2
      return 1
    fi

    if [[ -z "${seen[$resolved_project]:-}" ]]; then
      seen["$resolved_project"]=1
      printf "%s\n" "$resolved_project"
    fi
  done < <(
    printf "%s\n" "$zk_json" | jq -r '
      .[]
      | select((.metadata.type // "") == "index")
      | [
          .absPath,
          (.metadata.project // ""),
          (
            ((.tags // []) + (.metadata.tags // []))
            | map(select(type == "string" and startswith("project/")) | sub("^project/"; ""))
            | unique
            | join(",")
          )
        ]
      | @tsv
    '
  )
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

  local project_slug=""

  for candidate in "$@"; do
    if [[ "$session_name" == "$candidate" || "$session_name" == "${candidate}-"* ]]; then
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
  local project_output
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

  if ! project_output=$(discover_projects); then
    exit 1
  fi
  mapfile -t projects <<< "$project_output"

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

    project_slug=$(match_registered_project_slug "$name" "${projects[@]}")
    if [[ -z "$project_slug" ]]; then
      continue
    fi

    if [[ -n "$project_filter" && "$project_slug" != "$project_filter" ]]; then
      continue
    fi

    suffix="${name#"${project_slug}"}"
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
  local session_slug="${2:-main}"
  local layout="${3:-}"
  local project_path="${VAULT_ROOT}/projects/${slug}"
  local project_readme="${project_path}/README.md"
  local session_name="$slug"
  local existing
  local project_output

  if ! valid_slug "$slug"; then
    echo "error: invalid project slug '${slug}'" >&2
    echo "slugs must be lowercase, hyphen-separated strings" >&2
    exit 1
  fi

  if ! valid_slug "$session_slug"; then
    echo "error: invalid session slug '${session_slug}'" >&2
    echo "session slugs must be lowercase, hyphen-separated strings" >&2
    exit 1
  fi

  if [[ "$session_slug" != "main" ]]; then
    session_name="${slug}-${session_slug}"
  fi

  if ! project_output=$(discover_projects); then
    exit 1
  fi

  if ! printf "%s\n" "$project_output" | grep -Fxq "$slug"; then
    echo "error: project '${slug}' is not an active project hub in ${VAULT_ROOT}" >&2
    exit 1
  fi

  # Preserve the legacy project directory contract for session environment.
  if [[ ! -f "$project_readme" ]]; then
    echo "error: project '${slug}' not found" >&2
    echo "expected: ${project_readme}" >&2
    exit 1
  fi

  # Check if session already exists
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
    project_slug="$1"
    session_slug="main"
    if [[ $# -ge 2 ]]; then
      session_slug="$2"
    fi
    if [[ $# -gt 2 ]]; then
      echo "error: too many positional arguments" >&2
      usage >&2
      exit 1
    fi
    cmd_session "$project_slug" "$session_slug" "$LAYOUT"
    ;;
esac
