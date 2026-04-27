#!/usr/bin/env bash
# pz — Projctl Zellij session manager
#
# Usage: pz [--help] <command> [args]
#        pz <project> [<session>] [--layout <name>]
#
# Commands:
#   <project>   Create or attach to a Zellij session for the given project slug
#   list        List active project sessions
#   info        Show project mission, milestones, and sessions
#   agent       Run agentctl within the project context
#
# Options:
#   --help, -h           Show this help message
#   --layout <name>      Use a named zellij layout (dev, ops, write) on session creation
#
# Session naming:
#   Default sessions are named after the project slug directly.
#   Named sub-sessions append the session slug with a hyphen.
#   Example: "pz backend-api" creates/attaches to session "backend-api"
#   Example: "pz backend-api review" creates/attaches to session "backend-api-review"
#
# Project validation:
#   A project is considered valid when it is declared in projects.yaml
#   next to the consumer flake (nixos-config).
#
# Environment variables set inside the session:
#   PROJECT_NAME    The project slug
#   PROJECT_PATH    Absolute path to the project directory
#   VAULT_ROOT      Root directory for all projects

set -euo pipefail

VAULT_ROOT="${VAULT_ROOT:-$HOME/notes}"
PZ_MENU_CACHE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/keystone/project-menu"
PZ_MENU_CACHE_PATH="${PZ_MENU_CACHE_DIR}/projects-v1.json"
PZ_ICON_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/keystone/project-icons"
PZ_LAUNCHER_STATE_DIR="${VAULT_ROOT}/.keystone"
PZ_LAUNCHER_STATE_PATH="${PZ_LAUNCHER_STATE_DIR}/launcher-state.yaml"
PZ_REMOTE_USER="${PZ_REMOTE_USER:-${USER:-}}"
if [[ -z "$PZ_REMOTE_USER" ]]; then
  PZ_REMOTE_USER="$(id -un 2>/dev/null || true)"
fi
PZ_CURRENT_HOST="$(hostname)"
PZ_DISABLE_REMOTE="${PZ_DISABLE_REMOTE:-0}"

usage() {
  cat <<'EOF'
pz — Projctl Zellij session manager

Usage:
  pz <project> [<session>] [--layout <name>] [--host <hostname>]  Create or attach to a Zellij session
  pz list [--project <slug>]      List active project sessions
  pz info <project-slug>          Show project mission, milestones, and sessions
  pz export-menu-cache [--write-state]  Export snapshot JSON for desktop menus
  pz hosts-json                   Show declared hosts as JSON
  pz get-default-host             Show this machine's default target host
  pz set-default-host <host>      Set this machine's default target host
  pz project-launch-json <slug>   Show effective host and project launch defaults
  pz project-set-host <slug> <host>  Set a project-specific target host
  pz project-set-models <slug> <provider> <model> [fallback]  Set project launch defaults
  pz project-clear-prefs <slug>   Clear project-specific launch defaults
  pz agent <agent> <cmd> [args]   Run agentctl within the project context
  pz --help                       Show this help message

Options:
  -h, --help           Show this help message
  --layout <name>      Use a named zellij layout on session creation (dev, ops, write)
  --host <hostname>    Use the selected host instead of the local machine
EOF
}

ensure_launcher_state() {
  mkdir -p "$PZ_LAUNCHER_STATE_DIR"
  if [[ -f "$PZ_LAUNCHER_STATE_PATH" ]]; then
    return 0
  fi

  cat > "$PZ_LAUNCHER_STATE_PATH" <<'EOF'
version: 1
project_hosts:
  by_origin_host: {}
interactive_defaults:
  agents: {}
  projects: {}
EOF
}

launcher_state_json() {
  ensure_launcher_state
  yq -o=json eval '.' "$PZ_LAUNCHER_STATE_PATH"
}

find_hosts_repo() {
  # The consumer flake — the only repo pz cares about — lives at the
  # canonical path $HOME/.keystone/repos/$USER/keystone-config (a
  # deterministic function of $USER and $HOME). Tests override $HOME and
  # $USER to redirect this lookup; production callers MUST NOT introduce
  # an env-var override or filesystem cascade. See
  # conventions/architecture.consumer-flake-path.md.
  local _user="${USER:-}"
  if [[ -z "$_user" ]]; then
    _user="$(id -un 2>/dev/null || true)"
  fi
  if [[ -z "$_user" ]]; then
    echo "error: cannot determine current user (\$USER unset and id failed)" >&2
    return 1
  fi
  local _root="$HOME/.keystone/repos/${_user}/keystone-config"
  if [[ -f "$_root/hosts.nix" ]]; then
    readlink -f "$_root"
    return 0
  fi

  echo "error: Keystone consumer flake not found at canonical path: $_root" >&2
  echo "  Expected hosts.nix at $_root/hosts.nix." >&2
  return 1
}

