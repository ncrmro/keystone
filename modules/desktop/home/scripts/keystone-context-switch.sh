#!/usr/bin/env bash
# keystone-context-switch — Fuzzy context switcher for desktop contexts
#
# Lists active zellij sessions for registered pz projects, shows dormant
# projects from the same registry, and attaches or launches via pz.

set -euo pipefail

match_project_slug() {
  local session_name="$1"
  shift

  local project_slug=""

  for candidate in "$@"; do
    if [[ "$session_name" == "$candidate" || "$session_name" == "${candidate}-"* ]]; then
      if [[ -z "$project_slug" || ${#candidate} -gt ${#project_slug} ]]; then
        project_slug="$candidate"
      fi
    elif [[ "$session_name" == "obs-${candidate}" || "$session_name" == "obs-${candidate}-"* ]]; then
      if [[ -z "$project_slug" || ${#candidate} -gt ${#project_slug} ]]; then
        project_slug="$candidate"
      fi
    fi
  done

  if [[ -n "$project_slug" ]]; then
    printf "%s\n" "$project_slug"
  fi

  return 0
}

session_slug_for_project() {
  local session_name="$1"
  local project_slug="$2"

  if [[ "$session_name" == "obs-${project_slug}" || "$session_name" == "$project_slug" ]]; then
    printf "main\n"
  elif [[ "$session_name" == "obs-${project_slug}-"* ]]; then
    printf "%s\n" "${session_name#"obs-${project_slug}-"}"
  elif [[ "$session_name" == "${project_slug}-"* ]]; then
    printf "%s\n" "${session_name#"${project_slug}-"}"
  else
    printf "main\n"
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

launch_project_context() {
  local project_slug="$1"
  local session_slug="${2:-main}"

  if [[ "$session_slug" == "main" || -z "$session_slug" ]]; then
    ghostty -e pz "$project_slug" &
  else
    ghostty -e pz "$project_slug" "$session_slug" &
  fi
}

prompt_for_session_slug() {
  printf "\n" | keystone-launch-walker --dmenu --width 500 --minheight 1 --maxheight 630 -p "Session slug (optional)…" 2>/dev/null
}

if ! command -v pz >/dev/null 2>&1; then
  notify-send "pz not found" "Project session manager (pz) is required for contexts" -t 3000
  exit 0
fi

mapfile -t project_slugs < <(pz discover-slugs 2>/dev/null)

if [[ ${#project_slugs[@]} -eq 0 ]]; then
  notify-send "No contexts available" "No projects found via pz" -t 2000
  exit 0
fi

declare -A workspace_map
while IFS=$'\t' read -r ws_name ws_id; do
  [[ -z "$ws_name" ]] && continue
  if [[ "$ws_name" == name:* ]]; then
    workspace_map["${ws_name#name:}"]="$ws_id"
  fi
done < <(hyprctl workspaces -j 2>/dev/null | jq -r '.[] | "\(.name)\t\(.id)"')

declare -A active_entries
declare -A has_active_session

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if printf "%s\n" "$line" | grep -q "EXITED"; then
    continue
  fi

  session_name=$(printf "%s\n" "$line" | awk '{print $1}')
  project_slug=$(match_project_slug "$session_name" "${project_slugs[@]}")
  [[ -z "$project_slug" ]] && continue

  has_active_session["$project_slug"]=1
  session_slug=$(session_slug_for_project "$session_name" "$project_slug")
  session_title=$(session_title_for_project "$project_slug" "$session_slug")
  client_info=$(find_client_for_title "$session_title")

  workspace_label="—"
  if [[ -n "$client_info" ]]; then
    client_workspace=${client_info#*$'\t'}
    workspace_label="ws:${client_workspace}"
  elif [[ "$session_slug" == "main" && -n "${workspace_map[$project_slug]:-}" ]]; then
    workspace_label="ws:${workspace_map[$project_slug]}"
  fi

  entry_label="●  ${project_slug}"
  if [[ "$session_slug" != "main" ]]; then
    entry_label="${entry_label} / ${session_slug}"
  fi
  entry_label="${entry_label}  ${workspace_label}"

  active_entries["$entry_label"]="${project_slug}|${session_slug}|${client_info}"
done < <(zellij list-sessions --no-formatting 2>/dev/null || true)

entries=""
if [[ ${#active_entries[@]} -gt 0 ]]; then
  while IFS= read -r entry_label; do
    [[ -z "$entry_label" ]] && continue
    entries="${entries}${entry_label}\n"
  done < <(printf "%s\n" "${!active_entries[@]}" | sort)
fi

for project_slug in "${project_slugs[@]}"; do
  if [[ -z "${has_active_session[$project_slug]:-}" ]]; then
    entries="${entries}○  ${project_slug}  —  (not running)\n"
  fi
done

entries="${entries%\\n}"

if [[ -z "$entries" ]]; then
  notify-send "No contexts available" "No active sessions or projects found" -t 2000
  exit 0
fi

selected=$(printf "%b" "$entries" | keystone-launch-walker --dmenu --width 500 --minheight 1 --maxheight 630 -p "Context…" 2>/dev/null) || exit 0
[[ -z "$selected" ]] && exit 0

if [[ "$selected" == "●  "* ]]; then
  payload="${active_entries[$selected]:-}"
  [[ -z "$payload" ]] && exit 0

  selected_project=${payload%%|*}
  rest=${payload#*|}
  selected_session=${rest%%|*}
  client_info=${rest#*|}

  if [[ -n "$client_info" ]]; then
    client_address=${client_info%%$'\t'*}
    workspace_name=${client_info#*$'\t'}
    hyprctl dispatch workspace "$workspace_name" >/dev/null 2>&1
    hyprctl dispatch focuswindow "address:${client_address}" >/dev/null 2>&1
  else
    launch_project_context "$selected_project" "$selected_session"
  fi
else
  selected_project=$(printf "%s\n" "$selected" | awk '{print $2}')
  [[ -z "$selected_project" ]] && exit 0

  selected_session=$(prompt_for_session_slug) || exit 0
  launch_project_context "$selected_project" "$selected_session"
fi
