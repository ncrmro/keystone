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
PZ_MENU_CACHE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/keystone/project-menu"
PZ_MENU_CACHE_PATH="${PZ_MENU_CACHE_DIR}/projects-v1.json"
PZ_ICON_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/keystone/project-icons"

usage() {
  cat <<'EOF'
pz — Projctl Zellij session manager

Usage:
  pz <project> [<session>] [--layout <name>]  Create or attach to a Zellij session
  pz list [--project <slug>]      List active project sessions
  pz info <project-slug>          Show project mission, milestones, and sessions
  pz export-menu-cache [--write-state]  Export snapshot JSON for desktop menus
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

sanitize_text() {
  printf "%s" "${1//$'\t'/ }" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

project_icon_value() {
  local project_json="$1"
  printf "%s\n" "$project_json" | jq -r '.metadata.icon // ""'
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
  local hub_path="$3"
  local icon_value local_icon

  icon_value=$(project_icon_value "$project_json")
  [[ -n "$icon_value" ]] || return 1

  if [[ "$icon_value" =~ ^https?:// ]]; then
    download_icon_to_cache "$project_slug" "$icon_value"
    return $?
  fi

  if local_icon=$(resolve_local_icon_path "$icon_value" "$hub_path"); then
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
  local zk_json

  if ! zk_json=$(zk --notebook-dir "$VAULT_ROOT" list index/ --format json --quiet 2>/dev/null); then
    return 1
  fi

  printf "%s\n" "$zk_json" | jq -c --arg slug "$target_slug" '
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

project_mission() {
  local project_json="$1"
  local description
  local body
  local first_paragraph

  description=$(printf "%s\n" "$project_json" | jq -r '.metadata.description // ""')
  if [[ -n "$description" && "$description" != "null" ]]; then
    printf "%s\n" "$(sanitize_text "$description")"
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
    printf "%s\n" "$(sanitize_text "$first_paragraph")"
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
  local project_slug="$1"
  local line

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
  local project_slug="$1"
  local count=0
  local line

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

  while IFS=$'\t' read -r s la; do
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
  local arg=""

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

  local project_output project_slug project_json mission hub_path icon_path
  local sessions line session_name session_slug status
  local -a slugs=()
  local project_json_lines=""
  local session_json_lines=""
  local generated_at
  local payload=""

  if ! project_output=$(discover_projects); then
    exit 1
  fi

  while IFS=$'\t' read -r project_slug _; do
    [[ -z "$project_slug" ]] && continue
    slugs+=("$project_slug")

    hub_path=$(project_hub_path "$project_slug" || true)
    project_json=$(project_note_json "$project_slug")
    if [[ -n "$project_json" ]]; then
      mission=$(project_mission "$project_json")
    else
      mission="No project hub details found."
    fi
    icon_path=""
    if [[ -n "$project_json" ]]; then
      icon_path=$(resolve_project_icon "$project_slug" "$project_json" "$hub_path" || true)
    fi

    project_json_lines+="$(
      printf "%s\n" "$project_json" | jq -cn \
        --arg slug "$project_slug" \
        --arg mission "$(sanitize_text "$mission")" \
        --arg icon_path "$icon_path" \
        --argjson note "${project_json:-null}" '
          def milestone_lines:
            if ($note | type) != "object" then
              []
            else
              [
                (($note.metadata.milestones? // empty)
                  | if type == "array" then .[] else . end
                  | {
                      name: (.name // .title // .summary // .evidence // .description // "Milestone"),
                      date: (.date // .due_date // .due // "")
                    }
                  | if .date != "" then "\(.date) \(.name)" else .name end
                )
              ][0:3]
            end;

          {
            slug: $slug,
            mission: $mission,
            icon: $icon_path,
            milestones: milestone_lines,
            last_active: (
              if ($note | type) == "object" then
                ($note.metadata.last_active // "")
              else
                ""
              end
            )
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
      --argjson projects "$(printf "%s" "$project_json_lines" | jq -s '.')" \
      --argjson sessions "$(printf "%s" "$session_json_lines" | jq -s '.')" '
        {
          schema_version: 1,
          generated_at: $generated_at,
          cache_path: $cache_path,
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
                | $project + {
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
    cmd_session "$project_slug" "$session_slug" "$LAYOUT"
    ;;
esac
