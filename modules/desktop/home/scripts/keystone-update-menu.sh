#!/usr/bin/env bash
# keystone-update-menu — Walker/Elephant controller for Keystone OS release updates.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SCRIPT_REPO_ROOT="$(readlink -f "${SCRIPT_DIR}/../../../..")"

KEYSTONE_RELEASE_OWNER="ncrmro"
KEYSTONE_RELEASE_REPO="keystone"

notify() {
  notify-send "$@"
}

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

detach() {
  "$(keystone_cmd keystone-detach)" "$@"
}

current_hostname() {
  if [[ -n "${KEYSTONE_CONFIG_HOST:-}" ]]; then
    printf "%s\n" "$KEYSTONE_CONFIG_HOST"
    return 0
  fi

  uname -n
}

host_registry_json() {
  local repo_root="$1"
  nix eval --json --file "${repo_root}/hosts.nix"
}

current_host_key() {
  local repo_root="$1"
  local hostname=""

  hostname=$(current_hostname)
  host_registry_json "$repo_root" | jq -r --arg hostname "$hostname" '
    to_entries[]
    | select(.value.hostname == $hostname)
    | .key
  ' | head -n1
}

terminal_command_literal() {
  local parts=()
  local arg=""

  for arg in "$@"; do
    parts+=("$(printf '%q' "$arg")")
  done

  printf '%s' "${parts[*]}"
}

launch_terminal_command() {
  local title="$1"
  local command_literal="$2"
  local shell_cmd=""

  shell_cmd="${command_literal}; status=\$?; printf '\\n'; if [[ \$status -eq 0 ]]; then echo 'Command finished successfully.'; else echo \"Command failed with status \$status.\"; fi; read -r -n 1 -s -p 'Press any key to close...'; exit \$status"
  detach "$(keystone_cmd ghostty)" --title "$title" -e bash -lc "$shell_cmd"
}

github_api() {
  local path="$1"

  if command -v gh >/dev/null 2>&1; then
    gh api -H "Accept: application/vnd.github+json" "$path"
    return 0
  fi

  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/${path}"
}

resolve_input_node_id() {
  local repo_root="$1"
  local input_name="$2"

  jq -r --arg input_name "$input_name" '
    . as $lock
    | .nodes.root.inputs[$input_name] as $root_input
    | if ($root_input | type) == "string" then
        $root_input
      elif ($root_input | type) == "array" and ($root_input | length) == 2 then
        $lock.nodes[$root_input[0]].inputs[$root_input[1]]
      else
        empty
      end
  ' "${repo_root}/flake.lock"
}

