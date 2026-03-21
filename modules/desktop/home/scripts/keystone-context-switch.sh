#!/bin/bash
# keystone-context-switch — Fuzzy context switcher for desktop contexts
#
# Queries Hyprland workspaces and zellij sessions, presents a unified list
# via Walker dmenu, and switches to the selected context.
#
# Bound to $mod+D in Hyprland bindings.

set -euo pipefail

SESSION_PREFIX="obs"
VAULT_ROOT="${VAULT_ROOT:-$HOME/notes}"

# Collect active zellij sessions matching our prefix
declare -A SESSION_MAP
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  name=$(echo "$line" | awk '{print $1}')
  if [[ "$name" == "${SESSION_PREFIX}-"* ]]; then
    slug="${name#"${SESSION_PREFIX}"-}"
    if echo "$line" | grep -q "EXITED"; then
      SESSION_MAP["$slug"]="exited"
    else
      SESSION_MAP["$slug"]="active"
    fi
  fi
done < <(zellij list-sessions --no-formatting 2>/dev/null || true)

# Collect workspace info from Hyprland
declare -A WORKSPACE_MAP
while IFS=$'\t' read -r ws_name ws_id; do
  [[ -z "$ws_name" ]] && continue
  # Named workspaces have format "name:slug", extract the slug
  if [[ "$ws_name" == name:* ]]; then
    slug="${ws_name#name:}"
    WORKSPACE_MAP["$slug"]="$ws_id"
  fi
done < <(hyprctl workspaces -j 2>/dev/null | jq -r '.[] | "\(.name)\t\(.id)"')

# Query tab names for active sessions
get_tab_names() {
  local session_name="${SESSION_PREFIX}-${1}"
  # zellij action query-tab-names requires being inside a session, so we
  # use the list-sessions output or fall back gracefully
  zellij action --session "$session_name" query-tab-names 2>/dev/null | tr '\n' ' ' || true
}

# Build the display list
entries=""

# Active contexts (sessions with or without workspaces)
for slug in $(echo "${!SESSION_MAP[@]}" | tr ' ' '\n' | sort); do
  status="${SESSION_MAP[$slug]}"
  [[ "$status" == "exited" ]] && continue

  ws_info="—"
  if [[ -n "${WORKSPACE_MAP[$slug]:-}" ]]; then
    ws_info="ws:${WORKSPACE_MAP[$slug]}"
  fi

  # Try to get tab names
  tabs=$(get_tab_names "$slug")
  tab_display=""
  if [[ -n "$tabs" ]]; then
    for tab in $tabs; do
      tab_display="${tab_display}[${tab}] "
    done
    tab_display="${tab_display% }"
  fi

  entry="●  ${slug}  ${ws_info}"
  if [[ -n "$tab_display" ]]; then
    entry="${entry}  ${tab_display}"
  fi
  entries="${entries}${entry}\n"
done

# Available projects not yet running
if [[ -d "${VAULT_ROOT}/projects" ]]; then
  for project_dir in "${VAULT_ROOT}/projects"/*/; do
    [[ ! -d "$project_dir" ]] && continue
    slug=$(basename "$project_dir")
    # Skip if already in active sessions
    if [[ -z "${SESSION_MAP[$slug]:-}" ]]; then
      entries="${entries}○  ${slug}  —  (not running)\n"
    fi
  done
fi

# Remove trailing newline
entries="${entries%\\n}"

if [[ -z "$entries" ]]; then
  notify-send "No contexts available" "No active sessions or projects found" -t 2000
  exit 0
fi

# Show fuzzy selector via Walker
selected=$(echo -e "$entries" | keystone-launch-walker --dmenu --width 500 --minheight 1 --maxheight 630 -p "Context…" 2>/dev/null) || exit 0

[[ -z "$selected" ]] && exit 0

# Parse the selected entry to extract the slug
# Format: "●  slug  ws:N  [tabs]" or "○  slug  —  (not running)"
selected_slug=$(echo "$selected" | awk '{print $2}')

if [[ -z "$selected_slug" ]]; then
  exit 0
fi

# Check if it's an active context or needs launching
if echo "$selected" | grep -q "^●"; then
  # Active context — switch to its workspace
  if [[ -n "${WORKSPACE_MAP[$selected_slug]:-}" ]]; then
    hyprctl dispatch workspace "name:${selected_slug}" >/dev/null 2>&1
  else
    # Session exists but no workspace — launch via keystone-context
    keystone-context "$selected_slug"
  fi
else
  # Not running — launch via keystone-context
  keystone-context "$selected_slug"
fi
