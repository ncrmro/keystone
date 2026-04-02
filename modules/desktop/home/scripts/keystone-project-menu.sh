#!/usr/bin/env bash
# keystone-project-menu — Desktop adapter for project workflows
#
# Delegates domain logic to pz CLI (terminal-first source of truth).
# Handles Hyprland window management and Walker GUI state.

set -euo pipefail

export PATH="/etc/profiles/per-user/${USER:-$(id -un 2>/dev/null || echo ncrmro)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.local/bin:${PATH:-}"

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/keystone-project-menu"
CURRENT_PROJECT_FILE="${STATE_DIR}/current-project"
SNAPSHOT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/keystone/project-menu"
SNAPSHOT_PATH="${SNAPSHOT_DIR}/projects-v1.json"
SNAPSHOT_LOCK_DIR="${SNAPSHOT_DIR}/refresh.lock"
SNAPSHOT_FRESHNESS_SECONDS="${KEYSTONE_PROJECT_MENU_CACHE_FRESHNESS_SECONDS:-5}"

keystone_cmd() {
  local command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    command -v "$command_name"
    return 0
  fi

  if [[ -x "$HOME/.local/bin/$command_name" ]]; then
    printf "%s\n" "$HOME/.local/bin/$command_name"
    return 0
  fi

  printf "Unable to locate %s\n" "$command_name" >&2
  exit 1
}

shell_quote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

normalize_project_slug() {
  local raw_value="${1:-}"
  local action=""
  local project_slug=""
  local remainder=""

  if [[ "$raw_value" == *$'\t'* ]]; then
    IFS=$'\t' read -r action project_slug remainder <<< "$raw_value"
    if [[ -n "$project_slug" ]]; then
      printf "%s\n" "$project_slug"
      return 0
    fi
  fi

  printf "%s\n" "$raw_value"
}