discover_keystone_input_name() {
  local repo_root="$1"
  local matches=()

  mapfile -t matches < <(
    jq -r '
      def resolve_node($lock; $value):
        if ($value | type) == "string" then
          $value
        elif ($value | type) == "array" and ($value | length) == 2 then
          $lock.nodes[$value[0]].inputs[$value[1]]
        else
          empty
        end;

      . as $lock
      | [
          $lock.nodes.root.inputs
          | to_entries[]
          | .key as $key
          | resolve_node($lock; .value) as $node_id
          | select($node_id != null and $node_id != "")
          | ($lock.nodes[$node_id].locked // {}) as $locked
          | select($locked.type == "github" and $locked.owner == "'"${KEYSTONE_RELEASE_OWNER}"'" and $locked.repo == "'"${KEYSTONE_RELEASE_REPO}"'")
          | $key
        ]
      | .[]
    ' "${repo_root}/flake.lock"
  )

  if [[ "${#matches[@]}" -ne 1 ]]; then
    return 1
  fi

  printf "%s\n" "${matches[0]}"
}

current_locked_rev() {
  local repo_root="$1"
  local input_name="$2"
  local node_id=""

  node_id=$(resolve_input_node_id "$repo_root" "$input_name")
  if [[ -z "$node_id" ]]; then
    return 1
  fi

  jq -r --arg node_id "$node_id" '
    .nodes[$node_id].locked.rev // empty
  ' "${repo_root}/flake.lock"
}

current_locked_type() {
  local repo_root="$1"
  local input_name="$2"
  local node_id=""

  node_id=$(resolve_input_node_id "$repo_root" "$input_name")
  if [[ -z "$node_id" ]]; then
    return 1
  fi

  jq -r --arg node_id "$node_id" '
    .nodes[$node_id].locked.type // empty
  ' "${repo_root}/flake.lock"
}

repo_is_clean() {
  local repo_root="$1"

  [[ -z "$(git -C "$repo_root" status --porcelain --untracked-files=normal 2>/dev/null || true)" ]]
}

current_release_tag_for_rev() {
  local rev="$1"

  git -C "$SCRIPT_REPO_ROOT" tag --points-at "$rev" 2>/dev/null \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -Vr \
    | head -n1 || true
}

rev_exists_locally() {
  local rev="$1"
  git -C "$SCRIPT_REPO_ROOT" cat-file -e "${rev}^{commit}" >/dev/null 2>&1
}

rev_is_ancestor_of() {
  local older="$1"
  local newer="$2"

  git -C "$SCRIPT_REPO_ROOT" merge-base --is-ancestor "$older" "$newer" >/dev/null 2>&1
}

fetch_latest_release_json() {
  github_api "repos/${KEYSTONE_RELEASE_OWNER}/${KEYSTONE_RELEASE_REPO}/releases/latest"
}

fetch_release_commit_rev() {
  local tag_name="$1"
  github_api "repos/${KEYSTONE_RELEASE_OWNER}/${KEYSTONE_RELEASE_REPO}/commits/${tag_name}" | jq -r '.sha'
}

load_state() {
  local repo_root=""
  local input_name=""
  local input_type=""
  local current_rev=""
  local current_tag=""
  local latest_release_json=""
  local latest_tag=""
  local latest_name=""
  local latest_url=""
  local latest_published=""
  local latest_body=""
  local latest_rev=""
  local host_key=""
  local status_kind=""
  local status_summary=""
  local update_allowed="false"
  local update_reason=""
  local dirty="false"

  if ! repo_root=$(keystone-desktop-config config-repo-root 2>/dev/null); then
    jq -n --arg error "Unable to locate the active system flake." '{ ok: false, error: $error }'
    return 0
  fi

  if [[ ! -f "${repo_root}/flake.lock" ]]; then
    jq -n --arg repo_root "$repo_root" --arg error "The active system flake has no flake.lock." '{ ok: false, repo_root: $repo_root, error: $error }'
    return 0
  fi

  if ! input_name=$(discover_keystone_input_name "$repo_root" 2>/dev/null); then
    jq -n --arg repo_root "$repo_root" --arg error "Unable to find a Keystone GitHub input in the active system flake." '{ ok: false, repo_root: $repo_root, error: $error }'
    return 0
  fi

  input_type=$(current_locked_type "$repo_root" "$input_name" || true)
  if [[ "$input_type" != "github" ]]; then
    jq -n --arg repo_root "$repo_root" --arg input_name "$input_name" --arg error "The Keystone input is not locked to a GitHub source." '{ ok: false, repo_root: $repo_root, input_name: $input_name, error: $error }'
    return 0
  fi

  current_rev=$(current_locked_rev "$repo_root" "$input_name" || true)
  if [[ -z "$current_rev" ]]; then
    jq -n --arg repo_root "$repo_root" --arg input_name "$input_name" --arg error "Unable to read the locked Keystone revision from flake.lock." '{ ok: false, repo_root: $repo_root, input_name: $input_name, error: $error }'
    return 0
  fi

  current_tag=$(current_release_tag_for_rev "$current_rev")
  if ! repo_is_clean "$repo_root"; then
    dirty="true"
  fi

  if ! latest_release_json=$(fetch_latest_release_json 2>/dev/null); then
    jq -n \
      --arg repo_root "$repo_root" \
      --arg input_name "$input_name" \
      --arg current_rev "$current_rev" \
      --arg current_tag "$current_tag" \
      --arg dirty "$dirty" \
      --arg error "Unable to fetch the latest Keystone release from GitHub." \
      '{
        ok: false,
        repo_root: $repo_root,
        input_name: $input_name,
        current_rev: $current_rev,
        current_tag: $current_tag,
        dirty: ($dirty == "true"),
        error: $error
      }'
    return 0
  fi

  latest_tag=$(printf '%s\n' "$latest_release_json" | jq -r '.tag_name // empty')
  latest_name=$(printf '%s\n' "$latest_release_json" | jq -r '.name // .tag_name // empty')
  latest_url=$(printf '%s\n' "$latest_release_json" | jq -r '.html_url // empty')
  latest_published=$(printf '%s\n' "$latest_release_json" | jq -r '.published_at // empty')
  latest_body=$(printf '%s\n' "$latest_release_json" | jq -r '.body // "No release notes available."')

  if [[ -z "$latest_tag" ]]; then
    jq -n \
      --arg repo_root "$repo_root" \
      --arg input_name "$input_name" \
      --arg current_rev "$current_rev" \
      --arg current_tag "$current_tag" \
      --arg error "GitHub did not return a latest release tag for Keystone." \
      '{ ok: false, repo_root: $repo_root, input_name: $input_name, current_rev: $current_rev, current_tag: $current_tag, error: $error }'
    return 0
  fi

  if ! latest_rev=$(fetch_release_commit_rev "$latest_tag" 2>/dev/null); then
    jq -n \
      --arg repo_root "$repo_root" \
      --arg input_name "$input_name" \
      --arg current_rev "$current_rev" \
      --arg current_tag "$current_tag" \
      --arg latest_tag "$latest_tag" \
      --arg latest_name "$latest_name" \
      --arg latest_url "$latest_url" \
      --arg latest_published "$latest_published" \
      --arg latest_body "$latest_body" \
      --arg error "Unable to resolve the commit for the latest Keystone release tag." \
      '{
        ok: false,
        repo_root: $repo_root,
        input_name: $input_name,
        current_rev: $current_rev,
        current_tag: $current_tag,
        latest_tag: $latest_tag,
        latest_name: $latest_name,
        latest_url: $latest_url,
        latest_published: $latest_published,
        latest_body: $latest_body,
        error: $error
      }'
    return 0
  fi

  host_key=$(current_host_key "$repo_root" || true)

  if [[ "$current_rev" == "$latest_rev" ]]; then
    status_kind="up-to-date"
    status_summary="Locked release matches the latest published Keystone release."
  elif [[ -n "$current_tag" ]]; then
    status_kind="behind"
    status_summary="A newer Keystone release is available on GitHub."
  elif rev_exists_locally "$current_rev" && rev_exists_locally "$latest_rev" && rev_is_ancestor_of "$latest_rev" "$current_rev"; then
    status_kind="ahead"
    status_summary="The locked revision is newer than the latest published Keystone release."
  else
    status_kind="behind"
    status_summary="The locked revision does not match the latest published Keystone release."
  fi

  if [[ "$status_kind" == "behind" ]]; then
    if [[ "$dirty" == "true" ]]; then
      update_reason="The active system flake has uncommitted changes."
    elif [[ -z "$host_key" ]]; then
      update_reason="Unable to resolve the current host key from hosts.nix."
    else
      update_allowed="true"
      update_reason=""
    fi
  elif [[ "$status_kind" == "up-to-date" ]]; then
    update_reason="The current host already uses the latest Keystone release."
  else
    update_reason="The current lock is newer than the latest published release, so Walker will not downgrade it automatically."
  fi

  jq -n \
    --arg repo_root "$repo_root" \
    --arg input_name "$input_name" \
    --arg current_rev "$current_rev" \
    --arg current_tag "$current_tag" \
    --arg latest_tag "$latest_tag" \
    --arg latest_name "$latest_name" \
    --arg latest_url "$latest_url" \
    --arg latest_published "$latest_published" \
    --arg latest_body "$latest_body" \
    --arg latest_rev "$latest_rev" \
    --arg host_key "$host_key" \
    --arg status_kind "$status_kind" \
    --arg status_summary "$status_summary" \
    --arg update_reason "$update_reason" \
    --arg dirty "$dirty" \
    --arg update_allowed "$update_allowed" \
    '{
      ok: true,
      repo_root: $repo_root,
      input_name: $input_name,
      current_rev: $current_rev,
      current_tag: $current_tag,
      latest_tag: $latest_tag,
      latest_name: $latest_name,
      latest_url: $latest_url,
      latest_published: $latest_published,
      latest_body: $latest_body,
      latest_rev: $latest_rev,
      host_key: $host_key,
      status_kind: $status_kind,
      status_summary: $status_summary,
      update_reason: $update_reason,
      dirty: ($dirty == "true"),
      update_allowed: ($update_allowed == "true")
    }'
}

