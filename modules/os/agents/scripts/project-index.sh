#!/usr/bin/env bash
set -euo pipefail

PROJECTS_FILE="${KS_PROJECTS_FILE:-$HOME/PROJECTS.yaml}"

usage() {
  cat <<'EOF'
Usage:
  keystone-project-index list
  keystone-project-index get <slug>
  keystone-project-index normalize-repo <url>
EOF
}

valid_slug() {
  local slug="$1"
  [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

normalize_repo_url() {
  local url="$1"
  local normalized=""

  case "$url" in
    ssh://*)
      normalized="${url#ssh://}"
      normalized="${normalized#*@}"
      normalized="${normalized#*/}"
      ;;
    http://*|https://*)
      normalized="${url#http://}"
      normalized="${normalized#https://}"
      normalized="${normalized#*/}"
      ;;
    git@*:*/*)
      normalized="${url#git@}"
      normalized="${normalized#*:}"
      ;;
    *)
      echo "error: unsupported repo URL '${url}'" >&2
      return 1
      ;;
  esac

  normalized="${normalized%.git}"
  normalized="${normalized%%\?*}"
  normalized="${normalized%%#*}"

  if [[ "$normalized" != */* ]]; then
    echo "error: failed to normalize repo URL '${url}'" >&2
    return 1
  fi

  printf '%s\n' "$normalized"
}

project_index_json() {
  if [[ ! -f "$PROJECTS_FILE" ]]; then
    printf '{"projects":[],"sources":[]}\n'
    return 0
  fi

  local projects_json
  if ! projects_json=$(yq -o=json '.' "$PROJECTS_FILE" 2>/dev/null); then
    projects_json=$(yq '.' "$PROJECTS_FILE") || {
      echo "error: failed to read projects from ${PROJECTS_FILE}" >&2
      return 1
    }
  fi
  if [[ -z "$projects_json" ]]; then
    echo "error: failed to read projects from ${PROJECTS_FILE}" >&2
    return 1
  fi

  printf '%s\n' "$projects_json" | jq -c '
    {
      projects:
        [
          (.projects // [])[]
          | select((.status // "active") != "archived")
          | {
              slug: (.slug // ""),
              name: (.name // .slug // ""),
              description: (.description // ""),
              priority: (.priority // null),
              repos: ((.repos // []) | map(select(type == "string" and . != "")) | unique),
              sources: (.sources // [])
            }
          | select(.slug != "")
        ],
      sources: (.sources // [])
    }
  '
}

validate_projects() {
  local projects_json="$1"
  printf '%s\n' "$projects_json" | jq -e '
    .projects
    | all(
        if (.slug | startswith("__AMBIGUOUS__:")) then
          false
        else
          (.slug | test("^[a-z0-9]+(-[a-z0-9]+)*$"))
        end
      )
  ' >/dev/null
}

print_project_validation_error() {
  local projects_json="$1"

  local invalid
  invalid=$(printf '%s\n' "$projects_json" | jq -r '
    .projects[]
    | select((.slug | test("^[a-z0-9]+(-[a-z0-9]+)*$")) | not)
    | "error: project uses invalid slug '\''\(.slug)'\''"
  ' | head -n 1)
  if [[ -n "$invalid" ]]; then
    echo "$invalid" >&2
  fi
}

main() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
  fi

  case "$1" in
    list)
      local projects_json
      projects_json=$(project_index_json)
      if ! validate_projects "$projects_json"; then
        print_project_validation_error "$projects_json"
        exit 1
      fi
      printf '%s\n' "$projects_json"
      ;;
    get)
      if [[ $# -ne 2 ]]; then
        usage >&2
        exit 1
      fi
      if ! valid_slug "$2"; then
        echo "error: invalid project slug '$2'" >&2
        exit 1
      fi
      local projects_json
      projects_json=$(project_index_json)
      if ! validate_projects "$projects_json"; then
        print_project_validation_error "$projects_json"
        exit 1
      fi
      local project_json
      project_json=$(printf '%s\n' "$projects_json" | jq -c --arg slug "$2" '.projects[] | select(.slug == $slug)' | head -n 1)
      if [[ -z "$project_json" ]]; then
        echo "error: project '$2' not found in PROJECTS.yaml" >&2
        exit 1
      fi
      printf '%s\n' "$project_json"
      ;;
    normalize-repo)
      if [[ $# -ne 2 ]]; then
        usage >&2
        exit 1
      fi
      normalize_repo_url "$2"
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
