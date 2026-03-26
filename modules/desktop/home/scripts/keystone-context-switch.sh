#!/usr/bin/env bash
# keystone-context-switch — Fuzzy context switcher for desktop contexts
#
# Lists active zellij sessions for registered pz projects, shows dormant
# projects from the same registry, and attaches or launches via pz.

set -euo pipefail

VAULT_ROOT="${VAULT_ROOT:-$HOME/notes}"

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

project_note_json() {
  local target_slug="$1"

  zk --notebook-dir "$VAULT_ROOT" list index/ --format json --quiet 2>/dev/null | jq -c --arg slug "$target_slug" '
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

    first(
      .[]
      | select((.metadata.type // "") == "index")
      | select(inferred_project == $slug)
    )
  ' | head -n 1
}

truncate_text() {
  local text="$1"
  local limit="${2:-88}"

  if (( ${#text} <= limit )); then
    printf "%s\n" "$text"
  else
    printf "%s...\n" "${text:0:limit-3}"
  fi
}

project_mission() {
  local project_json="$1"
  local description
  local body
  local first_paragraph

  description=$(printf "%s\n" "$project_json" | jq -r '.metadata.description // ""')
  if [[ -n "$description" ]]; then
    printf "%s\n" "$description"
    return 0
  fi

  body=$(printf "%s\n" "$project_json" | jq -r '.body // ""')
  first_paragraph=$(
    printf "%s\n" "$body" | awk '
      /^## / { next }
      /^#/ { next }
      /^\|/ { next }
      /^- / { next }
      /^\s*$/ {
        if (paragraph != "") {
          print paragraph
          exit
        }
        next
      }
      {
        if (paragraph == "") {
          paragraph = $0
        } else {
          paragraph = paragraph " " $0
        }
      }
      END {
        if (paragraph != "") {
          print paragraph
        }
      }
    '
  )

  if [[ -n "$first_paragraph" ]]; then
    printf "%s\n" "$first_paragraph"
  else
    printf "No mission summary found in the project hub.\n"
  fi
}

project_milestones() {
  local project_json="$1"

  printf "%s\n" "$project_json" | jq -r '
    def milestone_entries:
      (.metadata.milestones? // empty)
      | if type == "array" then .[] else . end;

    [
      milestone_entries
      | {
          name: (.name // .title // .summary // .evidence // .description // "Milestone"),
          date: (.date // .due_date // .due // "")
        }
      | if .date != "" then "\(.date) \(.name)" else .name end
    ][0:3][]
  ' 2>/dev/null
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
    launch_project_context "$project_slug" "$session_slug"
  fi
}

show_project_details() {
  local project_slug="$1"
  local zellij_output="$2"
  local project_json
  local mission
  local entries
  local selected
  local -a milestones=()
  local -a session_entries=()
  declare -A session_actions=()
  declare -A workspace_map=()

  while IFS=$'\t' read -r ws_name ws_id; do
    [[ -z "$ws_name" ]] && continue
    if [[ "$ws_name" == name:* ]]; then
      workspace_map["${ws_name#name:}"]="$ws_id"
    fi
  done < <(hyprctl workspaces -j 2>/dev/null | jq -r '.[] | "\(.name)\t\(.id)"')

  project_json=$(project_note_json "$project_slug")
  if [[ -n "$project_json" ]]; then
    mission=$(project_mission "$project_json")
    mapfile -t milestones < <(project_milestones "$project_json")
  else
    mission="No project hub details found."
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if printf "%s\n" "$line" | grep -q "EXITED"; then
      continue
    fi

    local session_name session_slug session_title client_info workspace_label entry_label
    session_name=$(printf "%s\n" "$line" | awk '{print $1}')

    if [[ -z "$(match_project_slug "$session_name" "$project_slug")" ]]; then
      continue
    fi

    session_slug=$(session_slug_for_project "$session_name" "$project_slug")
    session_title=$(session_title_for_project "$project_slug" "$session_slug")
    client_info=$(find_client_for_title "$session_title")

    workspace_label="detached"
    if [[ -n "$client_info" ]]; then
      workspace_label="ws:${client_info#*$'\t'}"
    elif [[ "$session_slug" == "main" && -n "${workspace_map[$project_slug]:-}" ]]; then
      workspace_label="ws:${workspace_map[$project_slug]}"
    fi

    entry_label="●  ${session_slug}  ${workspace_label}"
    session_entries+=("$entry_label")
    session_actions["$entry_label"]="$session_slug"
  done <<< "$zellij_output"

  entries="←  Back\n⏵  Open main session\n✚  New session"

  if [[ ${#session_entries[@]} -gt 0 ]]; then
    while IFS= read -r entry_label; do
      [[ -z "$entry_label" ]] && continue
      entries="${entries}\n${entry_label}"
    done < <(printf "%s\n" "${session_entries[@]}" | sort -u)
  fi

  entries="${entries}\nℹ  Mission: $(truncate_text "$mission" 92)"

  if [[ ${#milestones[@]} -gt 0 ]]; then
    local milestone
    for milestone in "${milestones[@]}"; do
      entries="${entries}\n◌  Milestone: $(truncate_text "$milestone" 90)"
    done
  else
    entries="${entries}\n◌  Milestone: none listed"
  fi

  selected=$(printf "%b" "$entries" | keystone-launch-walker --dmenu --width 700 --minheight 1 --maxheight 630 -p "${project_slug}…" 2>/dev/null) || return 1
  [[ -z "$selected" ]] && return 1

  case "$selected" in
    "←  Back")
      return 1
      ;;
    "⏵  Open main session")
      focus_or_launch_project_session "$project_slug" "main"
      return 0
      ;;
    "✚  New session")
      local selected_session
      selected_session=$(prompt_for_session_slug) || return 1
      focus_or_launch_project_session "$project_slug" "${selected_session:-main}"
      return 0
      ;;
    "ℹ  "* | "◌  "*)
      show_project_details "$project_slug" "$zellij_output"
      return $?
      ;;
    *)
      if [[ -n "${session_actions[$selected]:-}" ]]; then
        focus_or_launch_project_session "$project_slug" "${session_actions[$selected]}"
        return 0
      fi
      return 1
      ;;
  esac
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
else
  selected_project=$(printf "%s\n" "$selected" | awk '{print $2}')
fi

[[ -z "$selected_project" ]] && exit 0

show_project_details "$selected_project" "$(zellij list-sessions --no-formatting 2>/dev/null || true)" || exit 0