preview_summary() {
  local state_json=""

  state_json=$(load_state)
  printf '%s\n' "$state_json" | jq -r '
    if .ok then
      [
        "Keystone OS update status",
        "",
        "Consumer flake: " + .repo_root,
        "Input: " + .input_name,
        "Current: " + (if .current_tag != "" then .current_tag else (.current_rev[0:7]) end) + " (" + .current_rev[0:7] + ")",
        "Latest: " + .latest_tag + " (" + .latest_rev[0:7] + ")",
        "Status: " + .status_summary,
        (
          if .update_allowed then
            "Update command: ks update"
          else
            "Update: " + .update_reason
          end
        )
      ] | join("\n")
    else
      [
        "Keystone OS update unavailable",
        "",
        (.error // "Unknown error")
      ] | join("\n")
    end
  '
}

preview_release_notes() {
  local state_json=""

  state_json=$(load_state)
  printf '%s\n' "$state_json" | jq -r '
    if .latest_tag then
      [
        (.latest_name // .latest_tag),
        "Tag: " + .latest_tag,
        (
          if (.latest_published // "") != "" then
            "Published: " + .latest_published
          else
            "Published: unknown"
          end
        ),
        "",
        (.latest_body // "No release notes available."),
        "",
        (.latest_url // "")
      ] | join("\n")
    else
      [
        "Keystone release notes unavailable",
        "",
        (.error // "Unknown error")
      ] | join("\n")
    end
  '
}

entries_json() {
  local state_json=""

  state_json=$(load_state)
  printf '%s\n' "$state_json" | jq -c '
    if .ok then
      [
        {
          Text: ("Current: " + (if .current_tag != "" then .current_tag else (.current_rev[0:7]) end)),
          Subtext: .status_summary,
          Value: "noop",
          Icon: "dialog-information-symbolic",
          Preview: "keystone-update-menu preview-summary",
          PreviewType: "command"
        },
        {
          Text: ("Latest: " + .latest_tag),
          Subtext: "GitHub release notes and changelog",
          Value: ("open-release-page\t" + .latest_url),
          Icon: "software-update-available-symbolic",
          Preview: "keystone-update-menu preview-release-notes",
          PreviewType: "command"
        },
        (
          if .update_allowed then
            {
              Text: "Update current host",
              Subtext: ("Run ks update to install " + .latest_tag + " on this host"),
              Value: "run-update",
              Icon: "system-software-update-symbolic",
              Preview: "keystone-update-menu preview-summary",
              PreviewType: "command"
            }
          else
            {
              Text: "Update unavailable",
              Subtext: .update_reason,
              Value: ("blocked\tUpdate unavailable\t" + .update_reason),
              Icon: "dialog-warning-symbolic",
              Preview: "keystone-update-menu preview-summary",
              PreviewType: "command"
            }
          end
        )
      ]
    else
      [
        {
          Text: "Keystone OS unavailable",
          Subtext: .error,
          Value: ("blocked\tKeystone OS unavailable\t" + .error),
          Icon: "dialog-warning-symbolic",
          Preview: "keystone-update-menu preview-summary",
          PreviewType: "command"
        }
      ]
    end
  '
}

run_update() {
  local state_json=""
  local command_literal=""

  state_json=$(load_state)
  if [[ "$(printf '%s\n' "$state_json" | jq -r '.ok and .update_allowed')" != "true" ]]; then
    notify "Update unavailable" "$(printf '%s\n' "$state_json" | jq -r '.update_reason // .error // "Unable to start the Keystone update flow."')"
    return 0
  fi

  command_literal=$(terminal_command_literal ks approve --reason "Run the Keystone update workflow for this host." -- ks update)
  launch_terminal_command "keystone-os-update" "$command_literal"
  notify "Keystone update started" "Running ks update on this host."
}

dispatch() {
  local payload="${1:-}"
  local action="" arg1="" arg2=""

  IFS=$'\t' read -r action arg1 arg2 <<<"$payload"

  case "$action" in
    noop | "")
      return 0
      ;;
    blocked)
      notify "$arg1" "$arg2"
      ;;
    open-release-page)
      detach xdg-open "$arg1"
      ;;
    run-update)
      run_update
      ;;
    *)
      printf "Unknown update menu action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

case "${1:-}" in
  entries-json)
    entries_json
    ;;
  preview-summary)
    preview_summary
    ;;
  preview-release-notes)
    preview_release_notes
    ;;
  dispatch)
    shift
    dispatch "${1:-}"
    ;;
  *)
    echo "Usage: keystone-update-menu {entries-json|preview-summary|preview-release-notes|dispatch} ..." >&2
    exit 1
    ;;
esac
