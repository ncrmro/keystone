#!/usr/bin/env bash
# keystone-project-menu — Desktop adapter for project workflows
#
# Delegates domain logic to pz CLI (terminal-first source of truth).
# Handles Hyprland window management and Walker GUI state.

set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/keystone-project-menu"
CURRENT_PROJECT_FILE="${STATE_DIR}/current-project"

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
  # Domain logic commands — delegate directly to pz
  summary|sessions|preview|export-menu-data)
    cmd="$1"
    shift
    exec pz "$cmd" "$@"
    ;;
  *)
    echo "Usage: keystone-project-menu {open|set-current-project|get-current-project|open-session-menu|summary|sessions|preview|export-menu-data} ..." >&2
    exit 1
    ;;
esac