match_project_slug() {
  local session_name="$1"
  shift

  local project_slug=""
  local candidate=""

  for candidate in "$@"; do
    if [[ "$session_name" == "$candidate" || "$session_name" == "${candidate}-"* ]]; then
      if [[ -z "$project_slug" || ${#candidate} -gt ${#project_slug} ]]; then
        project_slug="$candidate"
      fi
    fi
  done

  printf "%s\n" "$project_slug"
}

snapshot_is_fresh() {
  [[ -f "$SNAPSHOT_PATH" ]] || return 1
  (( $(date +%s) - $(stat -c %Y "$SNAPSHOT_PATH" 2>/dev/null) < SNAPSHOT_FRESHNESS_SECONDS ))
}

refresh_snapshot_sync() {
  mkdir -p "$SNAPSHOT_DIR"
  pz export-menu-cache --write-state >/dev/null
}

refresh_snapshot_async() {
  mkdir -p "$SNAPSHOT_DIR"

  (
    if mkdir "$SNAPSHOT_LOCK_DIR" 2>/dev/null; then
      trap 'rmdir "$SNAPSHOT_LOCK_DIR" >/dev/null 2>&1 || true' EXIT
      pz export-menu-cache --write-state >/dev/null 2>&1 || true
    fi
  ) >/dev/null 2>&1 &
}

detach() {
  "$(keystone_cmd keystone-detach)" "$@"
}

ensure_snapshot() {
  if [[ -f "$SNAPSHOT_PATH" ]]; then
    if ! snapshot_is_fresh; then
      refresh_snapshot_async
    fi
    return 0
  fi

  refresh_snapshot_sync
}

read_snapshot() {
  ensure_snapshot || true

  if [[ -f "$SNAPSHOT_PATH" ]]; then
    cat "$SNAPSHOT_PATH"
  else
    printf '{"schema_version":1,"generated_at":"","projects":[]}\n'
  fi
}

project_launch_json() {
  local project_slug="$1"
  pz project-launch-json "$project_slug"
}

project_effective_host() {
  local project_slug="$1"
  project_launch_json "$project_slug" | jq -r '.effectiveHost'
}

session_title_for_project() {
  local project_slug="$1"
  local session_slug="${2:-main}"

  if [[ "$session_slug" == "main" || -z "$session_slug" ]]; then
    printf "%s\n" "$project_slug"
  else
    printf "%s-%s\n" "$project_slug" "$session_slug"
  fi
}

find_client_for_title() {
  local expected_title="$1"

  hyprctl clients -j 2>/dev/null | jq -r --arg expected_title "$expected_title" '
    map(
      select(.class == "com.mitchellh.ghostty")
      | select(.title == $expected_title or (.title | startswith($expected_title + " | ")))
    )
    | sort_by(.focusHistoryID)
    | .[0]
    | if . == null then "" else "\(.address)\t\(.workspace.name)" end
  '
}

focus_or_launch_project_session() {
  local project_slug="$1"
  local session_slug="${2:-main}"
  local target_host="${3:-$(project_effective_host "$project_slug")}"
  local session_title
  local client_info

  session_title=$(session_title_for_project "$project_slug" "$session_slug")
  client_info=$(find_client_for_title "$session_title")

  if [[ -n "$client_info" ]]; then
    local client_address workspace_name
    client_address=${client_info%%$'\t'*}
    workspace_name=${client_info#*$'\t'}
    hyprctl dispatch workspace "$workspace_name" >/dev/null 2>&1
    hyprctl dispatch focuswindow "address:${client_address}" >/dev/null 2>&1
  else
    # Delegate launch to pz (wrapped in ghostty for desktop)
    if [[ "$session_slug" == "main" || -z "$session_slug" ]]; then
      detach ghostty -e pz --host "$target_host" "$project_slug"
    else
      detach ghostty -e pz --host "$target_host" "$project_slug" "$session_slug"
    fi
  fi
}

cmd_open() {
  local project_slug="$1"
  local session_slug="${2:-main}"
  local target_host="${3:-$(project_effective_host "$project_slug")}"

  focus_or_launch_project_session "$project_slug" "$session_slug" "$target_host"
}

cmd_set_current_project() {
  local project_slug
  project_slug=$(normalize_project_slug "${1:-}")

  mkdir -p "$STATE_DIR"
  printf "%s\n" "$project_slug" > "$CURRENT_PROJECT_FILE"
}

cmd_get_current_project() {
  if [[ -f "$CURRENT_PROJECT_FILE" ]]; then
    cat "$CURRENT_PROJECT_FILE"
  fi
}

cmd_open_session_menu() {
  local project_slug="$1"
  local target_host="${2:-$(project_effective_host "$project_slug")}"
  local session_slug=""

  cmd_set_current_project "$project_slug"

  walker -q >/dev/null 2>&1 || true

  session_slug=$(
    printf '\n' \
      | "$(keystone_cmd keystone-launch-walker)" --dmenu --inputonly --placeholder "Session slug… (leave empty for main)" 2>/dev/null \
      | tr -d '\r'
  ) || true

  if [[ -z "$session_slug" ]]; then
    return 0
  fi

  if [[ "$session_slug" == "CNCLD" ]]; then
    session_slug="main"
  fi

  cmd_open "$project_slug" "$session_slug" "$target_host"
}

cmd_open_notes_menu() {
  local project_slug="$1"

  cmd_set_current_project "$project_slug"
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m "menus:keystone-project-notes" -p "Project notes" >/dev/null 2>&1 &
}

cmd_open_details_menu() {
  local project_slug="$1"

  cmd_set_current_project "$project_slug"
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m "menus:keystone-project-details" -p "Project actions" >/dev/null 2>&1 &
}

cmd_projects_json() {
  read_snapshot | jq '
    [
      .projects[]
      | {
          Text: .slug,
          Subtext: (.summary // "not running"),
          Value: ("open-details\t" + .slug),
          Icon: (.icon // ""),
          Preview: ("keystone-project-menu project-preview " + (.slug | @sh)),
          PreviewType: "command"
        }
    ]
  '
}

cmd_project_details_json() {
  local project_slug="$1"
  local project_launch
  local target_host
  local provider
  local model
  local fallback_model
  local sessions_json
  local quoted_project
  quoted_project=$(shell_quote "$project_slug")
  project_launch=$(project_launch_json "$project_slug")
  target_host=$(printf '%s\n' "$project_launch" | jq -r '.effectiveHost')
  provider=$(printf '%s\n' "$project_launch" | jq -r '.provider // ""')
  model=$(printf '%s\n' "$project_launch" | jq -r '.model // ""')
  fallback_model=$(printf '%s\n' "$project_launch" | jq -r '.fallbackModel // ""')
  sessions_json=$(pz sessions "$target_host" "$project_slug" 2>/dev/null | jq -R -s '
    split("\n")
    | map(select(length > 0))
    | map(split("\t"))
    | map({ slug: .[0], status: .[1] })
  ')

  jq -cn \
    --arg slug "$project_slug" \
    --arg quoted "$quoted_project" \
    --arg target_host "$target_host" \
    --arg provider "$provider" \
    --arg model "$model" \
    --arg fallback_model "$fallback_model" \
    --argjson sessions "${sessions_json:-[]}" '
      [
        {
          Text: "Open main session",
          Subtext: ("Focus or launch the main project session on " + $target_host),
          Value: ("open\t" + $slug + "\tmain\t" + $target_host),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        },
        {
          Text: "New session",
          Subtext: ("Type a new slug for " + $target_host),
          Value: ("new-session-menu\t" + $slug + "\t" + $target_host),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        },
        {
          Text: "Notes",
          Subtext: "Browse notes tagged to this project",
          Value: ("open-notes-menu\t" + $slug),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        },
        {
          Text: "Target host",
          Subtext: $target_host,
          Value: ("set-host-menu\t" + $slug),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        },
        {
          Text: "Set this host as machine default",
          Subtext: ("Use " + $target_host + " as the default target from this machine"),
          Value: ("set-default-host\t" + $slug + "\t" + $target_host),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        },
        {
          Text: "Provider",
          Subtext: (if $provider == "" then "unset" else $provider end),
          Value: ("set-provider-menu\t" + $slug),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        },
        {
          Text: "Model",
          Subtext: (if $model == "" then "unset" else $model end),
          Value: ("set-model-menu\t" + $slug),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        },
        {
          Text: "Fallback model",
          Subtext: (if $fallback_model == "" then "unset" else $fallback_model end),
          Value: ("set-fallback-menu\t" + $slug),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        },
        {
          Text: "Clear project launch defaults",
          Subtext: "Remove project-specific host and model overrides",
          Value: ("clear-project-prefs\t" + $slug),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        }
      ]
      + (
          $sessions
          | map(select(.slug != "main"))
          | map({
              Text: .slug,
              Subtext: ((.status // "detached") + " on " + $target_host),
              Value: ("open\t" + $slug + "\t" + .slug + "\t" + $target_host),
              Preview: ("keystone-project-menu project-preview " + $quoted),
              PreviewType: "command"
            })
        )
    '
}

cmd_set_host_menu() {
  local project_slug="$1"
  local selected=""

  selected=$(
    pz hosts-json | jq -r '.[].hostname' \
      | "$(keystone_cmd keystone-launch-walker)" --dmenu --placeholder "Target host" 2>/dev/null \
      | tr -d '\r'
  ) || true
  if [[ -z "$selected" || "$selected" == "CNCLD" ]]; then
    return 0
  fi

  pz project-set-host "$project_slug" "$selected" >/dev/null
}

cmd_set_default_host() {
  local selected_host="$2"
  pz set-default-host "$selected_host" >/dev/null
}

cmd_project_model_field() {
  local project_slug="$1"
  local field="$2"
  local launch_json provider model fallback value

  launch_json=$(project_launch_json "$project_slug")
  provider=$(printf '%s\n' "$launch_json" | jq -r '.provider // ""')
  model=$(printf '%s\n' "$launch_json" | jq -r '.model // ""')
  fallback=$(printf '%s\n' "$launch_json" | jq -r '.fallbackModel // ""')

  case "$field" in
    provider)
      value=$(
        printf 'claude\ngemini\ncodex\n' \
          | "$(keystone_cmd keystone-launch-walker)" --dmenu --placeholder "Provider" 2>/dev/null \
          | tr -d '\r'
      ) || true
      [[ -z "$value" || "$value" == "CNCLD" ]] && return 0
      provider="$value"
      ;;
    model)
      value=$(printf '\n' | "$(keystone_cmd keystone-launch-walker)" --dmenu --inputonly --placeholder "Model" 2>/dev/null | tr -d '\r') || true
      [[ "$value" == "CNCLD" ]] && return 0
      model="$value"
      ;;
    fallback)
      value=$(printf '\n' | "$(keystone_cmd keystone-launch-walker)" --dmenu --inputonly --placeholder "Fallback model" 2>/dev/null | tr -d '\r') || true
      [[ "$value" == "CNCLD" ]] && return 0
      fallback="$value"
      ;;
  esac

  if [[ -z "$provider" ]]; then
    provider="claude"
  fi
  pz project-set-models "$project_slug" "$provider" "${model:-}" "${fallback:-}" >/dev/null
}

cmd_project_notes_json() {
  local project_slug="$1"

  zk --notebook-dir "$HOME/notes" list \
    --tag project \
    --tag "$project_slug" \
    --sort modified- \
    --limit 50 \
    --format json \
    --quiet \
    | jq '
      [
        .[]
        | {
            Text: .title,
            Subtext: (
              [
                (.metadata.type // "note"),
                ((.modified // "") | split("T")[0])
              ]
              | map(select(. != ""))
              | join(" · ")
            ),
            Value: ("open-note\t" + .absPath)
          }
      ]
    '
}

cmd_project_preview() {
  local project_slug="$1"
  read_snapshot | jq -r --arg slug "$project_slug" '
    first(.projects[] | select(.slug == $slug)) as $project
    | if $project == null then
        "Project: \($slug)\n\nMission:\nNo project hub details found.\n\nMilestones:\n- none listed\n\nActive Sessions:\n- none active"
      else
        (
          [
            "Project: \($project.slug)",
            "",
            "Mission:",
            ($project.mission // "No project hub details found."),
            "",
            "Milestones:"
          ]
          + (
              if (($project.milestones // []) | length) > 0 then
                ($project.milestones | map("- " + .))
              else
                ["- none listed"]
              end
            )
          + [
              "",
              "Active Sessions:"
            ]
          + (
              if (($project.sessions // []) | length) > 0 then
                ($project.sessions | map("- " + .slug + " (" + (.status // "detached") + ")"))
              else
                ["- none active"]
              end
            )
          | join("\n")
        )
      end
  '
}

cmd_refresh_cache() {
  refresh_snapshot_sync
  printf "%s\n" "$SNAPSHOT_PATH"
}

cmd_open_note() {
  local note_path="$1"

  detach ghostty -e zk --notebook-dir "$HOME/notes" edit "$note_path"
}

cmd_dispatch() {
  local payload="${1:-}"
  local action=""
  local project_slug=""
  local session_slug=""
  local target_host=""

  IFS=$'\t' read -r action project_slug session_slug target_host <<< "$payload"

  case "$action" in
    open)
      cmd_open "$project_slug" "${session_slug:-main}" "${target_host:-$(project_effective_host "$project_slug")}"
      ;;
    open-details)
      cmd_open_details_menu "$project_slug"
      ;;
    new-session-menu)
      cmd_open_session_menu "$project_slug" "${session_slug:-$(project_effective_host "$project_slug")}"
      ;;
    open-notes-menu)
      cmd_open_notes_menu "$project_slug"
      ;;
    set-host-menu)
      cmd_set_host_menu "$project_slug"
      ;;
    set-default-host)
      cmd_set_default_host "$project_slug" "$session_slug"
      ;;
    set-provider-menu)
      cmd_project_model_field "$project_slug" provider
      ;;
    set-model-menu)
      cmd_project_model_field "$project_slug" model
      ;;
    set-fallback-menu)
      cmd_project_model_field "$project_slug" fallback
      ;;
    clear-project-prefs)
      pz project-clear-prefs "$project_slug" >/dev/null
      ;;
    open-note)
      cmd_open_note "$project_slug"
      ;;
    *)
      printf "Unknown dispatch action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

case "${1:-}" in
  open)
    shift
    cmd_open "$@"
    ;;
  set-current-project)
    shift
    cmd_set_current_project "$@"
    ;;
  get-current-project)
    shift
    cmd_get_current_project "$@"
    ;;
  open-session-menu)
    shift
    cmd_open_session_menu "$@"
    ;;
  refresh-cache)
    shift
    cmd_refresh_cache "$@"
    ;;
  projects-json)
    shift
    cmd_projects_json "$@"
    ;;
  project-details-json)
    shift
    cmd_project_details_json "$@"
    ;;
  project-notes-json)
    shift
    cmd_project_notes_json "$@"
    ;;
  project-preview)
    shift
    cmd_project_preview "$@"
    ;;
  dispatch)
    shift
    cmd_dispatch "$@"
    ;;
  # Domain logic commands — delegate directly to pz
  summary|sessions|preview|export-menu-data|export-menu-cache|menu-cache-path)
    cmd="$1"
    shift
    exec pz "$cmd" "$@"
    ;;
  *)
    echo "Usage: keystone-project-menu {open|set-current-project|get-current-project|open-session-menu|refresh-cache|projects-json|project-details-json|project-notes-json|project-preview|dispatch|summary|sessions|preview|export-menu-data|export-menu-cache|menu-cache-path} ..." >&2
    exit 1
    ;;
esac
