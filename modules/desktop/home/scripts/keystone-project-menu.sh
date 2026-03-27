#!/usr/bin/env bash
# keystone-project-menu — Desktop adapter for project workflows
#
# Delegates domain logic to pz CLI (terminal-first source of truth).
# Handles Hyprland window management and Walker GUI state.

set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/keystone-project-menu"
CURRENT_PROJECT_FILE="${STATE_DIR}/current-project"
CACHE_DIR="${STATE_DIR}/cache"
CACHE_TTL_SECONDS="${KEYSTONE_PROJECT_MENU_CACHE_TTL_SECONDS:-3}"

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

cache_path_for_key() {
  local cache_key="$1"
  printf "%s/%s.cache\n" "$CACHE_DIR" "$cache_key"
}

cache_is_fresh() {
  local cache_path="$1"
  local ttl="$2"

  [[ -f "$cache_path" ]] || return 1
  (( $(date +%s) - $(stat -c %Y "$cache_path" 2>/dev/null) < ttl ))
}

write_cache() {
  local cache_path="$1"
  local payload="$2"

  mkdir -p "$CACHE_DIR"
  printf "%s" "$payload" > "${cache_path}.tmp"
  mv "${cache_path}.tmp" "$cache_path"
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
  local cache_path payload
  local project_output=""
  local -a slugs=()
  local -A project_session_lines=()
  local line=""
  local slug=""
  local summary=""
  local session_name=""
  local project_slug=""
  local session_slug=""
  local session_status=""

  cache_path=$(cache_path_for_key "projects-json-v2")
  if cache_is_fresh "$cache_path" "$CACHE_TTL_SECONDS"; then
    cat "$cache_path"
    return 0
  fi

  project_output=$(pz export-menu-data 2>/dev/null)

  while IFS=$'\t' read -r slug summary _; do
    [[ -z "$slug" ]] && continue
    slugs+=("$slug")
  done <<< "$project_output"

  while IFS= read -r line; do
    [[ -z "$line" || "$line" == *"EXITED"* ]] && continue

    session_name=$(printf "%s\n" "$line" | awk '{print $1}')
    project_slug=$(match_project_slug "$session_name" "${slugs[@]}")
    [[ -z "$project_slug" || "$session_name" == "$project_slug" ]] && continue

    session_slug="${session_name#"$project_slug"-}"
    if [[ "$line" == *"(current)"* ]]; then
      session_status="attached"
    else
      session_status="detached"
    fi

    project_session_lines["$project_slug"]+="$session_slug|$session_status"$'\n'
  done < <(zellij list-sessions --no-formatting 2>/dev/null || true)

  payload=$(
    while IFS=$'\t' read -r slug summary _; do
      [[ -z "$slug" ]] && continue

      local quoted
      quoted=$(shell_quote "$slug")

      jq -nc \
        --arg slug "$slug" \
        --arg summary "${summary:-not running}" \
        --arg quoted "$quoted" \
        '{
          Text: $slug,
          Subtext: $summary,
          Value: $slug,
          SubMenu: "keystone-project-details",
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        }'
    done <<< "$project_output" | jq -s '.'
  )

  write_cache "$cache_path" "$payload"
  printf "%s\n" "$payload"
}

cmd_project_details_json() {
  local project_slug="$1"
  local quoted_project
  local cache_path payload
  quoted_project=$(shell_quote "$project_slug")
  cache_path=$(cache_path_for_key "project-details-${project_slug}")

  if cache_is_fresh "$cache_path" "$CACHE_TTL_SECONDS"; then
    cat "$cache_path"
    return 0
  fi

  payload=$({
    jq -nc --arg slug "$project_slug" --arg quoted "$quoted_project" '{
      Text: "Open main session",
      Subtext: "Focus or launch the main project session",
      Value: ("open\t" + $slug + "\tmain"),
      Preview: ("keystone-project-menu project-preview " + $quoted),
      PreviewType: "command"
    }'

    jq -nc --arg slug "$project_slug" --arg quoted "$quoted_project" '{
      Text: "New session",
      Subtext: "Type a new slug in the next step",
      Value: ("new-session-menu\t" + $slug),
      Preview: ("keystone-project-menu project-preview " + $quoted),
      PreviewType: "command"
    }'

    keystone-project-menu sessions "$project_slug" | while IFS=$'\t' read -r session workspace; do
      [[ -z "$session" || "$session" == "main" ]] && continue

      jq -nc \
        --arg slug "$project_slug" \
        --arg quoted "$quoted_project" \
        --arg session "$session" \
        --arg workspace "$workspace" \
        '{
          Text: $session,
          Subtext: $workspace,
          Value: ("open\t" + $slug + "\t" + $session),
          Preview: ("keystone-project-menu project-preview " + $quoted),
          PreviewType: "command"
        }'
    done
  } | jq -s '.')

  write_cache "$cache_path" "$payload"
  printf "%s\n" "$payload"
}

cmd_project_preview() {
  local project_slug="$1"
  local cache_path payload
  cache_path=$(cache_path_for_key "project-preview-${project_slug}")

  if cache_is_fresh "$cache_path" "$CACHE_TTL_SECONDS"; then
    cat "$cache_path"
    return 0
  fi

  payload=$(pz preview "$project_slug")
  write_cache "$cache_path" "$payload"
  printf "%s\n" "$payload"
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
  summary|sessions|preview|export-menu-data)
    cmd="$1"
    shift
    exec pz "$cmd" "$@"
    ;;
  *)
    echo "Usage: keystone-project-menu {open|set-current-project|get-current-project|open-session-menu|projects-json|project-details-json|project-preview|dispatch|summary|sessions|preview|export-menu-data} ..." >&2
    exit 1
    ;;
esac
