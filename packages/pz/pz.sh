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
  local note_path resolved_project last_active

  if ! zk_json=$(zk --notebook-dir "$VAULT_ROOT" list index/ --format json --quiet); then
    echo "error: failed to discover active projects via zk in ${VAULT_ROOT}" >&2
    return 1
  fi

  while IFS=$'\t' read -r note_path resolved_project last_active; do
    if [[ -z "$resolved_project" ]]; then
      continue
    fi

    if [[ "$resolved_project" == __AMBIGUOUS__:* ]]; then
      echo "error: active project hub ${note_path} has ambiguous project tags: ${resolved_project#__AMBIGUOUS__:}" >&2
      return 1
    fi

    if ! valid_slug "$resolved_project"; then
      echo "error: active project hub ${note_path} uses invalid project slug '${resolved_project}'" >&2
      return 1
    fi

    if [[ -z "${seen[$resolved_project]:-}" ]]; then
      seen["$resolved_project"]=1
      printf "%s\t%s\n" "$resolved_project" "$last_active"
    fi
  done < <(
    printf "%s\n" "$zk_json" | jq -r '
      def merged_tags:
        if ((.metadata.tags // []) | length) > 0 then
          (.metadata.tags // [])
        else
          (.tags // [])
        end
        | map(select(type == "string"))
        | unique;

      def explicit_project_tags:
        merged_tags
        | map(select(startswith("project/")) | sub("^project/"; ""))
        | unique;

      def bare_project_tags:
        if (merged_tags | index("project")) == null then
          []
        else
          merged_tags
          | map(
              select(
                test("^[a-z0-9]+(-[a-z0-9]+)*$")
                and . != "index"
                and . != "project"
                and . != "archive"
              )
            )
          | unique
        end;

      def status_markers:
        merged_tags
        | map(select(startswith("status/") or . == "archive"))
        | unique;

      def inferred_project:
        if (.metadata.project // "") != "" then
          .metadata.project
        elif (explicit_project_tags | length) == 1 then
          explicit_project_tags[0]
        elif (explicit_project_tags | length) > 1 then
          "__AMBIGUOUS__:" + (explicit_project_tags | join(","))
        elif (bare_project_tags | length) == 1 then
          bare_project_tags[0]
        elif (bare_project_tags | length) > 1 then
          "__AMBIGUOUS__:" + (bare_project_tags | join(","))
        else
          ""
        end;

      .[]
      | select((.metadata.type // "") == "index")
      | select((status_markers | index("status/archived")) == null)
      | select((status_markers | index("archive")) == null)
      | select((.metadata.status // "") != "archived")
      | [
          .absPath,
          inferred_project,
          (.metadata.last_active // "")
        ]
      | @tsv
    '
  )
}

project_hub_path() {
  local target_slug="$1"
  local zk_json

  if ! zk_json=$(zk --notebook-dir "$VAULT_ROOT" list index/ --format json --quiet); then
    echo "error: failed to discover project hubs via zk in ${VAULT_ROOT}" >&2
    return 1
  fi

  printf "%s\n" "$zk_json" | jq -r --arg slug "$target_slug" '
    def merged_tags:
      if ((.metadata.tags // []) | length) > 0 then
        (.metadata.tags // [])
      else
        (.tags // [])
      end
      | map(select(type == "string"))
      | unique;

    def explicit_project_tags:
      merged_tags
      | map(select(startswith("project/")) | sub("^project/"; ""))
      | unique;

    def bare_project_tags:
      if (merged_tags | index("project")) == null then
        []
      else
        merged_tags
        | map(
            select(
              test("^[a-z0-9]+(-[a-z0-9]+)*$")
              and . != "index"
              and . != "project"
              and . != "archive"
            )
          )
        | unique
      end;

    def inferred_project:
      if (.metadata.project // "") != "" then
        .metadata.project
      elif (explicit_project_tags | length) == 1 then
        explicit_project_tags[0]
      elif (bare_project_tags | length) == 1 then
        bare_project_tags[0]
      else
        ""
      end;

    .[]
    | select((.metadata.type // "") == "index")
    | select(inferred_project == $slug)
    | .absPath
  ' | head -n 1
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
  set +e
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
    set -e
    exit 1
  fi

  local -A project_last_active
  local slugs=()
  while IFS=$'\t' read -r s la; do
    [[ -z "$s" ]] && continue
    slugs+=("$s")
    project_last_active["$s"]="$la"
  done <<< "$project_output"

  local sessions
  sessions=$(zellij list-sessions --no-formatting 2>/dev/null || true)
  if [[ -z "$sessions" ]]; then
    set -e
    return 0
  fi

  # Group sessions by project
  declare -A project_sessions
  while IFS= read -r line; do
    local name project_slug session_slug status suffix
    [[ -z "$line" ]] && continue

    name=$(printf "%s\n" "$line" | awk '{print $1}')

    project_slug=$(match_registered_project_slug "$name" "${slugs[@]}")
    if [[ -z "$project_slug" ]]; then
      continue
    fi

    if [[ -n "$project_filter" && "$project_slug" != "$project_filter" ]]; then
      continue
    fi

    suffix="${name#"$project_slug"}"
    if [[ -z "$suffix" ]]; then
      session_slug="main"
    else
      session_slug="${suffix#-}"
      [[ -z "$session_slug" ]] && session_slug="main"
    fi

    status=$(session_status_from_line "$line")
    # Store sessions as a newline-separated list for each project
    project_sessions["$project_slug"]+="$session_slug|$status"$'\n'
  done <<< "$sessions"

  if [[ ${#project_sessions[@]} -eq 0 ]]; then
    set -e
    return 0
  fi

  echo "PROJECT / SESSION                                           LAST ACTIVE"
  echo "----------------------------------------------------------  -----------"

  # Sort projects by last_active descending
  local sorted_projects
  mapfile -t sorted_projects < <(
    for p in "${!project_sessions[@]}"; do
      printf "%s\t%s\n" "${project_last_active[$p]:-0000-00-00}" "$p"
    done | sort -r | cut -f2
  )

  for p in "${sorted_projects[@]}"; do
    printf "%-58s  %s\n" "$p" "${project_last_active[$p]:-}"
    
    local p_sess
    # Use sort -u to avoid duplicates like multiple "main" sessions
    mapfile -t p_sess < <(printf "%s" "${project_sessions[$p]}" | sort -u -t'|' -k1,1)
    local total=${#p_sess[@]}
    local count=0

    for sess_data in "${p_sess[@]}"; do
      ((count++))
      local s st prefix
      
      # Robustly parse s and st from sess_data
      s="${sess_data%%|*}"
      st="${sess_data#*|}"
      
      [[ -z "$s" ]] && continue
      
      if [[ $count -eq $total ]]; then
        prefix="└──"
      else
        prefix="├──"
      fi
      
      printf "  %s %-54s\n" "$prefix" "$s"
    done
  done
  set -e
}

# create or attach to a project session
cmd_session() {
  local slug="$1"
  local session_slug="${2:-main}"
  local layout="${3:-}"
  local project_path="${VAULT_ROOT}/projects/${slug}"
  local project_readme="${project_path}/README.md"
  local project_cwd="${VAULT_ROOT}"
  local session_name="$slug"
  local existing
  local project_output
  local hub_path=""

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

  if ! printf "%s\n" "$project_output" | cut -f1 | grep -Fxq "$slug"; then
    echo "error: project '${slug}' is not an active project hub in ${VAULT_ROOT}" >&2
    exit 1
  fi

  if ! hub_path=$(project_hub_path "$slug"); then
    exit 1
  fi

  if [[ -d "$project_path" ]]; then
    project_cwd="$project_path"
  fi

  # Preserve the legacy project directory contract when it still exists.
  # When projects live only in the notes repo, fall back to the hub note.
  if [[ -f "$project_readme" ]]; then
    :
  elif [[ -n "$hub_path" ]]; then
    project_readme="$hub_path"
    project_path="$VAULT_ROOT"
  else
    project_readme=""
    project_path="$VAULT_ROOT"
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

    exec zellij --session "${session_name}" "${layout_args[@]}" options --default-cwd "${project_cwd}"
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

# --- Completion Logic ---

# Generate completions for pz
__pz_complete() {
  local cur prev words cword
  _get_comp_words_by_ref -n : cur prev words cword 2>/dev/null || return 0

  local projects
  projects=$(discover_projects 2>/dev/null | cut -f1)

  if [[ $cword -eq 1 ]]; then
    # Complete project slugs or subcommands
    local opts="list agent --help completion"
    COMPREPLY=( $(compgen -W "${opts} ${projects}" -- "$cur") )
    return 0
  fi

  if [[ $cword -eq 2 ]]; then
    local project="${words[1]}"
    if [[ "$project" == "agent" ]]; then
       # Could complete agent names here if needed
       return 0
    fi
    
    # Check if we are completing a session for a valid project
    if printf "%s\n" "${projects}" | grep -Fxq "$project"; then
      local sessions
      # Find existing sessions for this project
      sessions=$(zellij list-sessions --no-formatting 2>/dev/null | awk '{print $1}' | command grep -E "^${project}(-|$)" | sed "s/^${project}-//; s/^${project}$/main/" || true)
      COMPREPLY=( $(compgen -W "${sessions} new" -- "$cur") )
      return 0
    fi
  fi
}

# The actual 'completion' command to be sourced or eval'd
cmd_completion() {
  cat <<'EOF'
_pz_completion() {
  local cur prev words cword
  if type _get_comp_words_by_ref &>/dev/null; then
    _get_comp_words_by_ref -n : cur prev words cword
  else
    # Fallback if bash-completion is not fully available
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword="$COMP_CWORD"
  fi

  local projects
  # Attempt to use pz to discover slugs, fallback to calling the script directly if needed
  if command -v pz >/dev/null 2>&1; then
    projects=$(pz discover-slugs 2>/dev/null)
  else
    return 0
  fi

  if [[ $cword -eq 1 ]]; then
    local opts="list agent --help completion"
    COMPREPLY=( $(compgen -W "${opts} ${projects}" -- "$cur") )
    return 0
  fi

  if [[ $cword -eq 2 ]]; then
    local project="${words[1]}"
    if [[ "$project" == "list" || "$project" == "agent" || "$project" == "completion" ]]; then
       return 0
    fi
    if printf "%s\n" "${projects}" | grep -Fxq "$project"; then
      local sessions
      sessions=$(zellij list-sessions --no-formatting 2>/dev/null | awk '{print $1}' | command grep -E "^${project}(-|$)" | sed "s/^${project}-//; s/^${project}$/main/" || true)
      COMPREPLY=( $(compgen -W "${sessions} new" -- "$cur") )
      return 0
    fi
  fi
}
complete -F _pz_completion pz
EOF
}

# Add a hidden helper for completion to get slugs without extra info
cmd_discover_slugs() {
  discover_projects 2>/dev/null | cut -f1
}

# --- Argument parsing ---
if [[ $# -eq 0 ]]; then
  cmd_list
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
  cmd_list
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
  completion)
    cmd_completion
    ;;
  discover-slugs)
    cmd_discover_slugs
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
