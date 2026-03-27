#!/usr/bin/env bash
# keystone-project-menu — Desktop adapter for project workflows
#
# Delegates domain logic to pz CLI (terminal-first source of truth).
# Handles Hyprland window management and Walker GUI state.

set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/keystone-project-menu"
CURRENT_PROJECT_FILE="${STATE_DIR}/current-project"
SNAPSHOT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/keystone/project-menu"
SNAPSHOT_PATH="${SNAPSHOT_DIR}/projects-v1.json"
SNAPSHOT_LOCK_DIR="${SNAPSHOT_DIR}/refresh.lock"
SNAPSHOT_FRESHNESS_SECONDS="${KEYSTONE_PROJECT_MENU_CACHE_FRESHNESS_SECONDS:-5}"

shell_quote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
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
      ghostty -e pz "$project_slug" &
    else
      ghostty -e pz "$project_slug" "$session_slug" &
    fi
  fi
}

cmd_open() {
  local project_slug="$1"
  local session_slug="${2:-main}"

  focus_or_launch_project_session "$project_slug" "$session_slug"
}

cmd_set_current_project() {
  local project_slug="$1"

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

  cmd_set_current_project "$project_slug"

  # Restart walker to ensure it picks up the set
  walker -q >/dev/null 2>&1 || true
  sleep 0.05
  setsid keystone-launch-walker -m "menus:keystone-project-session" -p "Session slug…" >/dev/null 2>&1 &
}

cmd_projects_json() {
  read_snapshot | jq '
    [
      .projects[]
      | {
          Text: .slug,
          Subtext: (.summary // "not running"),
          Value: .slug,
          SubMenu: "keystone-project-details",
          Preview: ("keystone-project-menu project-preview " + (.slug | @sh)),
          PreviewType: "command"
        }
    ]
  '
}

cmd_project_details_json() {
  local project_slug="$1"
  local quoted_project
  quoted_project=$(shell_quote "$project_slug")

  read_snapshot | jq -c --arg slug "$project_slug" --arg quoted "$quoted_project" '
    (.projects[] | select(.slug == $slug)) as $project
    | [
        {
          Text: "Open main session",
          Subtext: "Focus or launch the main project session",
          Value: ("open\t" + $slug + "\tmain"),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        },
        {
          Text: "New session",
          Subtext: "Type a new slug in the next step",
          Value: ("new-session-menu\t" + $slug),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        }
      ]
      + (
          ($project.sessions // [])
          | map(select(.slug != "main"))
          | map({
              Text: .slug,
              Subtext: (.status // "detached"),
              Value: ("open\t" + $slug + "\t" + .slug),
              Preview: ("keystone-project-menu project-preview " + $quoted),
              PreviewType: "command"
            })
        )
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

cmd_dispatch() {
  local payload="${1:-}"
  local action=""
  local project_slug=""
  local session_slug=""

  IFS=$'\t' read -r action project_slug session_slug <<< "$payload"

  case "$action" in
    open)
      cmd_open "$project_slug" "${session_slug:-main}"
      ;;
    new-session-menu)
      cmd_open_session_menu "$project_slug"
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
    echo "Usage: keystone-project-menu {open|set-current-project|get-current-project|open-session-menu|refresh-cache|projects-json|project-details-json|project-preview|dispatch|summary|sessions|preview|export-menu-data|export-menu-cache|menu-cache-path} ..." >&2
    exit 1
    ;;
esac
