#!/usr/bin/env bash

set -euo pipefail

doctor_report_note() {
  local label="$1"
  local value="$2"
  printf -- '- **%s**: %s\n' "$label" "$value"
}

report_display_path() {
  local path="$1"
  if [[ "$path" == "$HOME/"* ]]; then
    printf '%s/%s\n' "\$HOME" "${path#"$HOME"/}"
  else
    printf '%s\n' "$path"
  fi
}

get_repos_registry() {
  local repo_root="$1"
  if [[ -f "$repo_root/repos.nix" ]]; then
    nix eval -f "$repo_root/repos.nix" --json 2>/dev/null
  else
    echo "{}"
  fi
}

local_override_args() {
  local repo_root="$1"
  local args=()
  local registry
  registry=$(get_repos_registry "$repo_root")

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local key input path name
    key=$(echo "$line" | cut -d'|' -f1)
    input=$(echo "$line" | cut -d'|' -f2)
    name="${key##*/}"
    path=""
    if [[ -d "$HOME/.keystone/repos/$key" ]]; then
      path="$HOME/.keystone/repos/$key"
    elif [[ -d "$repo_root/.repos/$name" ]]; then
      path="$repo_root/.repos/$name"
    elif [[ -d "$repo_root/.submodules/$name" ]]; then
      path="$repo_root/.submodules/$name"
    elif [[ -d "$repo_root/$name" ]]; then
      path="$repo_root/$name"
    fi

    if [[ -n "$path" && "$input" != "null" ]]; then
      args+=(--override-input "$input" "path:$path")
    fi
  done <<< "$(echo "$registry" | jq -r 'to_entries[] | "\(.key)|\(.value.flakeInput)"')"

  echo "${args[@]}"
}

resolve_current_hm_user() {
  local repo_root="$1"
  local host="$2"
  if [[ -z "$host" ]]; then
    echo ""
    return 0
  fi

  local preferred_user="${SUDO_USER:-${USER:-$(id -un)}}"
  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"
  local users_json
  users_json=$(timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${host}.config.home-manager.users" \
    --apply 'builtins.attrNames' --json \
    "${override_args[@]}" 2>/dev/null || echo "[]")

  if echo "$users_json" | jq -e --arg user "$preferred_user" '.[] | select(. == $user)' >/dev/null 2>&1; then
    echo "$preferred_user"
    return 0
  fi

  local fallback_user
  fallback_user=$(echo "$users_json" | jq -r 'map(select(startswith("agent-") | not)) | .[0] // ""')
  if [[ -n "$fallback_user" ]]; then
    echo "$fallback_user"
    return 0
  fi

  echo "$users_json" | jq -r '.[0] // ""'
}

eval_hm_user_attr_json() {
  local repo_root="$1"
  local host="$2"
  local user="$3"
  local attr_suffix="$4"
  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${host}.config.home-manager.users.\"${user}\".${attr_suffix}" \
    --json \
    "${override_args[@]}" 2>/dev/null
}

resolve_ollama_user() {
  local repo_root="$1"
  local host="$2"
  local user="${3:-}"

  if [[ -n "$user" ]]; then
    echo "$user"
    return 0
  fi

  local resolved_user
  resolved_user=$(resolve_current_hm_user "$repo_root" "$host")
  echo "$resolved_user"
}

resolve_ollama_enabled() {
  local repo_root="$1"
  local host="$2"
  local user
  user=$(resolve_ollama_user "$repo_root" "$host" "${3:-}")
  eval_hm_user_attr_json "$repo_root" "$host" "$user" "keystone.terminal.ai.ollama.enable" \
    | jq -r 'if . == true then "true" else "false" end' 2>/dev/null || echo "false"
}

resolve_ollama_host() {
  local repo_root="$1"
  local host="$2"
  local user
  user=$(resolve_ollama_user "$repo_root" "$host" "${3:-}")
  eval_hm_user_attr_json "$repo_root" "$host" "$user" "keystone.terminal.ai.ollama.host" \
    | jq -r '. // ""' 2>/dev/null
}

resolve_ollama_default_model() {
  local repo_root="$1"
  local host="$2"
  local user
  user=$(resolve_ollama_user "$repo_root" "$host" "${3:-}")
  eval_hm_user_attr_json "$repo_root" "$host" "$user" "keystone.terminal.ai.ollama.defaultModel" \
    | jq -r '. // ""' 2>/dev/null
}

list_ollama_models() {
  local ollama_host="$1"

  if ! command -v ollama >/dev/null 2>&1; then
    echo "_ollama CLI not installed_"
    return 0
  fi

  local models
  models=$(OLLAMA_HOST="$ollama_host" ollama list 2>/dev/null | awk 'NR > 1 { print $1 }' || true)
  if [[ -z "$models" ]]; then
    echo "_No local models found_"
    return 0
  fi

  while IFS= read -r model; do
    [[ -n "$model" ]] && echo "- $model"
  done <<< "$models"
}

known_agents_list() {
  if ! command -v agentctl >/dev/null 2>&1; then
    return 1
  fi

  local known_agents
  known_agents=$(agentctl 2>&1 | sed -n 's/^Known agents: //p' | head -n1)
  [[ -n "$known_agents" ]] || return 1

  printf '%s\n' "$known_agents" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | sed '/^$/d'
}

safe_systemctl_state() {
  local agent="$1"
  local unit="$2"
  local state

  state=$(agentctl "$agent" is-active "$unit" 2>/dev/null | head -n1 | tr -d '\r')
  if [[ -n "$state" ]]; then
    printf '%s\n' "$state"
  else
    printf '%s\n' "unknown"
  fi
}

count_status_matches() {
  local yaml="$1"
  local status="$2"
  local count

  count=$(printf '%s\n' "$yaml" | grep -c "status: ${status}" 2>/dev/null || true)
  printf '%s\n' "${count:-0}"
}

failed_units_list() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi

  systemctl --failed --plain --no-legend --no-pager 2>/dev/null \
    | sed -E 's/^[[:space:]]*●?[[:space:]]+//; s/[[:space:]].*$//' \
    | sed '/^$/d' || true
}