find_projects_file() {
  local repo_root
  repo_root=$(find_hosts_repo)
  local projects_file="$repo_root/projects.yaml"
  if [[ -f "$projects_file" ]]; then
    printf '%s\n' "$projects_file"
    return 0
  fi
  echo "error: no projects.yaml found in $repo_root" >&2
  return 1
}

projects_json() {
  local projects_file
  projects_file=$(find_projects_file)
  yq -o=json eval '.' "$projects_file"
}

project_yaml_json() {
  local slug="$1"
  projects_json | jq -c --arg slug "$slug" '.[$slug] // empty'
}

hosts_inventory_json() {
  local repo_root
  repo_root=$(find_hosts_repo)
  nix eval -f "$repo_root/hosts.nix" --json \
    --apply '
      hosts:
        builtins.map
          (name: {
            configName = name;
            hostname = (builtins.getAttr name hosts).hostname or "";
            sshTarget = (builtins.getAttr name hosts).sshTarget or null;
            fallbackIP = (builtins.getAttr name hosts).fallbackIP or null;
          })
          (builtins.attrNames hosts)
    '
}

validate_host_name() {
  local host="$1"
  hosts_inventory_json | jq -e --arg host "$host" 'any(.[]; .hostname == $host)' >/dev/null
}

host_ssh_target() {
  local host="$1"
  hosts_inventory_json | jq -r --arg host "$host" '
    first(.[] | select(.hostname == $host) | (.sshTarget // .hostname // ""))
  '
}

default_target_host() {
  local stored=""
  stored=$(launcher_state_json | jq -r --arg origin "$PZ_CURRENT_HOST" '
    .project_hosts.by_origin_host[$origin] // ""
  ')

  if [[ -n "$stored" ]]; then
    printf '%s\n' "$stored"
  else
    printf '%s\n' "$PZ_CURRENT_HOST"
  fi
}

set_default_target_host() {
  local host="$1"
  validate_host_name "$host" || {
    echo "error: unknown host '$host'" >&2
    return 1
  }

  ensure_launcher_state
  yq -i eval ".project_hosts.by_origin_host.\"${PZ_CURRENT_HOST}\" = \"${host}\"" "$PZ_LAUNCHER_STATE_PATH"
}

project_pref_json() {
  local project_slug="$1"
  launcher_state_json | jq -c --arg project_slug "$project_slug" '
    .interactive_defaults.projects[$project_slug] // {}
  '
}

project_effective_launch_json() {
  local project_slug="$1"
  local prefs_json effective_host
  prefs_json=$(project_pref_json "$project_slug")
  effective_host=$(printf '%s\n' "$prefs_json" | jq -r --arg default_host "$(default_target_host)" '
    .host // $default_host
  ')

  jq -cn \
    --arg project "$project_slug" \
    --arg current_host "$PZ_CURRENT_HOST" \
    --arg effective_host "$effective_host" \
    --argjson prefs "$prefs_json" '
      {
        project: $project,
        currentHost: $current_host,
        effectiveHost: $effective_host,
        provider: ($prefs.provider // ""),
        model: ($prefs.model // ""),
        fallbackModel: ($prefs.fallback_model // "")
      }
    '
}

set_project_host() {
  local project_slug="$1"
  local host="$2"
  validate_host_name "$host" || {
    echo "error: unknown host '$host'" >&2
    return 1
  }

  ensure_launcher_state
  yq -i eval ".interactive_defaults.projects.\"${project_slug}\".host = \"${host}\"" "$PZ_LAUNCHER_STATE_PATH"
}

set_project_models() {
  local project_slug="$1"
  local provider="$2"
  local model="$3"
  local fallback_model="${4:-}"

  ensure_launcher_state
  yq -i eval ".interactive_defaults.projects.\"${project_slug}\".provider = \"${provider}\"" "$PZ_LAUNCHER_STATE_PATH"
  yq -i eval ".interactive_defaults.projects.\"${project_slug}\".model = \"${model}\"" "$PZ_LAUNCHER_STATE_PATH"
  if [[ -n "$fallback_model" ]]; then
    yq -i eval ".interactive_defaults.projects.\"${project_slug}\".fallback_model = \"${fallback_model}\"" "$PZ_LAUNCHER_STATE_PATH"
  else
    yq -i eval 'del(.interactive_defaults.projects."'"${project_slug}"'".fallback_model)' "$PZ_LAUNCHER_STATE_PATH"
  fi
}

clear_project_prefs() {
  local project_slug="$1"
  ensure_launcher_state
  yq -i eval 'del(.interactive_defaults.projects."'"${project_slug}"'")' "$PZ_LAUNCHER_STATE_PATH"
}

agent_pref_json() {
  local agent_name="$1"
  launcher_state_json | jq -c --arg agent_name "$agent_name" '
    .interactive_defaults.agents[$agent_name] // {}
  '
}

set_agent_pref() {
  local agent_name="$1"
  local host="$2"
  local provider="${3:-}"
  local model="${4:-}"
  local fallback_model="${5:-}"

  validate_host_name "$host" || {
    echo "error: unknown host '$host'" >&2
    return 1
  }

  ensure_launcher_state
  yq -i eval ".interactive_defaults.agents.\"${agent_name}\".host = \"${host}\"" "$PZ_LAUNCHER_STATE_PATH"
  if [[ -n "$provider" ]]; then
    yq -i eval ".interactive_defaults.agents.\"${agent_name}\".provider = \"${provider}\"" "$PZ_LAUNCHER_STATE_PATH"
  fi
  if [[ -n "$model" ]]; then
    yq -i eval ".interactive_defaults.agents.\"${agent_name}\".model = \"${model}\"" "$PZ_LAUNCHER_STATE_PATH"
  fi
  if [[ -n "$fallback_model" ]]; then
    yq -i eval ".interactive_defaults.agents.\"${agent_name}\".fallback_model = \"${fallback_model}\"" "$PZ_LAUNCHER_STATE_PATH"
  fi
}

clear_agent_pref() {
  local agent_name="$1"
  ensure_launcher_state
  yq -i eval 'del(.interactive_defaults.agents."'"${agent_name}"'")' "$PZ_LAUNCHER_STATE_PATH"
}

run_capture_on_host() {
  local host="$1"
  shift

  if [[ "$host" == "$PZ_CURRENT_HOST" ]]; then
    "$@"
    return 0
  fi

  local target=""
  target=$(host_ssh_target "$host")
  if [[ -z "$target" ]]; then
    echo "error: host '$host' has no remote target" >&2
    return 1
  fi

  ssh -o BatchMode=yes "$target" "$@"
}

run_pz_capture_on_host() {
  local host="$1"
  shift

  if [[ "$host" == "$PZ_CURRENT_HOST" ]]; then
    "$0" "$@"
    return 0
  fi

  local target=""
  target=$(host_ssh_target "$host")
  if [[ -z "$target" ]]; then
    echo "error: host '$host' has no remote target" >&2
    return 1
  fi

  ssh -o BatchMode=yes "$target" "PZ_DISABLE_REMOTE=1 VAULT_ROOT=$(printf '%q' "$VAULT_ROOT") pz $(
    printf '%q ' "$@"
  )"
}

open_project_on_host() {
  local host="$1"
  local slug="$2"
  local session_slug="${3:-main}"
  local layout="${4:-}"

  if [[ "$host" == "$PZ_CURRENT_HOST" ]]; then
    cmd_session "$slug" "$session_slug" "$layout"
    return 0
  fi

  local target=""
  target=$(host_ssh_target "$host")
  if [[ -z "$target" ]]; then
    echo "error: host '$host' has no remote target" >&2
    return 1
  fi

  local args=()
  if [[ "$session_slug" != "main" ]]; then
    args+=("$session_slug")
  fi
  if [[ -n "$layout" ]]; then
    args+=(--layout "$layout")
  fi

  exec et "${PZ_REMOTE_USER}@${target}" -- pz "$slug" "${args[@]}"
}

valid_slug() {
  local slug="$1"
  [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

discover_projects() {
  local pj
  pj=$(projects_json)
  printf '%s\n' "$pj" | jq -r 'to_entries[] | [.key, ""] | @tsv'
}

projects_file_dir() {
  local projects_file
  projects_file=$(find_projects_file)
  dirname "$projects_file"
}

sanitize_text() {
  printf "%s" "${1//$'\t'/ }" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

project_icon_value() {
  local project_json="$1"
  printf "%s\n" "$project_json" | jq -r '.icon // ""'
}

icon_extension_from_source() {
  local source="$1"
  local candidate=""

  candidate=$(printf "%s\n" "$source" | sed 's/[?#].*$//' | awk -F/ '{print $NF}')
  if [[ "$candidate" == *.* ]]; then
    candidate=".${candidate##*.}"
  else
    candidate=""
  fi

  if [[ "$candidate" =~ ^\.[A-Za-z0-9]{1,5}$ ]]; then
    printf "%s\n" "${candidate,,}"
  else
    printf ".img\n"
  fi
}

resolve_local_icon_path() {
  local icon_value="$1"
  local hub_path="$2"
  local candidate=""

  [[ -n "$icon_value" ]] || return 1

  if [[ "$icon_value" = /* ]]; then
    candidate="$icon_value"
  elif [[ -n "$hub_path" ]]; then
    candidate="$(cd "$(dirname "$hub_path")" && realpath -m "$icon_value")"
  else
    candidate="$(realpath -m "$icon_value")"
  fi

  if [[ -f "$candidate" ]]; then
    printf "%s\n" "$candidate"
    return 0
  fi

  return 1
}

download_icon_to_cache() {
  local project_slug="$1"
  local icon_url="$2"
  local icon_ext cache_key cache_path tmp_path

  mkdir -p "$PZ_ICON_CACHE_DIR"
  icon_ext=$(icon_extension_from_source "$icon_url")
  cache_key=$(printf "%s" "$icon_url" | sha256sum | awk '{print $1}')
  cache_path="${PZ_ICON_CACHE_DIR}/${project_slug}-${cache_key}${icon_ext}"
  tmp_path="${cache_path}.tmp.$$"

  if curl -fsSL --connect-timeout 5 --max-time 20 "$icon_url" -o "$tmp_path"; then
    mv "$tmp_path" "$cache_path"
    printf "%s\n" "$cache_path"
    return 0
  fi

  rm -f "$tmp_path"
  if [[ -f "$cache_path" ]]; then
    printf "%s\n" "$cache_path"
    return 0
  fi

  return 1
}

resolve_project_icon() {
  local project_slug="$1"
  local project_json="$2"
  local base_dir="$3"
  local icon_value local_icon

  icon_value=$(project_icon_value "$project_json")
  [[ -n "$icon_value" ]] || return 1

  if [[ "$icon_value" =~ ^https?:// ]]; then
    download_icon_to_cache "$project_slug" "$icon_value"
    return $?
  fi

  # Resolve relative icon paths against the projects.yaml directory
  local dummy_path="${base_dir}/projects.yaml"
  if local_icon=$(resolve_local_icon_path "$icon_value" "$dummy_path"); then
    printf "%s\n" "$local_icon"
    return 0
  fi

  return 1
}

menu_cache_path() {
  printf "%s\n" "$PZ_MENU_CACHE_PATH"
}

cmd_menu_cache_path() {
  menu_cache_path
}

project_note_json() {
  local target_slug="$1"
  project_yaml_json "$target_slug"
}

project_mission() {
  local project_json="$1"
  printf '%s\n' "$project_json" | jq -r '.mission // "No mission defined."'
}

project_milestones() {
  local project_json="$1"

  printf "%s\n" "$project_json" | jq -r '
    [
      (.milestones // [])[0:3][]
      | if .date != "" and .date != null then "\(.date) \(.name)" else .name end
    ][]
  ' 2>/dev/null
}

cmd_info() {
  local project_slug="$1"
  local project_json
  local mission
  local milestone
  local had_milestones=0
  local had_sessions=0

  project_json=$(project_note_json "$project_slug")
  if [[ -n "$project_json" ]]; then
    mission=$(project_mission "$project_json")
  else
    mission="No project hub details found."
  fi

  printf "\033[1;34mProject:\033[0m %s\n\n" "$project_slug"
  printf "\033[1;34mMission:\033[0m\n%s\n\n" "$mission"
  printf "\033[1;34mMilestones:\033[0m\n"

  if [[ -n "$project_json" ]]; then
    while IFS= read -r milestone; do
      [[ -z "$milestone" ]] && continue
      had_milestones=1
      printf -- "- %s\n" "$(sanitize_text "$milestone")"
    done < <(project_milestones "$project_json")
  fi

  if [[ "$had_milestones" -eq 0 ]]; then
    printf -- "- none listed\n"
  fi

  printf "\n\033[1;34mActive Sessions:\033[0m\n"
  local sessions
  sessions=$(zellij list-sessions --no-formatting 2>/dev/null || true)
  
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == *"EXITED"* ]] && continue
    local session_name
    session_name=$(printf "%s\n" "$line" | awk '{print $1}')
    if [[ -n "$(match_registered_project_slug "$session_name" "$project_slug")" ]]; then
      had_sessions=1
      local session_slug status
      status=$(session_status_from_line "$line")
      if [[ "$session_name" == "$project_slug" ]]; then
        session_slug="main"
      else
        session_slug="${session_name#"$project_slug"-}"
      fi
      printf -- "- %-20s (%s)\n" "$session_slug" "$status"
    fi
  done <<< "$sessions"

  if [[ "$had_sessions" -eq 0 ]]; then
    printf -- "- none active\n"
  fi
}

cmd_sessions() {
  local target_host="${1:-$PZ_CURRENT_HOST}"
  local project_slug="${2:-}"
  local line

  if [[ -z "$project_slug" ]]; then
    echo "error: sessions requires <host> <project-slug>" >&2
    exit 1
  fi

  if [[ "$target_host" != "$PZ_CURRENT_HOST" && "$PZ_DISABLE_REMOTE" != "1" ]]; then
    run_pz_capture_on_host "$target_host" sessions "$PZ_CURRENT_HOST" "$project_slug"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" || "$line" == *"EXITED"* ]] && continue

    local session_name session_slug status
    session_name=$(printf "%s\n" "$line" | awk '{print $1}')
    if [[ -z "$(match_registered_project_slug "$session_name" "$project_slug")" ]]; then
      continue
    fi

    if [[ "$session_name" == "$project_slug" ]]; then
      session_slug="main"
    else
      session_slug="${session_name#"$project_slug"-}"
    fi

    status=$(session_status_from_line "$line")
    printf "%s\t%s\n" "$session_slug" "$status"
  done < <(zellij list-sessions --no-formatting 2>/dev/null || true)
}

cmd_summary() {
  local target_host="${1:-$PZ_CURRENT_HOST}"
  local project_slug="${2:-}"
  local count=0
  local line

  if [[ -z "$project_slug" ]]; then
    echo "error: summary requires <host> <project-slug>" >&2
    exit 1
  fi

  if [[ "$target_host" != "$PZ_CURRENT_HOST" && "$PZ_DISABLE_REMOTE" != "1" ]]; then
    run_pz_capture_on_host "$target_host" summary "$PZ_CURRENT_HOST" "$project_slug"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" || "$line" == *"EXITED"* ]] && continue

    local session_name
    session_name=$(printf "%s\n" "$line" | awk '{print $1}')
    if [[ -n "$(match_registered_project_slug "$session_name" "$project_slug")" ]]; then
      count=$((count + 1))
    fi
  done < <(zellij list-sessions --no-formatting 2>/dev/null || true)

  if [[ "$count" -eq 0 ]]; then
    printf "not running\n"
  elif [[ "$count" -eq 1 ]]; then
    printf "1 session active\n"
  else
    printf "%s sessions active\n" "$count"
  fi
}

cmd_preview() {
  local project_slug="$1"
  local project_json
  local mission
  local milestone
  local had_milestones=0
  local had_sessions=0

  project_json=$(project_note_json "$project_slug")
  if [[ -n "$project_json" ]]; then
    mission=$(project_mission "$project_json")
  else
    mission="No project hub details found."
  fi

  printf "Project: %s\n\n" "$project_slug"
  printf "Mission:\n%s\n\n" "$mission"
  printf "Milestones:\n"

  if [[ -n "$project_json" ]]; then
    while IFS= read -r milestone; do
      [[ -z "$milestone" ]] && continue
      had_milestones=1
      printf -- "- %s\n" "$(sanitize_text "$milestone")"
    done < <(project_milestones "$project_json")
  fi

  if [[ "$had_milestones" -eq 0 ]]; then
    printf -- "- none listed\n"
  fi

  printf "\nActive Sessions:\n"
  local sessions
  sessions=$(zellij list-sessions --no-formatting 2>/dev/null || true)
  
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == *"EXITED"* ]] && continue
    local session_name
    session_name=$(printf "%s\n" "$line" | awk '{print $1}')
    if [[ -n "$(match_registered_project_slug "$session_name" "$project_slug")" ]]; then
      had_sessions=1
      local session_slug status
      status=$(session_status_from_line "$line")
      if [[ "$session_name" == "$project_slug" ]]; then
        session_slug="main"
      else
        session_slug="${session_name#"$project_slug"-}"
      fi
      printf -- "- %-20s (%s)\n" "$session_slug" "$status"
    fi
  done <<< "$sessions"

  if [[ "$had_sessions" -eq 0 ]]; then
    printf -- "- none active\n"
  fi
}

cmd_export_menu_data() {
  local project_output
  local -A project_sessions_count=()
  local slugs=()

  if ! project_output=$(discover_projects); then
    exit 1
  fi

  while IFS=$'\t' read -r s _la; do
    [[ -z "$s" ]] && continue
    slugs+=("$s")
    project_sessions_count["$s"]=0
  done <<< "$project_output"

  # Bulk session count
  local sessions
  sessions=$(zellij list-sessions --no-formatting 2>/dev/null || true)
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == *"EXITED"* ]] && continue
    local session_name project_slug
    session_name=$(printf "%s\n" "$line" | awk '{print $1}')
    project_slug=$(match_registered_project_slug "$session_name" "${slugs[@]}")
    if [[ -n "$project_slug" ]]; then
      project_sessions_count["$project_slug"]=$((project_sessions_count["$project_slug"] + 1))
    fi
  done <<< "$sessions"

  for s in "${slugs[@]}"; do
    local session_label
    local count=${project_sessions_count[$s]}
    if [[ "$count" -eq 0 ]]; then
      session_label="not running"
    elif [[ "$count" -eq 1 ]]; then
      session_label="1 session active"
    else
      session_label="$count sessions active"
    fi

    printf "%s\t%s\t\n" "$s" "$session_label"
  done
}

cmd_export_menu_cache() {
  local write_state=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --write-state)
        write_state=1
        shift
        ;;
      --json)
        shift
        ;;
      *)
        echo "error: unknown option for 'export-menu-cache': $1" >&2
        exit 1
        ;;
    esac
  done

  local project_output project_slug project_json mission icon_path base_dir
  local sessions line session_name session_slug status
  local -a slugs=()
  local project_json_lines=""
  local session_json_lines=""
  local generated_at
  local payload=""

  if ! project_output=$(discover_projects); then
    exit 1
  fi

  base_dir=$(projects_file_dir)

  while IFS=$'\t' read -r project_slug _; do
    [[ -z "$project_slug" ]] && continue
    slugs+=("$project_slug")

    project_json=$(project_note_json "$project_slug")
    if [[ -n "$project_json" ]]; then
      mission=$(project_mission "$project_json")
    else
      mission="No project details found."
    fi
    icon_path=""
    if [[ -n "$project_json" ]]; then
      icon_path=$(resolve_project_icon "$project_slug" "$project_json" "$base_dir" || true)
    fi

    project_json_lines+="$(
      jq -cn \
        --arg slug "$project_slug" \
        --arg mission "$(sanitize_text "$mission")" \
        --arg icon_path "$icon_path" \
        --argjson note "${project_json:-null}" '
          {
            slug: $slug,
            mission: $mission,
            icon: $icon_path,
            milestones: (
              if ($note | type) == "object" then
                [($note.milestones // [])[0:3][]
                  | if .date != "" and .date != null then "\(.date) \(.name)" else .name end
                ]
              else
                []
              end
            ),
            last_active: ""
          }
        '
    )"$'\n'
  done <<< "$project_output"

  sessions=$(zellij list-sessions --no-formatting 2>/dev/null || true)
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == *"EXITED"* ]] && continue

    session_name=$(printf "%s\n" "$line" | awk '{print $1}')
    project_slug=$(match_registered_project_slug "$session_name" "${slugs[@]}")
    [[ -z "$project_slug" ]] && continue

    if [[ "$session_name" == "$project_slug" ]]; then
      session_slug="main"
    else
      session_slug="${session_name#"$project_slug"-}"
    fi

    status=$(session_status_from_line "$line")
    session_json_lines+="$(
      jq -cn \
        --arg project_slug "$project_slug" \
        --arg session_slug "$session_slug" \
        --arg status "$status" '
          {
            project_slug: $project_slug,
            session_slug: $session_slug,
            status: $status
          }
        '
    )"$'\n'
  done <<< "$sessions"

  generated_at=$(date --iso-8601=seconds)
  payload=$(
    jq -n \
      --arg generated_at "$generated_at" \
      --arg cache_path "$PZ_MENU_CACHE_PATH" \
      --arg current_host "$PZ_CURRENT_HOST" \
      --arg default_target_host "$(default_target_host)" \
      --argjson launcher_state "$(launcher_state_json)" \
      --argjson hosts "$(hosts_inventory_json)" \
      --argjson projects "$(printf "%s" "$project_json_lines" | jq -s '.')" \
      --argjson sessions "$(printf "%s" "$session_json_lines" | jq -s '.')" '
        {
          schema_version: 1,
          generated_at: $generated_at,
          cache_path: $cache_path,
          current_host: $current_host,
          default_target_host: $default_target_host,
          hosts: $hosts,
          projects: (
            $projects
            | sort_by(.last_active, .slug)
            | reverse
            | map(
                . as $project
                | ($sessions
                    | map(select(.project_slug == $project.slug))
                    | unique_by(.session_slug)
                    | sort_by(.session_slug)
                  ) as $project_sessions
                | ($launcher_state.interactive_defaults.projects[$project.slug].host // $default_target_host) as $effective_host
                | $project + {
                    effective_host: $effective_host,
                    sessions: (
                      $project_sessions
                      | map({
                          slug: .session_slug,
                          status: .status
                        })
                    ),
                    summary: (
                      ($project_sessions | length) as $count
                      | if $count == 0 then
                          "not running"
                        elif $count == 1 then
                          "1 session active"
                        else
                          "\($count) sessions active"
                        end
                    )
                  }
              )
          )
        }
      '
  )

  if [[ "$write_state" -eq 1 ]]; then
    local cache_path tmp_path
    cache_path=$(menu_cache_path)
    tmp_path="${cache_path}.tmp.$$"
    mkdir -p "$(dirname "$cache_path")"
    printf "%s\n" "$payload" > "$tmp_path"
    mv "$tmp_path" "$cache_path"
    printf "%s\n" "$cache_path"
    return 0
  fi

  printf "%s\n" "$payload"
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
  local target_host="$PZ_CURRENT_HOST"
  local project_output
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        if [[ $# -lt 2 ]]; then
          echo "error: --host requires a hostname argument" >&2
          exit 1
        fi
        target_host="$2"
        shift 2
        ;;
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

  if [[ "$target_host" != "$PZ_CURRENT_HOST" && "$PZ_DISABLE_REMOTE" != "1" ]]; then
    local remote_args=(list --host "$PZ_CURRENT_HOST")
    if [[ -n "$project_filter" ]]; then
      remote_args+=(--project "$project_filter")
    fi
    run_pz_capture_on_host "$target_host" "${remote_args[@]}"
    set -e
    return 0
  fi

  if ! project_output=$(discover_projects); then
    set -e
    exit 1
  fi

  local slugs=()
  while IFS=$'\t' read -r s _la; do
    [[ -z "$s" ]] && continue
    slugs+=("$s")
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
    local session_name project_slug session_slug status suffix
    [[ -z "$line" ]] && continue

    session_name=$(printf "%s\n" "$line" | awk '{print $1}')

    project_slug=$(match_registered_project_slug "$session_name" "${slugs[@]}")
    if [[ -z "$project_slug" ]]; then
      continue
    fi

    if [[ -n "$project_filter" && "$project_slug" != "$project_filter" ]]; then
      continue
    fi

    suffix="${session_name#"$project_slug"}"
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

  echo "PROJECT / SESSION"
  echo "-------------------------------------------"

  # Sort projects alphabetically
  local sorted_projects
  mapfile -t sorted_projects < <(
    for p in "${!project_sessions[@]}"; do
      printf "%s\n" "$p"
    done | sort
  )

  for p in "${sorted_projects[@]}"; do
    printf "%s\n" "$p"
    
    local p_sess
    # Use sort -u to avoid duplicates like multiple "main" sessions
    mapfile -t p_sess < <(printf "%s" "${project_sessions[$p]}" | sort -u -t'|' -k1,1)
    local total=${#p_sess[@]}
    local count=0

    for sess_data in "${p_sess[@]}"; do
      ((count++))
      local s prefix
      
      # Print the session name; the status component is not rendered here.
      s="${sess_data%%|*}"
      
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
  local target_host="${4:-$PZ_CURRENT_HOST}"
  local project_cwd="${HOME}"
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

  if ! printf "%s\n" "$project_output" | cut -f1 | grep -Fxq "$slug"; then
    echo "error: project '${slug}' is not declared in projects.yaml" >&2
    exit 1
  fi

  if [[ "$target_host" != "$PZ_CURRENT_HOST" ]]; then
    open_project_on_host "$target_host" "$slug" "$session_slug" "$layout"
    return 0
  fi

  # Check if session already exists
  existing=$(zellij list-sessions --no-formatting 2>/dev/null | awk '{print $1}' | grep -x "${session_name}" || true)

  if [[ -n "$existing" ]]; then
    # Attach to existing session — layout only applies to new sessions
    exec zellij attach "${session_name}"
  else
    # Create new session with project env vars set
    export PROJECT_NAME="${slug}"
    export VAULT_ROOT="${VAULT_ROOT:-$HOME/notes}"

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

cmd_hosts_json() {
  hosts_inventory_json
}

cmd_get_default_host() {
  default_target_host
}

cmd_set_default_host() {
  if [[ $# -ne 1 ]]; then
    echo "error: set-default-host requires <host>" >&2
    exit 1
  fi
  set_default_target_host "$1"
}

cmd_project_launch_json() {
  if [[ $# -ne 1 ]]; then
    echo "error: project-launch-json requires <project-slug>" >&2
    exit 1
  fi

  local launch_json
  launch_json=$(project_effective_launch_json "$1")
  jq -cn --argjson launch "$launch_json" --argjson hosts "$(hosts_inventory_json)" '
    $launch + { hosts: $hosts }
  '
}

cmd_project_set_host() {
  if [[ $# -ne 2 ]]; then
    echo "error: project-set-host requires <project-slug> <host>" >&2
    exit 1
  fi
  set_project_host "$1" "$2"
}

cmd_project_set_models() {
  if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "error: project-set-models requires <project-slug> <provider> <model> [fallback]" >&2
    exit 1
  fi
  set_project_models "$1" "$2" "$3" "${4:-}"
}

cmd_project_clear_prefs() {
  if [[ $# -ne 1 ]]; then
    echo "error: project-clear-prefs requires <project-slug>" >&2
    exit 1
  fi
  clear_project_prefs "$1"
}

cmd_launcher_state_json() {
  launcher_state_json
}

cmd_agent_pref_json() {
  if [[ $# -ne 1 ]]; then
    echo "error: agent-pref-json requires <agent>" >&2
    exit 1
  fi
  agent_pref_json "$1"
}

cmd_agent_set_pref() {
  if [[ $# -lt 2 || $# -gt 5 ]]; then
    echo "error: agent-set-pref requires <agent> <host> [provider] [model] [fallback]" >&2
    exit 1
  fi
  set_agent_pref "$1" "$2" "${3:-}" "${4:-}" "${5:-}"
}

cmd_agent_clear_pref() {
  if [[ $# -ne 1 ]]; then
    echo "error: agent-clear-pref requires <agent>" >&2
    exit 1
  fi
  clear_agent_pref "$1"
}

# --- Completion Logic ---

# Generate completions for pz
__pz_complete() {
  local cur words cword
  _get_comp_words_by_ref -n : cur words cword 2>/dev/null || return 0

  local projects
  projects=$(discover_projects 2>/dev/null | cut -f1)

  if [[ $cword -eq 1 ]]; then
    # Complete project slugs or subcommands
    local opts="list agent --help completion"
    mapfile -t COMPREPLY < <(compgen -W "${opts} ${projects}" -- "$cur")
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
      mapfile -t COMPREPLY < <(compgen -W "${sessions} new" -- "$cur")
      return 0
    fi
  fi
}

# The actual 'completion' command to be sourced or eval'd
cmd_completion() {
  cat <<'EOF'
if [[ -n "${ZSH_VERSION:-}" ]]; then
  _pz_completion() {
    local -a projects subcommands sessions
    local project

    projects=("${(@f)$(pz discover-slugs 2>/dev/null)}")
    subcommands=(list agent info completion)

    if (( CURRENT == 2 )); then
      compadd -- "${subcommands[@]}" "${projects[@]}"
      return 0
    fi

    local project_index=2
    if [[ -o KSH_ARRAYS ]]; then
      project_index=1
    fi
    project="${words[$project_index]}"
    case "$project" in
      list|agent|info|completion)
        return 0
        ;;
    esac

    if (( ${projects[(Ie)$project]} )); then
      sessions=("${(@f)$(
        zellij list-sessions --no-formatting 2>/dev/null \
          | awk '{print $1}' \
          | command grep -E "^${project}(-|$)" \
          | sed "s/^${project}-//; s/^${project}$/main/" || true
      )}")
      compadd -- "${sessions[@]}" new
    fi
  }

  compdef _pz_completion pz
else
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
    if command -v pz >/dev/null 2>&1; then
      projects=$(pz discover-slugs 2>/dev/null)
    else
      return 0
    fi

    if [[ $cword -eq 1 ]]; then
      local opts="list agent info --help completion"
      mapfile -t COMPREPLY < <(compgen -W "${opts} ${projects}" -- "$cur")
      return 0
    fi

    if [[ $cword -eq 2 ]]; then
      local project="${words[1]}"
      if [[ "$project" == "list" || "$project" == "agent" || "$project" == "info" || "$project" == "completion" ]]; then
         return 0
      fi
      if printf "%s\n" "${projects}" | grep -Fxq "$project"; then
        local sessions
        sessions=$(zellij list-sessions --no-formatting 2>/dev/null | awk '{print $1}' | command grep -E "^${project}(-|$)" | sed "s/^${project}-//; s/^${project}$/main/" || true)
        mapfile -t COMPREPLY < <(compgen -W "${sessions} new" -- "$cur")
        return 0
      fi
    fi
  }

  complete -F _pz_completion pz
fi
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

# Extract global flags from anywhere in args
LAYOUT=""
TARGET_HOST=""
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
    --host)
      if [[ $# -lt 2 ]]; then
        echo "error: --host requires a hostname argument" >&2
        exit 1
      fi
      TARGET_HOST="$2"
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
  summary)
    shift
    cmd_summary "$@"
    ;;
  sessions)
    shift
    cmd_sessions "$@"
    ;;
  info)
    shift
    cmd_info "$@"
    ;;
  preview)
    shift
    cmd_preview "$@"
    ;;
  export-menu-cache)
    shift
    cmd_export_menu_cache "$@"
    ;;
  hosts-json)
    shift
    cmd_hosts_json "$@"
    ;;
  get-default-host)
    shift
    cmd_get_default_host "$@"
    ;;
  set-default-host)
    shift
    cmd_set_default_host "$@"
    ;;
  project-launch-json)
    shift
    cmd_project_launch_json "$@"
    ;;
  project-set-host)
    shift
    cmd_project_set_host "$@"
    ;;
  project-set-models)
    shift
    cmd_project_set_models "$@"
    ;;
  project-clear-prefs)
    shift
    cmd_project_clear_prefs "$@"
    ;;
  launcher-state-json)
    shift
    cmd_launcher_state_json "$@"
    ;;
  agent-pref-json)
    shift
    cmd_agent_pref_json "$@"
    ;;
  agent-set-pref)
    shift
    cmd_agent_set_pref "$@"
    ;;
  agent-clear-pref)
    shift
    cmd_agent_clear_pref "$@"
    ;;
  export-menu-data)
    shift
    cmd_export_menu_data "$@"
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
  menu-cache-path)
    cmd_menu_cache_path
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
    if [[ -z "$TARGET_HOST" ]]; then
      TARGET_HOST=$(default_target_host)
    fi
    cmd_session "$project_slug" "$session_slug" "$LAYOUT" "$TARGET_HOST"
    ;;
esac