repo_status_summary() {
  local path="$1"

  if [[ ! -d "$path" ]]; then
    printf 'missing (%s)' "$path"
    return 0
  fi

  if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'not-a-git-repo'
    return 0
  fi

  local branch dirty untracked upstream ahead behind remote_ref_known
  branch=$(git -C "$path" branch --show-current 2>/dev/null || true)
  [[ -n "$branch" ]] || branch="detached"

  dirty="clean"
  if ! git -C "$path" diff --quiet 2>/dev/null || ! git -C "$path" diff --cached --quiet 2>/dev/null; then
    dirty="dirty"
  fi

  untracked="no"
  if [[ -n "$(git -C "$path" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
    untracked="yes"
  fi

  upstream=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
  ahead="n/a"
  behind="n/a"
  remote_ref_known="no"
  if [[ -n "$upstream" ]] && git -C "$path" rev-parse "$upstream" >/dev/null 2>&1; then
    remote_ref_known="yes"
    read -r behind ahead < <(git -C "$path" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null || printf '? ?\n')
  fi

  printf 'branch=%s, dirty=%s, untracked=%s, upstream=%s, remoteRefKnown=%s, ahead=%s, behind=%s' \
    "$branch" "$dirty" "$untracked" "${upstream:-none}" "$remote_ref_known" "$ahead" "$behind"
}

gather_managed_repo_health() {
  local base_dir="$1"
  local title="$2"

  echo "### ${title}"
  if [[ ! -d "$base_dir" ]]; then
    echo "_Missing: ${base_dir}_"
    return 0
  fi

  local found=0
  while IFS= read -r repo_path; do
    found=1
    local repo_label="${repo_path#"$base_dir"/}"
    doctor_report_note "$repo_label" "$(repo_status_summary "$repo_path")"
  done < <(find "$base_dir" -mindepth 3 -maxdepth 3 -type d -name .git -prune -printf '%h\n' | sort)

  if [[ "$found" -eq 0 ]]; then
    echo "_No managed repos found under ${base_dir}_"
  fi
}

gather_deepwork_job_health() {
  echo "### DeepWork job folders"

  if [[ -z "${DEEPWORK_ADDITIONAL_JOBS_FOLDERS:-}" ]]; then
    echo "_DEEPWORK_ADDITIONAL_JOBS_FOLDERS is not set_"
    return 0
  fi

  local jobs_dir
  IFS=':' read -r -a job_dirs <<< "${DEEPWORK_ADDITIONAL_JOBS_FOLDERS}"
  for jobs_dir in "${job_dirs[@]}"; do
    [[ -z "$jobs_dir" ]] && continue
    if [[ -d "$jobs_dir" ]]; then
      local job_count
      job_count=$(find "$jobs_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
      doctor_report_note "$(report_display_path "$jobs_dir")" "present, jobs=${job_count}"
    else
      doctor_report_note "$(report_display_path "$jobs_dir")" "missing"
    fi
  done
}

command_version_or_unknown() {
  local cmd="$1"
  shift || true
  if [[ -x "$cmd" ]]; then
    "$cmd" "$@" --version 2>/dev/null | head -n1 || echo "unknown"
  else
    echo "unknown"
  fi
}

gather_deepwork_mcp_health() {
  local repo_root="$1"
  local claude_json="$HOME/.claude.json"
  local installed_plugins_json="$HOME/.claude/installed_plugins.json"
  local plugin_cache_root="$HOME/.claude/plugins/cache"
  local uv_tool_dir="$HOME/.local/share/uv/tools/deepwork"
  local providers=0
  local provider_labels=()

  echo "### DeepWork MCP"

  if [[ -f "$claude_json" ]]; then
    local claude_server_json claude_command claude_args claude_version
    claude_server_json=$(jq -c '.mcpServers.deepwork // empty' "$claude_json" 2>/dev/null || true)
    if [[ -n "$claude_server_json" ]]; then
      claude_command=$(printf '%s\n' "$claude_server_json" | jq -r '.command // ""')
      claude_args=$(printf '%s\n' "$claude_server_json" | jq -r '(.args // []) | join(" ")')
      claude_version="unknown"
      if [[ "$claude_command" == */deepwork ]]; then
        claude_version=$(command_version_or_unknown "$claude_command")
      fi
      providers=$((providers + 1))
      provider_labels+=("claude-json")
      doctor_report_note "$(report_display_path "$claude_json")" "present, command=${claude_command:-none}, args=${claude_args:-none}, version=${claude_version}"
    else
      doctor_report_note "$(report_display_path "$claude_json")" "no deepwork entry"
    fi
  else
    doctor_report_note "$(report_display_path "$claude_json")" "missing"
  fi

  local candidate_mcp
  for candidate_mcp in "$repo_root/.mcp.json" "$repo_root/plugins/claude/.mcp.json"; do
    if [[ -f "$candidate_mcp" ]]; then
      local project_server_json project_command project_args
      project_server_json=$(jq -c '.mcpServers.deepwork // empty' "$candidate_mcp" 2>/dev/null || true)
      if [[ -n "$project_server_json" ]]; then
        project_command=$(printf '%s\n' "$project_server_json" | jq -r '.command // ""')
        project_args=$(printf '%s\n' "$project_server_json" | jq -r '(.args // []) | join(" ")')
        providers=$((providers + 1))
        provider_labels+=("project-mcp")
        doctor_report_note "$(report_display_path "$candidate_mcp")" "present, command=${project_command:-none}, args=${project_args:-none}"
      else
        doctor_report_note "$(report_display_path "$candidate_mcp")" "present, no deepwork entry"
      fi
    fi
  done

  if [[ -d "$uv_tool_dir" ]]; then
    local uv_version="unknown"
    if [[ -x "$uv_tool_dir/bin/deepwork" ]]; then
      uv_version=$(command_version_or_unknown "$uv_tool_dir/bin/deepwork")
    fi
    doctor_report_note "$(report_display_path "$uv_tool_dir")" "present, version=${uv_version}"
  else
    doctor_report_note "$(report_display_path "$uv_tool_dir")" "absent"
  fi

  if [[ -d "$plugin_cache_root" ]]; then
    local cache_hits
    cache_hits=$(find "$plugin_cache_root" -maxdepth 3 -type d \( -name 'deepwork-plugins' -o -name '*deepwork*' \) 2>/dev/null | sort || true)
    if [[ -n "$cache_hits" ]]; then
      local display_hits=""
      while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        display_hits+="${display_hits:+ }$(report_display_path "$hit")"
      done <<< "$cache_hits"
      doctor_report_note "$(report_display_path "$plugin_cache_root")" "$display_hits"
    else
      doctor_report_note "$(report_display_path "$plugin_cache_root")" "no deepwork cache entries"
    fi
  else
    doctor_report_note "$(report_display_path "$plugin_cache_root")" "missing"
  fi

  if [[ -f "$installed_plugins_json" ]]; then
    local installed_deepwork_plugins
    installed_deepwork_plugins=$(jq -r '
      if type == "array" then
        .[]
      elif type == "object" then
        (.installed // .plugins // [])
        | if type == "array" then .[] else empty end
      else
        empty
      end
      | if type == "string" then . else (.id // .name // .slug // empty) end
      | select(test("deepwork"; "i"))
    ' "$installed_plugins_json" 2>/dev/null | sort -u || true)
    if [[ -n "$installed_deepwork_plugins" ]]; then
      doctor_report_note "$(report_display_path "$installed_plugins_json")" "$(printf '%s' "$installed_deepwork_plugins" | tr '\n' ' ' | sed 's/  */ /g; s/ $//')"
    else
      doctor_report_note "$(report_display_path "$installed_plugins_json")" "no deepwork plugins"
    fi
  else
    doctor_report_note "$(report_display_path "$installed_plugins_json")" "missing"
  fi

  if (( providers > 1 )); then
    doctor_report_note "provider status" "conflict, providers=${providers}, active=${provider_labels[*]}"
  elif (( providers == 1 )); then
    doctor_report_note "provider status" "single provider, active=${provider_labels[*]}"
  else
    doctor_report_note "provider status" "no configured deepwork provider found"
  fi
}

gather_notes_hygiene() {
  local notes_dir="$1"

  echo "### Notes repo"
  doctor_report_note "path" "$(report_display_path "$notes_dir")"
  doctor_report_note "git" "$(repo_status_summary "$notes_dir")"

  local legacy_artifacts=()
  local artifact
  for artifact in ".agents" ".deepwork" ".mcp.json" ".mcp" "mcp"; do
    if [[ -e "$notes_dir/$artifact" ]]; then
      legacy_artifacts+=("$artifact")
    fi
  done

  if [[ ${#legacy_artifacts[@]} -eq 0 ]]; then
    doctor_report_note "legacy artifacts" "none"
  else
    doctor_report_note "legacy artifacts" "${legacy_artifacts[*]}"
  fi
}

gather_worktree_health() {
  local worktree_dir="$1"

  echo "### Worktrees"
  if [[ ! -d "$worktree_dir" ]]; then
    echo "_Missing: ${worktree_dir}_"
    return 0
  fi

  local found=0
  while IFS= read -r wt_path; do
    found=1
    local branch upstream ahead behind merged_status default_ref
    branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || true)
    [[ -n "$branch" ]] || branch="detached"

    upstream=$(git -C "$wt_path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
    ahead="n/a"
    behind="n/a"
    if [[ -n "$upstream" ]] && git -C "$wt_path" rev-parse "$upstream" >/dev/null 2>&1; then
      read -r behind ahead < <(git -C "$wt_path" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null || printf '? ?\n')
    fi

    merged_status="active"
    default_ref=$(git -C "$wt_path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
    [[ -n "$default_ref" ]] || default_ref="refs/remotes/origin/main"
    if [[ "$branch" != "detached" ]] && git -C "$wt_path" show-ref --verify --quiet "$default_ref"; then
      if git -C "$wt_path" merge-base --is-ancestor "refs/heads/$branch" "$default_ref" 2>/dev/null; then
        merged_status="merged-into-${default_ref#refs/remotes/origin/}"
      fi
    fi

    doctor_report_note "${wt_path#"$worktree_dir"/}" \
      "branch=${branch}, upstream=${upstream:-none}, ahead=${ahead}, behind=${behind}, status=${merged_status}"
  done < <(find "$worktree_dir" -mindepth 3 -maxdepth 3 -type d | while read -r candidate; do
    git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1 && printf '%s\n' "$candidate"
  done | sort)

  if [[ "$found" -eq 0 ]]; then
    echo "_No worktrees found under ${worktree_dir}_"
  fi
}

gather_forgejo_auth() {
  echo "### Forgejo auth"

  if ! command -v tea >/dev/null 2>&1; then
    echo "_tea is not installed_"
    return 0
  fi

  if timeout 15 tea api --login forgejo /user >/dev/null 2>&1; then
    doctor_report_note "tea" "authenticated"
  else
    doctor_report_note "tea" "not authenticated or missing token"
  fi

  if command -v fj >/dev/null 2>&1; then
    if timeout 15 fj whoami >/dev/null 2>&1; then
      doctor_report_note "fj" "authenticated"
    else
      doctor_report_note "fj" "not authenticated"
    fi
  fi
}

gather_fleet_health() {
  local hosts_nix="$1"
  local local_gen="$2"
  local current_hostname
  current_hostname=$(hostname)

  local all_hosts
  all_hosts=$(nix eval -f "$hosts_nix" --json --apply 'builtins.attrNames' 2>/dev/null) || return 0
  local host_list
  host_list=$(echo "$all_hosts" | jq -r '.[]')

  echo "### Fleet status"
  echo "| Host | Reachable | NixOS Generation | Status |"
  echo "|------|-----------|------------------|--------|"

  for host in $host_list; do
    local host_json host_name ssh_target fallback_ip
    host_json=$(nix eval -f "$hosts_nix" "$host" --json 2>/dev/null) || continue
    host_name=$(echo "$host_json" | jq -r '.hostname // ""')
    ssh_target=$(echo "$host_json" | jq -r '.sshTarget // ""')
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // ""')

    if [[ "$host_name" == "$current_hostname" ]]; then
      echo "| $host | local | $local_gen | ← current |"
      continue
    fi

    if [[ -z "$ssh_target" ]]; then
      echo "| $host | — | — | no sshTarget |"
      continue
    fi

    local resolved="$ssh_target"
    local reachable="no"
    local remote_gen="—"
    local status="unreachable"

    if ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${ssh_target}" true 2>/dev/null; then
      reachable="yes"
    elif [[ -n "$fallback_ip" ]] && ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${fallback_ip}" true 2>/dev/null; then
      reachable="yes (LAN)"
      resolved="$fallback_ip"
    fi

    if [[ "$reachable" != "no" ]]; then
      remote_gen=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${resolved}" nixos-version 2>/dev/null || echo "unknown")
      if [[ "$remote_gen" == "$local_gen" ]]; then
        status="ok"
      elif [[ "$remote_gen" == "unknown" ]]; then
        status="unknown"
      else
        status="drift"
      fi
    fi

    echo "| $host | $reachable | $remote_gen | $status |"
  done
}

gather_agent_health() {
  if ! command -v agentctl >/dev/null 2>&1; then
    echo "### Agent status"
    echo "_agentctl not available on this host_"
    return 0
  fi

  local agents
  agents=$(known_agents_list 2>/dev/null || true)
  if [[ -z "$agents" ]]; then
    echo "### Agent status"
    echo "_No agents configured_"
    return 0
  fi

  echo "### Agent status"
  echo "| Agent | Task Loop | Notes Sync | SSH Agent | Status |"
  echo "|-------|-----------|------------|-----------|--------|"

  local agent
  while IFS= read -r agent; do
    [[ -n "$agent" ]] || continue
    local task_loop notes_sync ssh_agent overall
    task_loop=$(safe_systemctl_state "$agent" "agent-${agent}-task-loop.timer")
    notes_sync=$(safe_systemctl_state "$agent" "agent-${agent}-notes-sync.timer")
    ssh_agent=$(safe_systemctl_state "$agent" "agent-${agent}-ssh-agent.service")

    if [[ "$task_loop" == "active" && "$notes_sync" == "active" && "$ssh_agent" == "active" ]]; then
      overall="ok"
    elif [[ "$task_loop" == "unknown" && "$notes_sync" == "unknown" ]]; then
      overall="unreachable"
    else
      overall="degraded"
    fi

    echo "| $agent | $task_loop | $notes_sync | $ssh_agent | $overall |"
  done <<< "$agents"
}

gather_agent_tasks() {
  if ! command -v agentctl >/dev/null 2>&1; then
    return 0
  fi

  local agents
  agents=$(known_agents_list 2>/dev/null || true)
  [[ -z "$agents" ]] && return 0

  echo "### Agent tasks"
  echo "| Agent | Pending | In Progress | Blocked | Completed |"
  echo "|-------|---------|-------------|---------|-----------|"

  local agent
  while IFS= read -r agent; do
    [[ -n "$agent" ]] || continue
    local tasks_yaml pending in_progress blocked completed
    tasks_yaml=$(agentctl "$agent" exec cat "/home/agent-${agent}/TASKS.yaml" 2>/dev/null || true)

    if [[ -z "$tasks_yaml" ]]; then
      echo "| $agent | — | — | — | — |"
      continue
    fi

    pending=$(count_status_matches "$tasks_yaml" "pending")
    in_progress=$(count_status_matches "$tasks_yaml" "in_progress")
    blocked=$(count_status_matches "$tasks_yaml" "blocked")
    completed=$(count_status_matches "$tasks_yaml" "completed")
    echo "| $agent | $pending | $in_progress | $blocked | $completed |"
  done <<< "$agents"
}

gather_agent_doctor_reports() {
  if ! command -v agentctl >/dev/null 2>&1; then
    return 0
  fi

  local agents
  agents=$(known_agents_list 2>/dev/null || true)
  [[ -z "$agents" ]] && return 0

  echo "## Agent preflight reports"
  echo ""
  local agent
  while IFS= read -r agent; do
    [[ -n "$agent" ]] || continue
    echo "### ${agent}"
    agentctl "$agent" doctor-report 2>/dev/null || echo "_failed to collect report_"
    echo ""
  done <<< "$agents"
}

gather_ollama_diagnostics() {
  local repo_root="$1"
  local current_host="$2"

  echo "### Ollama diagnostics"

  if [[ -z "$current_host" ]]; then
    echo "_Current host is not defined in hosts.nix; skipping config evaluation_"
    return 0
  fi

  local user
  user=$(resolve_current_hm_user "$repo_root" "$current_host")
  if [[ -z "$user" ]]; then
    echo "_No home-manager user found for current host_"
    return 0
  fi

  local enabled host default_model
  enabled=$(resolve_ollama_enabled "$repo_root" "$current_host" "$user")
  host=$(resolve_ollama_host "$repo_root" "$current_host" "$user")
  default_model=$(resolve_ollama_default_model "$repo_root" "$current_host" "$user")

  echo "- Home-manager user: $user"
  echo "- Ollama enabled: $enabled"
  echo "- Ollama host: ${host:-_not configured_}"
  echo "- Default model: ${default_model:-_not configured_}"
  echo "- ollama CLI: $(command -v ollama >/dev/null 2>&1 && echo "installed" || echo "missing")"
  echo "- claude CLI: $(command -v claude >/dev/null 2>&1 && echo "installed" || echo "missing")"

  if command -v ollama >/dev/null 2>&1 && [[ -n "$host" ]]; then
    if OLLAMA_HOST="$host" ollama list >/dev/null 2>&1; then
      echo "- Ollama API: reachable"
    else
      echo "- Ollama API: unreachable"
    fi
  else
    echo "- Ollama API: unchecked"
  fi

  echo "- Available models:"
  list_ollama_models "$host"

  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"
  local agent_users_json
  agent_users_json=$(timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${current_host}.config.home-manager.users" \
    --apply 'builtins.attrNames' --json \
    "${override_args[@]}" 2>/dev/null || echo "[]")
  local agent_users
  agent_users=$(echo "$agent_users_json" | jq -r '.[] | select(startswith("agent-"))')

  if [[ -z "$agent_users" ]]; then
    echo "- Agent local config: _no agent home-manager users found_"
    return 0
  fi

  echo "- Agent local config:"
  while IFS= read -r agent_user; do
    [[ -z "$agent_user" ]] && continue
    local agent_enabled agent_host agent_model
    agent_enabled=$(resolve_ollama_enabled "$repo_root" "$current_host" "$agent_user")
    agent_host=$(resolve_ollama_host "$repo_root" "$current_host" "$agent_user")
    agent_model=$(resolve_ollama_default_model "$repo_root" "$current_host" "$agent_user")
    echo "  - ${agent_user}: enabled=${agent_enabled}, host=${agent_host:-none}, defaultModel=${agent_model:-none}"
  done <<< "$agent_users"
}

generate_doctor_report() {
  local repo_root="$1"
  local hosts_nix="$2"
  local current_host="$3"
  local scope="$4"
  local agent_name="$5"
  local notes_dir="${NOTES_DIR:-$HOME/notes}"
  local code_dir="${CODE_DIR:-$HOME/repos}"
  local worktree_dir="${WORKTREE_DIR:-$HOME/.worktrees}"

  echo "## Scripted preflight report"
  echo ""
  doctor_report_note "scope" "$scope"
  if [[ -n "$agent_name" ]]; then
    doctor_report_note "agent" "$agent_name"
  fi
  doctor_report_note "home" "$HOME"
  doctor_report_note "notesDir" "$(report_display_path "$notes_dir")"
  doctor_report_note "codeDir" "$(report_display_path "$code_dir")"
  doctor_report_note "worktreeDir" "$(report_display_path "$worktree_dir")"
  echo ""

  local gen=""
  if command -v nixos-version >/dev/null 2>&1; then
    gen=$(nixos-version 2>/dev/null || true)
  fi

  echo "## Local system"
  echo ""
  [[ -n "$gen" ]] && doctor_report_note "nixosGeneration" "$gen"

  echo "### Failed systemd units"
  local failed=""
  failed=$(failed_units_list)
  if [[ -z "$failed" ]]; then
    echo "_None_"
  else
    while IFS= read -r unit; do
      [[ -n "$unit" ]] && echo "- $unit"
    done <<< "$failed"
  fi
  echo ""

  echo "### Disk usage"
  echo '```'
  df -h 2>/dev/null | head -20 || echo "_unavailable_"
  echo '```'
  echo ""

  echo "### flake.lock age"
  if [[ -f "$repo_root/flake.lock" ]]; then
    local lock_age
    lock_age=$(git -C "$repo_root" log -1 --format="%ar" -- flake.lock 2>/dev/null || true)
    echo "${lock_age:-unknown}"
  else
    echo "_flake.lock not found_"
  fi
  echo ""

  gather_forgejo_auth
  echo ""
  gather_managed_repo_health "$HOME/.keystone/repos" "Managed repos"
  echo ""
  gather_managed_repo_health "$code_dir" "Project repos"
  echo ""
  gather_deepwork_job_health
  echo ""
  gather_deepwork_mcp_health "$repo_root"
  echo ""
  gather_notes_hygiene "$notes_dir"
  echo ""
  gather_worktree_health "$worktree_dir"
  echo ""
  gather_ollama_diagnostics "$repo_root" "$current_host"
  echo ""

  if [[ "$scope" == "human" && -n "$hosts_nix" && -f "$hosts_nix" ]]; then
    gather_fleet_health "$hosts_nix" "$gen"
    echo ""
    gather_agent_health
    echo ""
    gather_agent_tasks
    echo ""
    gather_agent_doctor_reports
  fi
}

main() {
  local repo_root=""
  local hosts_nix=""
  local current_host=""
  local scope="human"
  local agent_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-root) repo_root="${2:-}"; shift 2 ;;
      --hosts-nix) hosts_nix="${2:-}"; shift 2 ;;
      --current-host) current_host="${2:-}"; shift 2 ;;
      --scope) scope="${2:-}"; shift 2 ;;
      --agent-name) agent_name="${2:-}"; shift 2 ;;
      -h|--help)
        echo "Usage: doctor-report.sh --repo-root PATH --hosts-nix PATH --current-host HOST [--scope human|agent] [--agent-name NAME]" >&2
        return 0
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        return 1
        ;;
    esac
  done

  [[ -n "$repo_root" ]] || { echo "Error: --repo-root is required" >&2; return 1; }
  [[ -n "$hosts_nix" ]] || hosts_nix="$repo_root/hosts.nix"
  generate_doctor_report "$repo_root" "$hosts_nix" "$current_host" "$scope" "$agent_name"
}

main "$@"
