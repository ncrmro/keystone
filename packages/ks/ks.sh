#!/usr/bin/env bash
# ks — Keystone infrastructure CLI
#
# Implements REQ-018: Keystone Home Directory and Repo Management
# See conventions/code.shell-scripts.md
#
# Usage: ks <command> [options]
#
# Commands:
#   build  [--lock] [HOSTS]                            Build home-manager profiles (or full system with --lock)
#   update [--debug] [--dev] [--boot] [--pull] [--lock] [HOSTS]  Deploy (home-manager only with --dev, full system default)
#   grafana dashboards apply|export <uid>              Apply or export keystone dashboard JSON via Grafana API
#   sync-host-keys                                   Populate hostPublicKey in hosts.nix from live hosts
#   agent  [--local [MODEL]] [args...]               Launch AI agent with keystone OS context
#   doctor [--local [MODEL]] [args...]               Launch diagnostic AI agent with system state
#
# Host resolution:
#   1. If HOST is provided, use it directly
#   2. Otherwise, look up the current machine's hostname in hosts.nix
#
# HOSTS:
#   Comma-separated list of host names (e.g. host1,host2).
#   Defaults to current machine hostname.
#   Risky hosts should be placed last (e.g. workstation,ocean).
#
#
# Repo discovery:
#   1. $NIXOS_CONFIG_DIR if set and contains hosts.nix
#   2. Git repo root of current directory if it contains hosts.nix
#   3. ~/.keystone/repos/*/ if it contains hosts.nix
#   4. ~/nixos-config as fallback
#
# The --dev flag overrides keystone and agenix-secrets flake inputs with
# local clone paths for testing uncommitted changes.
#
# Requirements (RFC 2119)
#
# Repo management
#   MUST pull nixos-config, keystone, and agenix-secrets before building (lock mode).
#   MUST update flake.lock (nix flake update) before building, not after.
#   MUST commit and push flake.lock only after a successful build.
#   MUST verify keystone and agenix-secrets are clean and fully pushed before locking.
#
# Build
#   MUST always use local .repos/keystone and .repos/agenix-secrets as --override-input
#     when those directories exist, regardless of --dev flag.
#   MUST build all target hosts before deploying any of them.
#   MUST pass --no-link to nix build to prevent ./result symlinks in the caller's CWD.
#   SHOULD build all targets in a single nix invocation (nix parallelises internally).
#   SHOULD hide warning lines during `ks update` by default; `--debug` MUST show them.
#
# Deployment
#   MUST deploy hosts sequentially (not in parallel) to limit blast radius.
#   MUST obtain sudo credentials before any other work (pull, lock, build) when a local
#     host is targeted, so the user is not interrupted mid-run.
#   SHOULD keep sudo credentials alive for the duration of the run.
#
# --dev mode
#   MUST skip pull, flake-update, commit, and push phases.
#   MAY be used with uncommitted local repo changes.

set -euo pipefail

KS_DEBUG=false
KS_HM_USERS_FILTER=""
KS_HM_ALL_USERS=false
HM_ACTIVATION_RECORDS=()

print_main_help() {
  cat <<'EOF'
Usage: ks <command> [options]

Build, deploy, and inspect Keystone-managed hosts.

Commands:
  help [command]                                    Show general or command-specific help
  build [--lock] [--user USERS] [--all-users] [HOSTS]
                                                    Build home-manager profiles, or full systems with --lock
  update [--debug] [--dev] [--boot] [--pull] [--lock] [--user USERS] [--all-users] [HOSTS]
                                                    Pull, lock, build, push, and deploy
  switch [--boot] [HOSTS]                           Deploy current state without pull, lock, or push
  sync-host-keys                                    Populate hostPublicKey in hosts.nix from live hosts
  grafana dashboards apply
  grafana dashboards export <uid>                   Apply or export Grafana dashboards
  agent [--local [MODEL]] [args...]                 Launch an AI agent with Keystone context
  doctor [--local [MODEL]] [args...]                Launch a diagnostic AI agent with system state

HOSTS:
  Comma-separated host names such as workstation,ocean.
  Defaults to the current host resolved from hosts.nix.

Repo discovery:
  1. $NIXOS_CONFIG_DIR if it contains hosts.nix
  2. The current git repo root if it contains hosts.nix
  3. ~/.keystone/repos/*/ if it contains hosts.nix
  4. ~/nixos-config

Examples:
  ks build
  ks build --lock workstation,ocean
  ks update --dev
  ks help grafana dashboards

Use "ks help <command>" for command-specific help.
EOF
}

print_build_help() {
  cat <<'EOF'
Usage: ks build [--lock] [--user USERS] [--all-users] [HOSTS]

Build Keystone configurations for one or more hosts.

Options:
  --lock               Build full NixOS system closures instead of home-manager profiles
  --user USERS         Limit home-manager builds to a comma-separated user list
  --all-users          Build all home-manager users on each target host
  -h, --help           Show this help

Defaults:
  Without --lock, ks builds home-manager activation packages only.
  Without HOSTS, ks resolves the current host from hosts.nix.

Examples:
  ks build
  ks build workstation,ocean
  ks build --user alice,agent-coder workstation
  ks build --lock ocean
EOF
}

print_update_help() {
  cat <<'EOF'
Usage: ks update [--debug] [--dev] [--boot] [--pull] [--lock] [--user USERS] [--all-users] [HOSTS]

Pull, verify, build, and deploy Keystone hosts.

Options:
  --debug              Show warnings from git and nix commands
  --dev                Build and activate home-manager profiles only
  --boot               Register the new generation for next boot without switching now
  --pull               Pull managed repos only; skip build and deploy
  --lock               Force lock mode explicitly; this is the default unless --dev is set
  --user USERS         Limit home-manager activation to a comma-separated user list
  --all-users          Activate all home-manager users on each target host
  -h, --help           Show this help

Defaults:
  ks update runs in lock mode by default.
  HOSTS defaults to the current host resolved from hosts.nix.

Examples:
  ks update
  ks update --dev workstation
  ks update --boot ocean
  ks update --pull --dev
EOF
}

print_switch_help() {
  cat <<'EOF'
Usage: ks switch [--boot] [HOSTS]

Build and deploy the current local state without pull, lock, or push steps.

Options:
  --boot               Register the new generation for next boot without switching now
  -h, --help           Show this help

Defaults:
  HOSTS defaults to the current host resolved from hosts.nix.

Examples:
  ks switch
  ks switch workstation,ocean
  ks switch --boot ocean
EOF
}

print_sync_host_keys_help() {
  cat <<'EOF'
Usage: ks sync-host-keys

Fetch SSH host public keys from live hosts and write them into hosts.nix.

Options:
  -h, --help           Show this help

Behavior:
  Hosts without sshTarget are skipped.
  When sshTarget is unreachable and fallbackIP exists, ks retries over fallbackIP.

Examples:
  ks sync-host-keys
EOF
}

print_agent_help() {
  cat <<'EOF'
Usage: ks agent [--local [MODEL]] [args...]

Launch an AI coding agent with Keystone conventions and host context.

Options:
  --local [MODEL]      Use the local Ollama-backed model, or the configured default model
  -h, --help           Show this help

Behavior:
  Any remaining args are passed through to the underlying claude invocation.

Examples:
  ks agent
  ks agent --local
  ks agent --local qwen2.5-coder:14b --continue
EOF
}

print_doctor_help() {
  cat <<'EOF'
Usage: ks doctor [--local [MODEL]] [args...]

Launch a diagnostic AI agent with fleet and local system state.

Options:
  --local [MODEL]      Use the local Ollama-backed model, or the configured default model
  -h, --help           Show this help

Behavior:
  Any remaining args are passed through to the underlying claude invocation.

Examples:
  ks doctor
  ks doctor --local
  ks doctor --local mistral --continue
EOF
}

print_grafana_help() {
  cat <<'EOF'
Usage: ks grafana dashboards <apply|export> [uid]

Manage checked-in Keystone Grafana dashboards through the Grafana API.

Subcommands:
  dashboards apply     Apply every dashboard JSON file in the repo
  dashboards export <uid>
                       Export one dashboard by UID into its checked-in JSON file

Options:
  -h, --help           Show this help

Examples:
  ks grafana dashboards apply
  ks grafana dashboards export keystone-host-overview
EOF
}

print_grafana_dashboards_help() {
  cat <<'EOF'
Usage: ks grafana dashboards <apply|export> [uid]

Apply or export Keystone Grafana dashboards.

Subcommands:
  apply                Push all checked-in dashboard JSON files to Grafana
  export <uid>         Pull one dashboard by UID into its checked-in JSON file

Environment:
  GRAFANA_URL          Override the Grafana base URL
  GRAFANA_API_KEY      Override the Grafana API key

Examples:
  ks grafana dashboards apply
  ks grafana dashboards export keystone-system-index
EOF
}

show_help_topic() {
  case "${1:-}" in
    ""|ks)
      print_main_help
      ;;
    build)
      print_build_help
      ;;
    update)
      print_update_help
      ;;
    switch)
      print_switch_help
      ;;
    sync-host-keys)
      print_sync_host_keys_help
      ;;
    agent)
      print_agent_help
      ;;
    doctor)
      print_doctor_help
      ;;
    grafana)
      if [[ "${2:-}" == "dashboards" ]]; then
        print_grafana_dashboards_help
      else
        print_grafana_help
      fi
      ;;
    *)
      echo "Error: Unknown help topic '$*'" >&2
      echo "Run 'ks --help' to see available commands." >&2
      return 1
      ;;
  esac
}

run_with_warning_filter() {
  if [[ "${KS_DEBUG}" == true ]]; then
    "$@"
  else
    "$@" 2> >(
      awk '
        /^warning:/ { next }
        /^evaluation warning:/ { next }
        { print > "/dev/stderr" }
      '
    )
  fi
}

# --- Discover repo root ---
# All paths are resolved with readlink -f because Nix `path:` flake URIs
# break on symlinks (e.g. ~/nixos-config -> .repos/ncrmro/nixos-config).
find_repo() {
  if [[ -n "${NIXOS_CONFIG_DIR:-}" ]] && [[ -f "$NIXOS_CONFIG_DIR/hosts.nix" ]]; then
    readlink -f "$NIXOS_CONFIG_DIR"
    return
  fi

  local dir
  dir=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$dir" ]] && [[ -f "$dir/hosts.nix" ]]; then
    readlink -f "$dir"
    return
  fi

  # Scan for any repo with hosts.nix in ~/.keystone/repos/
  if [[ -d "$HOME/.keystone/repos" ]]; then
    local match
    match=$(find "$HOME/.keystone/repos" -maxdepth 3 -name hosts.nix -print -quit)
    if [[ -n "$match" ]]; then
      readlink -f "$(dirname "$match")"
      return
    fi
  fi

  if [[ -f "$HOME/nixos-config/hosts.nix" ]]; then
    readlink -f "$HOME/nixos-config"
    return
  fi

  echo "Error: Cannot find nixos-config repo (no hosts.nix found)." >&2
  echo "Set NIXOS_CONFIG_DIR or run from within the repo." >&2
  exit 1
}

# --- Get repo registry from repos.nix ---
get_repos_registry() {
  local repo_root="$1"
  if [[ -f "$repo_root/repos.nix" ]]; then
    nix eval -f "$repo_root/repos.nix" --json 2>/dev/null
  else
    echo "{}"
  fi
}

# --- Resolve HOST from hosts.nix ---
resolve_host() {
  local hosts_nix="$1"
  local host="${2:-}"

  if [[ -z "$host" ]]; then
    local current
    current=$(hostname)
    host=$(nix eval -f "$hosts_nix" --raw \
      --apply "hosts: let m = builtins.filter (k: (builtins.getAttr k hosts).hostname == \"$current\") (builtins.attrNames hosts); in if m == [] then \"\" else builtins.head m")
    if [[ -z "$host" ]]; then
      echo "Error: No hosts.nix entry with hostname '$current'." >&2
      echo "Specify HOST explicitly: ks <command> <HOST>" >&2
      exit 1
    fi
  fi

  # Validate HOST exists
  if ! nix eval -f "$hosts_nix" "$host" --json >/dev/null 2>&1; then
    echo "Error: Unknown host '$host'." >&2
    echo "Known hosts:" >&2
    nix eval -f "$hosts_nix" --apply 'h: builtins.concatStringsSep "\n  " (builtins.attrNames h)' --raw >&2
    echo >&2
    exit 1
  fi

  echo "$host"
}

# --- Local override args (always applied when local repos exist) ---
# Returns --override-input flags for any local repos found.
# Silent and exits cleanly if no local repos are present.
local_override_args() {
  local repo_root="$1"
  local args=()
  local registry
  registry=$(get_repos_registry "$repo_root")

  # Parse registry entries
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local key input path
    key=$(echo "$line" | cut -d'|' -f1)
    input=$(echo "$line" | cut -d'|' -f2)

    # Check for checkout in standard locations:
    # 1. ~/.keystone/repos/{key}
    # 2. $repo_root/.repos/{name}
    # 3. $repo_root/.submodules/{name} (legacy)
    # 4. $repo_root/{name} (legacy)
    local name="${key##*/}"
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

  echo "${args[@]}"   # empty string if no repos found — no error, no exit
}

resolve_current_hm_user() {
  local repo_root="$1"
  local host="$2"
  if [[ -z "$host" ]]; then
    echo ""
    return
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
    return
  fi

  local fallback_user
  fallback_user=$(echo "$users_json" | jq -r 'map(select(startswith("agent-") | not)) | .[0] // ""')
  if [[ -n "$fallback_user" ]]; then
    echo "$fallback_user"
    return
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
    return
  fi

  local resolved_user
  resolved_user=$(resolve_current_hm_user "$repo_root" "$host")
  if [[ -z "$resolved_user" ]]; then
    echo "Error: could not resolve a home-manager user for host '$host'." >&2
    exit 1
  fi

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

require_ollama_enabled() {
  local repo_root="$1"
  local host="$2"
  local user="$3"
  local enabled
  enabled=$(resolve_ollama_enabled "$repo_root" "$host" "$user")
  if [[ "$enabled" != "true" ]]; then
    echo "Error: local model support is not enabled for home-manager user '$user' on host '$host'." >&2
    echo "Set keystone.terminal.ai.ollama.enable = true to use --local." >&2
    exit 1
  fi
}

resolve_local_model() {
  local explicit_model="$1"
  local default_model="$2"

  if [[ -n "$explicit_model" && "$explicit_model" != "default" ]]; then
    echo "$explicit_model"
    return
  fi

  if [[ -n "$default_model" ]]; then
    echo "$default_model"
    return
  fi

  echo "Error: no local model was provided and keystone.terminal.ai.ollama.defaultModel is not set." >&2
  exit 1
}

list_ollama_models() {
  local ollama_host="$1"

  if ! command -v ollama >/dev/null 2>&1; then
    echo "_ollama CLI not installed_"
    return
  fi

  local models
  models=$(OLLAMA_HOST="$ollama_host" ollama list 2>/dev/null | awk 'NR > 1 { print $1 }' || true)
  if [[ -z "$models" ]]; then
    echo "_No local models found_"
    return
  fi

  while IFS= read -r model; do
    [[ -n "$model" ]] && echo "- $model"
  done <<< "$models"
}

# --- Push keystone with fork fallback (REQ-016.9) ---
# Pushes the local keystone repo. If the user lacks push access to the upstream
# repo, forks it and pushes to the fork instead.
push_keystone_with_fork_fallback() {
  local ks_path="$1"
  [[ -z "$ks_path" || ! -d "$ks_path" ]] && return 0

  # Extract owner/repo from remote URL (handles SSH, HTTPS, and Forgejo SSH)
  local remote_url
  remote_url=$(git -C "$ks_path" remote get-url origin 2>/dev/null) || return 1
  local _tmp _repo _rest _owner owner_repo
  _tmp="${remote_url##*[:/]}"     # last path segment: "keystone.git"
  _repo="${_tmp%.git}"            # strip .git suffix
  _rest="${remote_url%"$_tmp"}"   # everything before last segment
  _rest="${_rest%[:/]}"           # strip trailing : or /
  _owner="${_rest##*[:/]}"        # owner segment
  owner_repo="${_owner}/${_repo}"

  if ! command -v gh >/dev/null 2>&1; then
    echo "Warning: gh CLI not found. Attempting direct push..." >&2
    run_with_warning_filter git -C "$ks_path" push || {
      echo "Error: Push failed. Install gh CLI for fork-fallback support." >&2
      return 1
    }
    return 0
  fi

  # Check collaborator permission
  local current_user permission
  current_user=$(gh api user -q .login 2>/dev/null) || current_user=""
  if [[ -n "$current_user" ]]; then
    permission=$(gh api "repos/$owner_repo/collaborators/$current_user/permission" -q '.permission' 2>/dev/null) || permission="none"
  else
    permission="none"
  fi

  case "$permission" in
    admin|maintain|write)
      echo "Pushing keystone (direct access)..."
      run_with_warning_filter git -C "$ks_path" push
      ;;
    *)
      echo "No push access to $owner_repo, pushing to fork..."
      # Ensure fork exists
      gh repo fork "$owner_repo" --clone=false 2>/dev/null || true
      local fork_remote
      local repo_name
      repo_name=$(basename "$owner_repo")
      repo_name="${repo_name%.git}"
      fork_remote="git@github.com:$current_user/${repo_name}.git"
      # Set origin to fork for this push (will be restored by user if needed)
      git -C "$ks_path" remote set-url origin "$fork_remote"
      run_with_warning_filter git -C "$ks_path" push -u origin "$(git -C "$ks_path" branch --show-current)"
      echo "Pushed to fork: $fork_remote"
      ;;
  esac
}

# --- List home-manager users for a host (REQ-016.3) ---
# Evaluates the flake to get all home-manager managed usernames for a host.
list_hm_users() {
  local repo_root="$1" host="$2"
  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"
  timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${host}.config.home-manager.users" \
    --apply 'builtins.attrNames' --json \
    "${override_args[@]}" 2>/dev/null | jq -r '.[]'
}

list_target_hm_users() {
  local repo_root="$1"
  local host="$2"
  local users
  users=$(list_hm_users "$repo_root" "$host") || return 1
  [[ -z "$users" ]] && return 0

  if [[ -n "$KS_HM_USERS_FILTER" ]]; then
    local matched=()
    local requested=()
    IFS=',' read -ra requested <<< "$KS_HM_USERS_FILTER"
    for requested_user in "${requested[@]}"; do
      local found=false
      while IFS= read -r available_user; do
        [[ -z "$available_user" ]] && continue
        if [[ "$available_user" == "$requested_user" ]]; then
          matched+=("$available_user")
          found=true
          break
        fi
      done <<< "$users"

      if [[ "$found" == false ]]; then
        echo "Error: home-manager user '$requested_user' is not configured on host '$host'." >&2
        return 1
      fi
    done

    printf '%s\n' "${matched[@]}"
    return 0
  fi

  if [[ "$KS_HM_ALL_USERS" == true ]]; then
    printf '%s\n' "$users"
    return 0
  fi

  local current_hostname host_hostname
  current_hostname=$(hostname)
  host_hostname=$(nix eval -f "$repo_root/hosts.nix" "$host.hostname" --raw 2>/dev/null || echo "")

  if [[ "$host_hostname" == "$current_hostname" ]]; then
    local current_user
    current_user=$(resolve_current_hm_user "$repo_root" "$host")
    if [[ -n "$current_user" ]]; then
      printf '%s\n' "$current_user"
      return 0
    fi
  fi

  printf '%s\n' "$users"
}

find_cached_hm_activation_path() {
  local host="$1"
  local user="$2"
  local record
  for record in "${HM_ACTIVATION_RECORDS[@]}"; do
    IFS=$'\t' read -r record_host record_user record_path <<< "$record"
    if [[ "$record_host" == "$host" && "$record_user" == "$user" ]]; then
      printf '%s\n' "$record_path"
      return 0
    fi
  done

  return 1
}

# --- Build home-manager activation packages only (REQ-016.1-3) ---
# Builds home-manager activationPackage for each user on each host, returning
# cached "host:user:store-path" entries reused during deployment.
build_home_manager_only() {
  local repo_root="$1"
  shift
  local target_hosts=("$@")

  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  local build_targets=()
  local target_map=()   # host:user pairs
  HM_ACTIVATION_RECORDS=()

  for h in "${target_hosts[@]}"; do
    local users
    users=$(list_target_hm_users "$repo_root" "$h") || continue
    if [[ -z "$users" ]]; then
      echo "Warning: No home-manager users for host $h, skipping." >&2
      continue
    fi
    while IFS= read -r user; do
      build_targets+=("$repo_root#nixosConfigurations.$h.config.home-manager.users.\"$user\".home.activationPackage")
      target_map+=("$h:$user")
    done <<< "$users"
  done

  if [[ ${#build_targets[@]} -eq 0 ]]; then
    echo "Warning: No home-manager targets to build." >&2
    return 0
  fi

  echo "Building home-manager profiles: ${target_map[*]}..."
  local build_paths=()
  local build_output
  if ! build_output=$(nix build --no-link --print-out-paths "${build_targets[@]}" "${override_args[@]}"); then
    echo "Error: Home-manager build failed." >&2
    exit 1
  fi
  mapfile -t build_paths <<< "$build_output"

  local i
  for i in "${!target_map[@]}"; do
    IFS=':' read -r host user <<< "${target_map[$i]}"
    HM_ACTIVATION_RECORDS+=("$host"$'\t'"$user"$'\t'"${build_paths[$i]}")
  done

  echo "Home-manager build complete."
}

# --- Deploy home-manager profiles only (REQ-016.4-5) ---
# Activates home-manager profiles for each user on each target host.
# Does not require sudo — activation runs as the owning user.
deploy_home_manager_only() {
  local repo_root="$1"
  shift
  local target_hosts=("$@")

  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  local current_hostname
  current_hostname=$(hostname)
  local hosts_nix="$repo_root/hosts.nix"

  for host in "${target_hosts[@]}"; do
    local users
    users=$(list_target_hm_users "$repo_root" "$host") || continue
    [[ -z "$users" ]] && continue

    local host_json host_hostname ssh_target fallback_ip
    host_json=$(nix eval -f "$hosts_nix" "$host" --json 2>/dev/null) || continue
    host_hostname=$(echo "$host_json" | jq -r '.hostname')
    ssh_target=$(echo "$host_json" | jq -r '.sshTarget // empty')
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')

    while IFS= read -r user; do
      # Resolve the activation package store path
      local activation_path
      activation_path=$(find_cached_hm_activation_path "$host" "$user") || activation_path=""
      if [[ -z "$activation_path" ]]; then
        activation_path=$(nix build --no-link --print-out-paths \
          "$repo_root#nixosConfigurations.$host.config.home-manager.users.\"$user\".home.activationPackage" \
          "${override_args[@]}" 2>/dev/null) || {
          echo "Error: Failed to resolve activation package for $user on $host" >&2
          continue
        }
      fi

      if [[ -z "$activation_path" ]]; then
        echo "Error: Failed to resolve activation package for $user on $host" >&2
        continue
      fi

      if [[ "$host_hostname" == "$current_hostname" ]]; then
        # LOCAL deploy — run activation as the user
        echo "Activating home-manager for $user on $host (local)..."
        sudo -u "$user" "$activation_path/activate" || {
          echo "Error: Activation failed for $user on $host" >&2
        }
      else
        # REMOTE deploy
        if [[ -z "$ssh_target" ]]; then
          echo "Error: $host has no sshTarget, cannot deploy remotely." >&2
          continue
        fi

        local resolved="$ssh_target"
        if [[ -n "$fallback_ip" ]]; then
          if ! ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${ssh_target}" true 2>/dev/null; then
            resolved="$fallback_ip"
            echo "Tailscale unavailable for $host, using LAN: $fallback_ip"
          fi
        fi

        echo "Activating home-manager for $user on $host (remote: $resolved)..."
        # Copy the closure to the remote host, then activate
        nix copy --to "ssh://root@$resolved" "$activation_path" "${override_args[@]}" 2>/dev/null || true
        # $user and $activation_path are intentionally expanded client-side
        # shellcheck disable=SC2029
        ssh "root@$resolved" "sudo -u '$user' '$activation_path/activate'" || {
          echo "Error: Remote activation failed for $user on $host" >&2
        }
      fi
    done <<< "$users"
  done
}

# --- Find local repo path ---
# Returns the local path for a given repo registry key (owner/repo).
find_local_repo() {
  local repo_root="$1" key="$2"
  local name="${key##*/}"

  if [[ -d "$HOME/.keystone/repos/$key" ]]; then
    echo "$HOME/.keystone/repos/$key"
  elif [[ -d "$repo_root/.repos/$name" ]]; then
    echo "$repo_root/.repos/$name"
  elif [[ -d "$repo_root/.submodules/$name" ]]; then
    echo "$repo_root/.submodules/$name"
  elif [[ -d "$repo_root/$name" ]]; then
    echo "$repo_root/$name"
  fi
}

# --- Pull (clone or update) a repo ---
pull_repo() {
  local repo_root="$1" key="$2" url="$3"
  local target="$HOME/.keystone/repos/$key"

  # Check for existing checkout in legacy locations
  local existing
  existing=$(find_local_repo "$repo_root" "$key")
  if [[ -n "$existing" ]]; then
    target="$existing"
  fi

  if [[ -e "$target/.git" ]]; then
    # Detect detached HEAD and recover by switching to the default branch before pulling
    if ! git -C "$target" symbolic-ref HEAD >/dev/null 2>&1; then
      local default_branch
      default_branch=$(git -C "$target" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
      default_branch="${default_branch:-main}"
      echo "Warning: $key is in detached HEAD state, switching to $default_branch..." >&2
      git -C "$target" checkout "$default_branch" || {
        echo "Error: failed to checkout $default_branch in $key" >&2
        return 1
      }
    fi
    echo "Pulling $key..."
    run_with_warning_filter git -C "$target" pull --ff-only
  else
    echo "Cloning $key..."
    mkdir -p "$(dirname "$target")"
    git clone "$url" "$target"
  fi
}

bootstrap_managed_repos() {
  local repo_root="$1"
  local registry="$2"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local key url
    key=$(echo "$line" | cut -d'|' -f1)
    url=$(echo "$line" | cut -d'|' -f2)
    pull_repo "$repo_root" "$key" "$url"
  done <<< "$(echo "$registry" | jq -r 'to_entries[] | "\(.key)|\(.value.url)"')"
}

# --- Verify repo is clean and pushed ---
verify_repo_clean() {
  local path="$1" name="$2"
  if [[ ! -d "$path" ]]; then
    return 0
  fi
  if ! git -C "$path" diff --quiet || ! git -C "$path" diff --cached --quiet; then
    echo "Error: $name has uncommitted changes at $path" >&2
    exit 1
  fi
  if [[ -n "$(git -C "$path" ls-files --others --exclude-standard)" ]]; then
    echo "Error: $name has untracked files at $path" >&2
    exit 1
  fi
  local local_ref remote_ref
  local_ref=$(git -C "$path" rev-parse HEAD)
  remote_ref=$(git -C "$path" rev-parse "@{upstream}" 2>/dev/null || echo "")
  if [[ -n "$remote_ref" && "$local_ref" != "$remote_ref" ]]; then
    echo "Error: $name has unpushed commits at $path" >&2
    exit 1
  fi
}

# --- Commands ---

cmd_sync_host_keys() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help)
        print_sync_host_keys_help
        return 0
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        exit 1
        ;;
    esac
  fi

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"

  # Get all host keys
  local all_hosts
  all_hosts=$(nix eval -f "$hosts_nix" --json --apply 'builtins.attrNames')
  local host_list
  host_list=$(echo "$all_hosts" | jq -r '.[]')

  local changed=0 skipped=0 failed=0

  for host in $host_list; do
    local host_json ssh_target fallback_ip
    host_json=$(nix eval -f "$hosts_nix" "$host" --json)
    ssh_target=$(echo "$host_json" | jq -r '.sshTarget // empty')

    if [[ -z "$ssh_target" ]]; then
      echo "SKIP $host (no sshTarget)"
      ((skipped++)) || true
      continue
    fi

    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')

    # Resolve SSH target with Tailscale → LAN fallback
    local resolved="$ssh_target"
    if ! ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${ssh_target}" true 2>/dev/null; then
      if [[ -n "$fallback_ip" ]]; then
        resolved="$fallback_ip"
        echo "  Tailscale unavailable for $host, using LAN: $fallback_ip"
      else
        echo "FAIL $host (unreachable via $ssh_target)"
        ((failed++)) || true
        continue
      fi
    fi

    # Fetch host public key
    local pubkey
    pubkey=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${resolved}" \
      'cat /etc/ssh/ssh_host_ed25519_key.pub' 2>/dev/null | awk '{print $1" "$2}') || true

    if [[ -z "$pubkey" ]]; then
      echo "FAIL $host (could not read host key from $resolved)"
      ((failed++)) || true
      continue
    fi

    # Check current value
    local current
    current=$(echo "$host_json" | jq -r '.hostPublicKey // empty')

    if [[ "$pubkey" == "$current" ]]; then
      echo "  OK $host (unchanged)"
      continue
    fi

    # Update hosts.nix — insert or replace hostPublicKey
    if [[ -n "$current" ]]; then
      # Replace existing hostPublicKey line
      sed -i "s|hostPublicKey = \"${current}\";|hostPublicKey = \"${pubkey}\";|" "$hosts_nix"
    else
      # Insert hostPublicKey after the role line for this host
      sed -i "/^  ${host} = {/,/^  };/ s|role = \"[^\"]*\";|&\n    hostPublicKey = \"${pubkey}\";|" "$hosts_nix"
    fi

    echo "  SET $host → ${pubkey:0:40}..."
    ((changed++)) || true
  done

  echo ""
  echo "Summary: $changed updated, $skipped skipped, $failed failed"
  if [[ $changed -gt 0 ]]; then
    echo "Review changes with: git diff hosts.nix"
  fi
}

cmd_build() {
  local hosts_arg="" lock=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_build_help
        return 0
        ;;
      --dev) shift ;;  # kept for backwards compat, no-op
      --lock) lock=true; shift ;;
      --user)
        [[ $# -lt 2 ]] && { echo "Error: --user requires a value" >&2; exit 1; }
        KS_HM_USERS_FILTER="$2"
        shift 2
        ;;
      --all-users)
        KS_HM_ALL_USERS=true
        shift
        ;;
      -*) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
      *) hosts_arg="$1"; shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"

  local target_hosts=()
  if [[ -z "$hosts_arg" ]]; then
    target_hosts+=("$(resolve_host "$hosts_nix" "")")
  else
    # Split by comma
    IFS=',' read -ra ADDR <<< "$hosts_arg"
    for h in "${ADDR[@]}"; do
      target_hosts+=("$(resolve_host "$hosts_nix" "$h")")
    done
  fi

  if [[ "$lock" == true ]]; then
    # ── LOCK MODE (REQ-016.7): full system build with lock workflow ──
    # Step 1: Verify repos are clean
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      local path
      path=$(find_local_repo "$repo_root" "$key")
      [[ -n "$path" ]] && verify_repo_clean "$path" "$key"
    done <<< "$(get_repos_registry "$repo_root" | jq -r 'to_entries[].key')"

    # Step 2: Push keystone with fork fallback (REQ-016.9)
    local ks_path
    ks_path=$(find_local_repo "$repo_root" "ncrmro/keystone")
    [[ -n "$ks_path" ]] && push_keystone_with_fork_fallback "$ks_path"

    # Step 3: Lock flake inputs
    echo "Locking flake inputs..."
    local inputs
    inputs=$(get_repos_registry "$repo_root" | jq -r 'to_entries[].value.flakeInput | select(. != null)')
    # shellcheck disable=SC2086
    nix flake update $inputs --flake "$repo_root"

    # Step 4: Full system build with local overrides (REQ-019.5)
    local override_args=()
    read -ra override_args <<< "$(local_override_args "$repo_root")"
    local build_targets=()
    for h in "${target_hosts[@]}"; do
      build_targets+=("$repo_root#nixosConfigurations.$h.config.system.build.toplevel")
    done
    echo "Building (full system): ${target_hosts[*]}..."
    nix build --no-link "${build_targets[@]}" "${override_args[@]}"

    # Step 5: Commit flake.lock only after successful build (REQ-019.8)
    if ! git -C "$repo_root" diff --quiet flake.lock; then
      echo "Committing flake.lock..."
      git -C "$repo_root" add flake.lock
      git -C "$repo_root" commit -m "chore: relock keystone + agenix-secrets"
    fi

    # Step 6: Push nixos-config
    echo "Pushing nixos-config..."
    git -C "$repo_root" push
    echo "Lock + build complete for: ${target_hosts[*]}"
  else
    # ── DEV MODE (REQ-016.1): home-manager only build ──
    build_home_manager_only "$repo_root" "${target_hosts[@]}"
  fi
}

# --- Switch command (fast deploy) ---
cmd_switch() {
  local mode="switch" hosts_arg=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_switch_help
        return 0
        ;;
      --boot) mode="boot"; shift ;;
      -*) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
      *) hosts_arg="$1"; shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"
  KS_HM_USERS_FILTER=""
  KS_HM_ALL_USERS=false
  HM_ACTIVATION_RECORDS=()

  local target_hosts=()
  if [[ -z "$hosts_arg" ]]; then
    target_hosts+=("$(resolve_host "$hosts_nix" "")")
  else
    # Split by comma
    IFS=',' read -ra ADDR <<< "$hosts_arg"
    for h in "${ADDR[@]}"; do
      target_hosts+=("$(resolve_host "$hosts_nix" "$h")")
    done
  fi

  # Cache sudo if local host is targeted
  local needs_sudo=false current_hostname
  current_hostname=$(hostname)
  for h in "${target_hosts[@]}"; do
    local h_hostname
    h_hostname=$(nix eval -f "$hosts_nix" "$h.hostname" --raw)
    if [[ "$h_hostname" == "$current_hostname" ]]; then
      needs_sudo=true; break
    fi
  done

  if [[ "$needs_sudo" == true ]]; then
    echo "Caching sudo credentials..."
    sudo -v
  fi

  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  # Step 1: Build ALL in parallel for efficiency
  local build_targets=()
  for h in "${target_hosts[@]}"; do
    build_targets+=("$repo_root#nixosConfigurations.$h.config.system.build.toplevel")
  done

  echo "Building: ${target_hosts[*]}..."
  local build_paths=()
  mapfile -t build_paths < <(nix build --no-link --print-out-paths "${build_targets[@]}" "${override_args[@]}")

  # Step 2: Deploy sequentially using the built store paths
  for i in "${!target_hosts[@]}"; do
    local host="${target_hosts[$i]}"
    local path="${build_paths[$i]}"
    local host_json ssh_target fallback_ip host_hostname
    host_json=$(nix eval -f "$hosts_nix" "$host" --json)
    ssh_target=$(echo "$host_json" | jq -r '.sshTarget // empty')
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')
    host_hostname=$(echo "$host_json" | jq -r '.hostname')

    if [[ "$host_hostname" == "$current_hostname" ]]; then
      local old_sw new_sw old_kernel new_kernel old_initrd new_initrd etc_changed=false
      old_sw=$(readlink -f /run/current-system/sw 2>/dev/null || echo "old")
      new_sw=$(readlink -f "$path/sw" 2>/dev/null || echo "new")
      old_kernel=$(readlink -f /run/current-system/kernel 2>/dev/null || echo "old")
      new_kernel=$(readlink -f "$path/kernel" 2>/dev/null || echo "new")
      old_initrd=$(readlink -f /run/current-system/initrd 2>/dev/null || echo "old")
      new_initrd=$(readlink -f "$path/initrd" 2>/dev/null || echo "new")

      if ! diff -r -q --exclude="per-user" "$(readlink -f /run/current-system/etc)" "$(readlink -f "$path/etc")" >/dev/null 2>&1; then
        etc_changed=true
      fi

      if [[ "$old_sw" == "$new_sw" && "$old_kernel" == "$new_kernel" && "$old_initrd" == "$new_initrd" && "$etc_changed" == false ]]; then
        echo "OS core unchanged. Activating fast home-manager switch locally..."
        deploy_home_manager_only "$repo_root" "$host"
        sudo nix-env -p /nix/var/nix/profiles/system --set "$path"
        echo "Skipped switch-to-configuration for $host because the system closure is unchanged."
      else
        echo "Deploying $host locally ($mode)..."
        sudo nix-env -p /nix/var/nix/profiles/system --set "$path"
        sudo touch /var/run/nixos-rebuild-safe-to-update-bootloader
        sudo "$path/bin/switch-to-configuration" "$mode"
      fi
    else
      if [[ -z "$ssh_target" ]]; then
        echo "Error: $host has no sshTarget (local-only host). Cannot deploy remotely." >&2; exit 1
      fi
      local resolved="$ssh_target"
      if [[ -n "$fallback_ip" ]]; then
        if ! ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${ssh_target}" true 2>/dev/null; then
          resolved="$fallback_ip"
        fi
      fi
      
      echo "Deploying $host to root@$resolved ($mode)..."
      nix copy --to "ssh://root@$resolved" "$path"
      
      # Check remote OS state
      local new_sw new_kernel new_initrd check_cmd remote_status
      new_sw=$(readlink -f "$path/sw" 2>/dev/null || echo "new")
      new_kernel=$(readlink -f "$path/kernel" 2>/dev/null || echo "new")
      new_initrd=$(readlink -f "$path/initrd" 2>/dev/null || echo "new")
      
      check_cmd="
        old_sw=\$(readlink -f /run/current-system/sw 2>/dev/null || echo 'old')
        old_kernel=\$(readlink -f /run/current-system/kernel 2>/dev/null || echo 'old')
        old_initrd=\$(readlink -f /run/current-system/initrd 2>/dev/null || echo 'old')
        if [[ \"\$old_sw\" == \"$new_sw\" && \"\$old_kernel\" == \"$new_kernel\" && \"\$old_initrd\" == \"$new_initrd\" ]]; then
          if ! diff -r -q --exclude='per-user' \"\$(readlink -f /run/current-system/etc)\" \"\$(readlink -f $path/etc)\" >/dev/null 2>&1; then
            echo 'OS'
          else
            echo 'HM'
          fi
        else
          echo 'OS'
        fi
      "
      # shellcheck disable=SC2029
      remote_status=$(ssh "root@$resolved" "$check_cmd")

      if [[ "$remote_status" == "HM" ]]; then
        echo "OS core unchanged. Activating fast home-manager switch remotely..."
        deploy_home_manager_only "$repo_root" "$host"
        # shellcheck disable=SC2029
        ssh "root@$resolved" "nix-env -p /nix/var/nix/profiles/system --set $path"
        echo "Skipped switch-to-configuration for $host because the system closure is unchanged."
      else
        # shellcheck disable=SC2029
        ssh "root@$resolved" "nix-env -p /nix/var/nix/profiles/system --set $path && touch /var/run/nixos-rebuild-safe-to-update-bootloader && $path/bin/switch-to-configuration $mode"
      fi
    fi
    echo "Update complete for $host"
  done
  cmd_grafana "dashboards" "apply"
}

# --- Update command ---
cmd_update() {
  local mode="switch" hosts_arg="" pull=false lock=true
  KS_HM_USERS_FILTER=""
  KS_HM_ALL_USERS=false
  HM_ACTIVATION_RECORDS=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_update_help
        return 0
        ;;
      --debug) KS_DEBUG=true; shift ;;
      --dev) lock=false; shift ;;
      --boot) mode="boot"; shift ;;
      --pull) pull=true; shift ;;
      --lock) lock=true; shift ;;
      --user)
        [[ $# -lt 2 ]] && { echo "Error: --user requires a value" >&2; exit 1; }
        KS_HM_USERS_FILTER="$2"
        shift 2
        ;;
      --all-users)
        KS_HM_ALL_USERS=true
        shift
        ;;
      -*) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
      *) hosts_arg="$1"; shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"

  local target_hosts=()
  if [[ -z "$hosts_arg" ]]; then
    target_hosts+=("$(resolve_host "$hosts_nix" "")")
  else
    # Split by comma
    IFS=',' read -ra ADDR <<< "$hosts_arg"
    for h in "${ADDR[@]}"; do
      target_hosts+=("$(resolve_host "$hosts_nix" "$h")")
    done
  fi

  local registry
  registry=$(get_repos_registry "$repo_root")

  # --- Handle --pull (standalone, no lock) ---
  if [[ "$pull" == true && "$lock" != true ]]; then
    bootstrap_managed_repos "$repo_root" "$registry"
    echo "Pull complete."
    return
  fi

  # ── DEV MODE: home-manager only (REQ-016.2) ──────────────────────────────────
  if [[ "$lock" != true ]]; then
    bootstrap_managed_repos "$repo_root" "$registry"
    build_home_manager_only "$repo_root" "${target_hosts[@]}"
    deploy_home_manager_only "$repo_root" "${target_hosts[@]}"
    echo "Dev mode update complete (home-manager only) for: ${target_hosts[*]}"
    return
  fi

  # ── LOCK MODE: full system rebuild ──────────────────────────────────────────

  # Step 1: Cache sudo credentials immediately — before any pull, lock, or build.
  # Any update that reaches this point may deploy locally; prompt upfront so the
  # user is not interrupted later.
  local needs_sudo=false
  local current_hostname
  current_hostname=$(hostname)
  for h in "${target_hosts[@]}"; do
    local h_hostname
    h_hostname=$(nix eval -f "$hosts_nix" "$h.hostname" --raw)
    if [[ "$h_hostname" == "$current_hostname" ]]; then
      needs_sudo=true
      break
    fi
  done

  SUDO_KEEPALIVE_PID=""
  if [[ "$needs_sudo" == true ]]; then
    echo "Caching sudo credentials (needed for local deploy)..."
    sudo -v
    # Keepalive: refresh every 60 s so a long pull/lock/build doesn't expire the ticket.
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; trap - EXIT' EXIT
  fi

  # ── UPFRONT PHASE ───────────────────────────────────────────────────────────
  # Step 1: Pull nixos-config so we operate on latest
  echo "Pulling nixos-config..."
  run_with_warning_filter git -C "$repo_root" pull --ff-only

  # Step 2: Pull all repos in registry
  bootstrap_managed_repos "$repo_root" "$registry"

  # Step 3: Verify repos are clean and fully pushed before locking
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    local path
    path=$(find_local_repo "$repo_root" "$key")
    [[ -n "$path" ]] && verify_repo_clean "$path" "$key"
  done <<< "$(echo "$registry" | jq -r 'to_entries[].key')"

  # Step 3.5: Push keystone with fork fallback (REQ-016.8-9)
  local ks_path
  ks_path=$(find_local_repo "$repo_root" "ncrmro/keystone")
  [[ -n "$ks_path" ]] && push_keystone_with_fork_fallback "$ks_path"

  # Step 4: Update flake.lock BEFORE building so the build validates what will be committed
  echo "Locking flake inputs..."
  local inputs
  inputs=$(echo "$registry" | jq -r 'to_entries[].value.flakeInput | select(. != null)')
  # shellcheck disable=SC2086
  run_with_warning_filter nix flake update $inputs --flake "$repo_root"

  # Step 5: Commit flake.lock (if changed)
  if ! git -C "$repo_root" diff --quiet flake.lock; then
    echo "Committing flake.lock..."
    git -C "$repo_root" add flake.lock
    git -C "$repo_root" commit -m "chore: relock keystone + agenix-secrets"
  fi

  # Always use local overrides when repos are present
  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  # ── BUILD PHASE ─────────────────────────────────────────────────────────────
  # Step 7: Build all targets in a single invocation (nix parallelises internally)
  local build_targets=()
  for h in "${target_hosts[@]}"; do
    build_targets+=("$repo_root#nixosConfigurations.$h.config.system.build.toplevel")
  done

  echo "Building: ${target_hosts[*]}..."
  local build_paths=()
  if ! mapfile -t build_paths < <(run_with_warning_filter nix build --no-link --print-out-paths "${build_targets[@]}" "${override_args[@]}"); then
    local rerun_cmd="ks update"
    if [[ "${KS_DEBUG}" == true ]]; then
      rerun_cmd+=" --debug"
    fi
    if [[ "$mode" == "boot" ]]; then
      rerun_cmd+=" --boot"
    fi
    rerun_cmd+=" --lock"
    if [[ -n "$hosts_arg" ]]; then
      rerun_cmd+=" $hosts_arg"
    fi
    echo ""
    echo "ERROR: Build failed."
    echo "Fix the build errors above, then rerun: $rerun_cmd"
    exit 1
  fi

  # ── POST-BUILD PHASE ────────────────────────────────────────────────────────
  # Step 8: Push flake.lock only after a successful build
  echo "Pushing nixos-config..."
  if ! run_with_warning_filter git -C "$repo_root" pull --rebase origin "$(git -C "$repo_root" branch --show-current)"; then
    echo ""
    echo "ERROR: Failed to rebase nixos-config against origin."
    echo "Resolve conflicts manually, then run: git push"
    exit 1
  fi
  if ! run_with_warning_filter git -C "$repo_root" push; then
    echo ""
    echo "ERROR: Failed to push nixos-config."
    echo "Run 'git pull --rebase && git push' to retry."
    exit 1
  fi

  # Step 2: Deploy sequentially using the built store paths
  for i in "${!target_hosts[@]}"; do
    local host="${target_hosts[$i]}"
    local path="${build_paths[$i]}"
    local host_json ssh_target fallback_ip host_hostname
    host_json=$(nix eval -f "$hosts_nix" "$host" --json)
    ssh_target=$(echo "$host_json" | jq -r '.sshTarget // empty')
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')
    host_hostname=$(echo "$host_json" | jq -r '.hostname')

    if [[ "$host_hostname" == "$current_hostname" ]]; then
      local old_sw new_sw old_kernel new_kernel old_initrd new_initrd etc_changed=false
      old_sw=$(readlink -f /run/current-system/sw 2>/dev/null || echo "old")
      new_sw=$(readlink -f "$path/sw" 2>/dev/null || echo "new")
      old_kernel=$(readlink -f /run/current-system/kernel 2>/dev/null || echo "old")
      new_kernel=$(readlink -f "$path/kernel" 2>/dev/null || echo "new")
      old_initrd=$(readlink -f /run/current-system/initrd 2>/dev/null || echo "old")
      new_initrd=$(readlink -f "$path/initrd" 2>/dev/null || echo "new")

      if ! diff -r -q --exclude="per-user" "$(readlink -f /run/current-system/etc)" "$(readlink -f "$path/etc")" >/dev/null 2>&1; then
        etc_changed=true
      fi

      if [[ "$old_sw" == "$new_sw" && "$old_kernel" == "$new_kernel" && "$old_initrd" == "$new_initrd" && "$etc_changed" == false ]]; then
        echo "OS core unchanged. Activating fast home-manager switch locally..."
        deploy_home_manager_only "$repo_root" "$host"
        sudo nix-env -p /nix/var/nix/profiles/system --set "$path"
        sudo touch /var/run/nixos-rebuild-safe-to-update-bootloader
        sudo "$path/bin/switch-to-configuration" boot
      else
        echo "Deploying $host locally ($mode)..."
        sudo nix-env -p /nix/var/nix/profiles/system --set "$path"
        sudo touch /var/run/nixos-rebuild-safe-to-update-bootloader
        sudo "$path/bin/switch-to-configuration" "$mode"
      fi
    else
      if [[ -z "$ssh_target" ]]; then
        echo "Error: $host has no sshTarget (local-only host). Cannot deploy remotely." >&2; exit 1
      fi
      local resolved="$ssh_target"
      if [[ -n "$fallback_ip" ]]; then
        if ! ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${ssh_target}" true 2>/dev/null; then
          resolved="$fallback_ip"
        fi
      fi
      
      echo "Deploying $host to root@$resolved ($mode)..."
      nix copy --to "ssh://root@$resolved" "$path"
      
      # Check remote OS state
      local new_sw new_kernel new_initrd check_cmd remote_status
      new_sw=$(readlink -f "$path/sw" 2>/dev/null || echo "new")
      new_kernel=$(readlink -f "$path/kernel" 2>/dev/null || echo "new")
      new_initrd=$(readlink -f "$path/initrd" 2>/dev/null || echo "new")
      
      check_cmd="
        old_sw=\$(readlink -f /run/current-system/sw 2>/dev/null || echo 'old')
        old_kernel=\$(readlink -f /run/current-system/kernel 2>/dev/null || echo 'old')
        old_initrd=\$(readlink -f /run/current-system/initrd 2>/dev/null || echo 'old')
        if [[ \"\$old_sw\" == \"$new_sw\" && \"\$old_kernel\" == \"$new_kernel\" && \"\$old_initrd\" == \"$new_initrd\" ]]; then
          if ! diff -r -q --exclude='per-user' \"\$(readlink -f /run/current-system/etc)\" \"\$(readlink -f $path/etc)\" >/dev/null 2>&1; then
            echo 'OS'
          else
            echo 'HM'
          fi
        else
          echo 'OS'
        fi
      "
      # shellcheck disable=SC2029
      remote_status=$(ssh "root@$resolved" "$check_cmd")

      if [[ "$remote_status" == "HM" ]]; then
        echo "OS core unchanged. Activating fast home-manager switch remotely..."
        deploy_home_manager_only "$repo_root" "$host"
        # shellcheck disable=SC2029
        ssh "root@$resolved" "nix-env -p /nix/var/nix/profiles/system --set $path && touch /var/run/nixos-rebuild-safe-to-update-bootloader && $path/bin/switch-to-configuration boot"
      else
        # shellcheck disable=SC2029
        ssh "root@$resolved" "nix-env -p /nix/var/nix/profiles/system --set $path && touch /var/run/nixos-rebuild-safe-to-update-bootloader && $path/bin/switch-to-configuration $mode"
      fi
    fi

    [[ "$mode" == "boot" ]] && echo "Reboot required to apply changes for $host."
    echo "Update complete for $host"
  done
  cmd_grafana "dashboards" "apply"
}

# --- Find keystone repo (where conventions/ lives) ---
# Returns the path to the local keystone repo clone, or empty string if not found.
find_keystone_repo() {
  local repo_root="$1"
  local ks_path
  ks_path=$(find_local_repo "$repo_root" "ncrmro/keystone")
  echo "${ks_path:-}"
}

# --- Load conventions from keystone repo ---
# Concatenates all *.md files from conventions/ in the keystone repo.
# Prints nothing (no error) if the directory is not found.
load_conventions() {
  local ks_repo="$1"
  if [[ -z "$ks_repo" || ! -d "$ks_repo/conventions" ]]; then
    return 0
  fi
  local first=true
  for f in "$ks_repo/conventions"/*.md; do
    [[ -f "$f" ]] || continue
    if [[ "$first" == true ]]; then
      first=false
    else
      echo ""
      echo "---"
      echo ""
    fi
    cat "$f"
  done
}

grafana_dashboards_dir() {
  local repo_root="$1"
  local ks_repo
  ks_repo=$(find_keystone_repo "$repo_root")

  if [[ -n "$ks_repo" && -d "$ks_repo/modules/server/services/grafana/dashboards" ]]; then
    printf '%s\n' "$ks_repo/modules/server/services/grafana/dashboards"
    return
  fi

  if [[ -d "$repo_root/modules/server/services/grafana/dashboards" ]]; then
    printf '%s\n' "$repo_root/modules/server/services/grafana/dashboards"
    return
  fi

  echo "Error: could not locate keystone Grafana dashboards directory." >&2
  exit 1
}

resolve_grafana_url() {
  local repo_root="$1"
  if [[ -n "${GRAFANA_URL:-}" ]]; then
    printf '%s\n' "$GRAFANA_URL"
    return
  fi

  local hosts_nix="$repo_root/hosts.nix"
  if [[ ! -f "$hosts_nix" ]]; then
    echo "Error: hosts.nix not found while resolving Grafana URL." >&2
    exit 1
  fi

  local current_hostname current_host domain subdomain grafana_host=""
  current_hostname=$(hostname)
  current_host=$(nix eval -f "$hosts_nix" --raw \
    --apply "hosts: let m = builtins.filter (k: (builtins.getAttr k hosts).hostname == \"$current_hostname\") (builtins.attrNames hosts); in if m == [] then \"\" else builtins.head m" \
    2>/dev/null || true)

  # Try to find a host with grafana enabled
  if [[ -n "$current_host" ]]; then
    if [[ "$(nix eval "$repo_root#nixosConfigurations.${current_host}.config.keystone.server.services.grafana.enable" --json 2>/dev/null)" == "true" ]]; then
      grafana_host="$current_host"
    fi
  fi

  if [[ -z "$grafana_host" ]]; then
    # Scan all server hosts for grafana.enable
    local server_hosts
    server_hosts=$(nix eval -f "$hosts_nix" --json --apply "hosts: builtins.filter (k: (builtins.getAttr k hosts).role == \"server\") (builtins.attrNames hosts)" 2>/dev/null || echo "[]")
    for host in $(echo "$server_hosts" | jq -r '.[]'); do
      if [[ "$(nix eval "$repo_root#nixosConfigurations.${host}.config.keystone.server.services.grafana.enable" --json 2>/dev/null)" == "true" ]]; then
        grafana_host="$host"
        break
      fi
    done
  fi

  if [[ -z "$grafana_host" ]]; then
    echo "Error: could not find any host with keystone.server.services.grafana.enable = true. Set GRAFANA_URL." >&2
    exit 1
  fi

  subdomain=$(nix eval "$repo_root#nixosConfigurations.${grafana_host}.config.keystone.server.services.grafana.subdomain" --raw 2>/dev/null || printf 'grafana')
  domain=$(nix eval "$repo_root#nixosConfigurations.${grafana_host}.config.keystone.domain" --raw 2>/dev/null || true)

  if [[ -z "$domain" ]]; then
    echo "Error: could not resolve Grafana URL from config for host '$grafana_host'. Set GRAFANA_URL." >&2
    exit 1
  fi

  printf 'https://%s.%s\n' "$subdomain" "$domain"
}

resolve_grafana_api_key() {
  if [[ -n "${GRAFANA_API_KEY:-}" ]]; then
    printf '%s\n' "$GRAFANA_API_KEY"
    return
  fi

  if [[ -f /run/agenix/grafana-api-token ]]; then
    tr -d '\n' < /run/agenix/grafana-api-token
    return
  fi

  return 1
}

cmd_grafana_dashboards() {
  local action="${1:-}"
  shift || true

  case "$action" in
    -h|--help)
      print_grafana_dashboards_help
      return 0
      ;;
    "")
      echo "Error: Missing grafana dashboards action" >&2
      print_grafana_dashboards_help >&2
      exit 1
      ;;
  esac

  local repo_root dashboards_dir grafana_url grafana_api_key
  repo_root=$(find_repo)
  dashboards_dir=$(grafana_dashboards_dir "$repo_root")
  
  grafana_url=$(resolve_grafana_url "$repo_root" 2>/dev/null || true)
  if [[ -z "$grafana_url" ]]; then
    echo "Warning: skipping dashboard sync (could not resolve Grafana URL). Set GRAFANA_URL." >&2
    return 0
  fi

  grafana_api_key=$(resolve_grafana_api_key 2>/dev/null || true)
  if [[ -z "$grafana_api_key" ]]; then
    echo "Warning: Keystone Grafana API token is not configured on this host." >&2
    echo "To enable dashboard synchronization and Grafana MCP, you must:" >&2
    echo "  1. Define 'secrets/grafana-api-token.age' in your nixos-config/secrets.nix" >&2
    echo "  2. Assign it to this host's public key" >&2
    echo "  3. Rebuild and switch this host: ks switch" >&2
    echo "" >&2
    # TODO: In the future, keystone can automate this by submitting a PR to your nixos-config.
    echo "For now, you can also set the GRAFANA_API_KEY environment variable." >&2
    return 0
  fi

  case "$action" in
    apply)
      local file uid payload
      shopt -s nullglob
      for file in "$dashboards_dir"/*.json; do
        uid=$(jq -r '.uid // empty' "$file")
        if [[ -z "$uid" ]]; then
          echo "Skipping $file (missing uid)" >&2
          continue
        fi
        payload=$(jq -cn --slurpfile dashboard "$file" '{dashboard: $dashboard[0], overwrite: true}')
        curl -fsS \
          -H "Authorization: Bearer ${grafana_api_key}" \
          -H 'Content-Type: application/json' \
          -X POST \
          --data "$payload" \
          "${grafana_url}/api/dashboards/db" >/dev/null
        echo "Applied ${uid}"
      done
      ;;
    export)
      local uid="${1:-}"
      local target_file response body
      if [[ -z "$uid" ]]; then
        print_grafana_dashboards_help >&2
        exit 1
      fi

      target_file=$(find "$dashboards_dir" -maxdepth 1 -type f -name '*.json' -print0 | \
        while IFS= read -r -d '' file; do
          if [[ "$(jq -r '.uid // empty' "$file")" == "$uid" ]]; then
            printf '%s\n' "$file"
            break
          fi
        done)

      if [[ -z "$target_file" ]]; then
        echo "Error: no checked-in dashboard JSON with uid '$uid' under $dashboards_dir." >&2
        exit 1
      fi

      response=$(curl -fsS \
        -H "Authorization: Bearer ${grafana_api_key}" \
        "${grafana_url}/api/dashboards/uid/${uid}")
      body=$(printf '%s\n' "$response" | jq '.dashboard | del(.id, .version)')
      printf '%s\n' "$body" > "$target_file"
      echo "Exported ${uid} -> ${target_file}"
      ;;
    *)
      echo "Error: Unknown grafana dashboards action '$action'" >&2
      print_grafana_dashboards_help >&2
      exit 1
      ;;
  esac
}

cmd_grafana() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    -h|--help)
      print_grafana_help
      ;;
    "")
      echo "Error: Missing grafana subcommand" >&2
      print_grafana_help >&2
      exit 1
      ;;
    dashboards)
      cmd_grafana_dashboards "$@"
      ;;
    *)
      echo "Error: Unknown grafana subcommand '$subcommand'" >&2
      print_grafana_help >&2
      exit 1
      ;;
  esac
}

# --- Build host table from hosts.nix ---
build_host_table() {
  local hosts_nix="$1"
  local current_hostname
  current_hostname=$(hostname)

  local all_hosts
  all_hosts=$(nix eval -f "$hosts_nix" --json --apply 'builtins.attrNames' 2>/dev/null) || return 0
  local host_list
  host_list=$(echo "$all_hosts" | jq -r '.[]')

  echo "| Host | Hostname | Role | SSH Target | Fallback IP | Build Remote |"
  echo "|------|----------|------|------------|-------------|--------------|"
  for host in $host_list; do
    local host_json hostname role ssh_target fallback_ip build_on_remote marker
    host_json=$(nix eval -f "$hosts_nix" "$host" --json 2>/dev/null) || continue
    hostname=$(echo "$host_json" | jq -r '.hostname // ""')
    role=$(echo "$host_json" | jq -r '.role // ""')
    ssh_target=$(echo "$host_json" | jq -r '.sshTarget // ""')
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // ""')
    build_on_remote=$(echo "$host_json" | jq -r '.buildOnRemote // false')
    marker=""
    [[ "$hostname" == "$current_hostname" ]] && marker=" ← current"
    echo "| $host$marker | $hostname | $role | ${ssh_target:-—} | ${fallback_ip:-—} | $build_on_remote |"
  done
}

# --- Build user/agent table from nixos-config flake ---
# Evaluates keystone.os.users and keystone.os.agents for the given host.
# Prints nothing on failure or timeout (graceful degradation).
# NOTE: First-call may take 30-60s on a cold Nix eval cache; subsequent calls
# are fast due to Nix's built-in evaluation cache.
build_user_table() {
  local repo_root="$1"
  local current_host="$2"

  [[ -z "$current_host" ]] && return 0

  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  local users_json agents_json
  users_json=$(timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${current_host}.config.keystone.os.users" \
    --json \
    --apply 'u: builtins.mapAttrs (_: v: { fullName = v.fullName or ""; }) u' \
    "${override_args[@]}" \
    2>/dev/null) || users_json=""
  agents_json=$(timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${current_host}.config.keystone.os.agents" \
    --json \
    --apply 'a: builtins.mapAttrs (_: v: { fullName = v.fullName or ""; email = v.email or ""; host = v.host or ""; }) a' \
    "${override_args[@]}" \
    2>/dev/null) || agents_json=""

  [[ -z "$users_json" && -z "$agents_json" ]] && return 0

  echo "| Name | Type | Full Name | Email | Host |"
  echo "|------|------|-----------|-------|------|"
  if [[ -n "$users_json" ]]; then
    echo "$users_json" | jq -r 'to_entries[] | "| \(.key) | user | \(.value.fullName) | | |"'
  fi
  if [[ -n "$agents_json" ]]; then
    echo "$agents_json" | jq -r 'to_entries[] | "| \(.key) | agent | \(.value.fullName) | \(.value.email) | \(.value.host) |"'
  fi
}

# --- ks update workflow documentation (REQ-014.5) ---
# NOTE: ks update/switch requires sudo. Agents MUST NOT run it directly.
# This documentation is injected as reference knowledge so the agent can
# explain the workflow to humans or understand the deploy pipeline.
ks_update_workflow_docs() {
  cat <<'WFDOC'
## Deployment Workflows (Reference Only — requires sudo, human-only)

> **WARNING**: `ks update` and `ks switch` call `sudo` and activate system
> configurations. Agents MUST NOT run these commands. Use `ks build` to test
> changes, then ask a human to deploy.

### 1. `ks update` — Full Release Workflow
`ks update [--debug] [--dev] [--boot] [--pull] [--lock] [HOSTS]`

Use this for official updates. It ensures everything is pulled, locked,
verified, and pushed to origin before deployment.

1. **Pull** nixos-config and all registered repos
2. **Verify** all repos are clean
3. **Lock** flake inputs and **Commit** flake.lock
4. **Build** all target hosts in parallel for verification
5. **Push** nixos-config to origin
6. **Deploy** hosts sequentially using the verified store paths (fast activation)

### 2. `ks switch` — Fast Iteration Workflow
`ks switch [--boot] [HOSTS]`

Use this for local development. It builds and activates the current state of
the local repo immediately, skipping pull, lock, and push phases.

### Flags (update)

| Flag | Effect |
|------|--------|
| `--debug` | Show warning lines from underlying `git`/`nix` commands |
| `--dev` | Home-manager only: clone or pull managed repos, then build + activate user/agent profiles |
| `--boot` | Use `boot` instead of `switch` mode (reboot required to apply) |
| `--pull` | Pull repos only — no build or deploy |
| `--lock` | Force locking (default when `--dev` is not set), full system rebuild |

### HOSTS

Comma-separated list of host names (e.g. `ocean,maia`). Defaults to current hostname.
Risky hosts should be placed last: `workstation,ocean`.
WFDOC
}

# --- Local flake override documentation (REQ-014.7) ---
local_flake_override_docs() {
  cat <<'OFDOC'
## Local Flake Overrides

`ks` auto-detects local repo clones and passes
`--override-input` flags to every `nix build` / `ks switch` call —
no manual flags needed.

### Detected Paths (in order)

| Input | Paths checked |
|-------|---------------|
| <input> | `~/.keystone/repos/<owner>/<repo>`, `<repo>/.repos/<name>`, `<repo>/.submodules/<name>` |

### Workflow for Repo Changes

1. Edit files in local repo checkout
2. Test with `ks build --dev` (builds home-manager with local overrides)
3. Apply locally with `ks switch` (system update with local overrides)
4. Once satisfied, commit + push the repo
5. Run `ks update` for official deployment (locks and pushes nixos-config)
OFDOC
}

# --- Fleet health: check reachability + NixOS generation for all hosts ---
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
    local host_json hostname ssh_target fallback_ip
    host_json=$(nix eval -f "$hosts_nix" "$host" --json 2>/dev/null) || continue
    hostname=$(echo "$host_json" | jq -r '.hostname // ""')
    ssh_target=$(echo "$host_json" | jq -r '.sshTarget // ""')
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // ""')

    # Current host — use local data
    if [[ "$hostname" == "$current_hostname" ]]; then
      echo "| $host | local | $local_gen | ← current |"
      continue
    fi

    # Skip hosts with no SSH target
    if [[ -z "$ssh_target" ]]; then
      echo "| $host | — | — | no sshTarget |"
      continue
    fi

    # Try SSH with Tailscale → fallback
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

# --- Agent health: check key systemd services for each agent ---
gather_agent_health() {
  local hosts_nix="$1"

  # Check if agentctl is available
  if ! command -v agentctl >/dev/null 2>&1; then
    echo "### Agent status"
    echo "_agentctl not available on this host_"
    return 0
  fi

  # Get known agents from agentctl help output
  local known_agents
  known_agents=$(agentctl 2>&1 | grep "Known agents:" | sed 's/.*Known agents: //' || true)
  if [[ -z "$known_agents" ]]; then
    echo "### Agent status"
    echo "_No agents configured_"
    return 0
  fi

  echo "### Agent status"
  echo "| Agent | Task Loop | Notes Sync | SSH Agent | Status |"
  echo "|-------|-----------|------------|-----------|--------|"

  for agent in $known_agents; do
    local task_loop notes_sync ssh_agent overall

    # Check key services via agentctl (handles remote dispatch automatically)
    task_loop=$(agentctl "$agent" is-active "agent-${agent}-task-loop.timer" 2>/dev/null || echo "unknown")
    notes_sync=$(agentctl "$agent" is-active "agent-${agent}-notes-sync.timer" 2>/dev/null || echo "unknown")
    ssh_agent=$(agentctl "$agent" is-active "agent-${agent}-ssh-agent.service" 2>/dev/null || echo "unknown")

    # Determine overall status
    if [[ "$task_loop" == "active" && "$notes_sync" == "active" && "$ssh_agent" == "active" ]]; then
      overall="ok"
    elif [[ "$task_loop" == "unknown" && "$notes_sync" == "unknown" ]]; then
      overall="unreachable"
    else
      overall="degraded"
    fi

    echo "| $agent | $task_loop | $notes_sync | $ssh_agent | $overall |"
  done
}

# --- Agent task queue: count tasks by status ---
gather_agent_tasks() {
  # Check if agentctl is available
  if ! command -v agentctl >/dev/null 2>&1; then
    return 0
  fi

  local known_agents
  known_agents=$(agentctl 2>&1 | grep "Known agents:" | sed 's/.*Known agents: //' || true)
  [[ -z "$known_agents" ]] && return 0

  echo "### Agent tasks"
  echo "| Agent | Pending | In Progress | Blocked | Completed |"
  echo "|-------|---------|-------------|---------|-----------|"

  for agent in $known_agents; do
    local tasks_yaml pending in_progress blocked completed
    tasks_yaml=$(agentctl "$agent" exec cat "/home/agent-${agent}/notes/TASKS.yaml" 2>/dev/null || true)

    if [[ -z "$tasks_yaml" ]]; then
      echo "| $agent | — | — | — | — |"
      continue
    fi

    pending=$(echo "$tasks_yaml" | grep -c 'status: pending' 2>/dev/null || echo "0")
    in_progress=$(echo "$tasks_yaml" | grep -c 'status: in_progress' 2>/dev/null || echo "0")
    blocked=$(echo "$tasks_yaml" | grep -c 'status: blocked' 2>/dev/null || echo "0")
    completed=$(echo "$tasks_yaml" | grep -c 'status: completed' 2>/dev/null || echo "0")

    echo "| $agent | $pending | $in_progress | $blocked | $completed |"
  done
}

# --- Gather current system state (for ks doctor) ---
gather_system_state() {
  local repo_root="$1"
  local hosts_nix="$2"
  local current_host="${3:-}"

  echo "## System State"
  echo ""

  # NixOS generation
  local gen=""
  if command -v nixos-version >/dev/null 2>&1; then
    gen=$(nixos-version 2>/dev/null || true)
  fi
  [[ -n "$gen" ]] && echo "**NixOS generation**: $gen"
  echo ""

  # Systemd failed units
  echo "### Failed systemd units"
  local failed=""
  if command -v systemctl >/dev/null 2>&1; then
    failed=$(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}' || true)
  fi
  if [[ -z "$failed" ]]; then
    echo "_None_"
  else
    while IFS= read -r unit; do
      echo "- $unit"
    done <<< "$failed"
  fi
  echo ""

  # Disk usage
  echo "### Disk usage"
  echo '```'
  df -h 2>/dev/null | head -20 || echo "_unavailable_"
  echo '```'
  echo ""

  # Flake lock age
  echo "### flake.lock age"
  if [[ -f "$repo_root/flake.lock" ]]; then
    local lock_age
    lock_age=$(git -C "$repo_root" log -1 --format="%ar" -- flake.lock 2>/dev/null || true)
    if [[ -n "$lock_age" ]]; then
      echo "_Last updated: ${lock_age}_"
    else
      echo "_unknown_"
    fi
  else
    echo "_flake.lock not found_"
  fi
  echo ""

  # Ollama diagnostics
  gather_ollama_diagnostics "$repo_root" "$current_host"
  echo ""

  # Fleet health (host reachability + generation comparison)
  if [[ -n "$hosts_nix" && -f "$hosts_nix" ]]; then
    gather_fleet_health "$hosts_nix" "$gen"
    echo ""
  fi

  # Agent health (service status)
  gather_agent_health "$hosts_nix"
  echo ""

  # Agent task queue
  gather_agent_tasks
}

gather_ollama_diagnostics() {
  local repo_root="$1"
  local current_host="$2"

  echo "### Ollama diagnostics"

  if [[ -z "$current_host" ]]; then
    echo "_Current host is not defined in hosts.nix; skipping config evaluation_"
    return
  fi

  local user
  user=$(resolve_current_hm_user "$repo_root" "$current_host")
  if [[ -z "$user" ]]; then
    echo "_No home-manager user found for current host_"
    return
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

  local agent_users_json
  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"
  agent_users_json=$(timeout 60 nix eval \
    "$repo_root#nixosConfigurations.${current_host}.config.home-manager.users" \
    --apply 'builtins.attrNames' --json \
    "${override_args[@]}" 2>/dev/null || echo "[]")
  local agent_users
  agent_users=$(echo "$agent_users_json" | jq -r '.[] | select(startswith("agent-"))')

  if [[ -z "$agent_users" ]]; then
    echo "- Agent local config: _no agent home-manager users found_"
    return
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

# --- Build shared agent system prompt (REQ-014.2-8) ---
# Usage: build_agent_prompt repo_root hosts_nix ks_repo current_host
build_agent_prompt() {
  local repo_root="$1"
  local hosts_nix="$2"
  local ks_repo="$3"
  local current_host="$4"

  local prompt=""

  # 1. Conventions from keystone repo (REQ-014.8, REQ-014.14, REQ-014.16)
  if [[ -n "$ks_repo" ]]; then
    local conventions
    conventions=$(load_conventions "$ks_repo")
    if [[ -n "$conventions" ]]; then
      prompt="$conventions"
    fi

    # Load ks-agent archetype (provides identity and constraints for ks agent sessions)
    local archetype_file="$ks_repo/modules/os/agents/archetypes/ks-agent.md"
    if [[ -f "$archetype_file" ]]; then
      if [[ -n "$prompt" ]]; then
        prompt="$prompt

---

$(cat "$archetype_file")"
      else
        prompt="$(cat "$archetype_file")"
      fi
    fi
  fi

  # 2. ks update workflow (REQ-014.5)
  local workflow
  workflow=$(ks_update_workflow_docs)
  if [[ -n "$prompt" ]]; then
    prompt="$prompt

---

$workflow"
  else
    prompt="$workflow"
  fi

  # 3. Local flake override docs (REQ-014.7)
  local override_docs
  override_docs=$(local_flake_override_docs)
  prompt="$prompt

---

$override_docs"

  # 4. Current host identity (REQ-014.4)
  local current_hostname
  current_hostname=$(hostname)
  local nixos_gen=""
  if command -v nixos-version >/dev/null 2>&1; then
    nixos_gen=$(nixos-version 2>/dev/null || true)
  fi
  local host_section
  host_section="## Current Host

- **Hostname**: $current_hostname"
  [[ -n "$nixos_gen" ]] && host_section="$host_section
- **NixOS generation**: $nixos_gen"
  prompt="$prompt

---

$host_section"

  # 5. Host table (REQ-014.2, REQ-014.17-19)
  local host_table
  host_table=$(build_host_table "$hosts_nix")
  if [[ -n "$host_table" ]]; then
    prompt="$prompt

## Hosts

$host_table"
  fi

  # 6. Users/agents table (REQ-014.3) — best-effort, skipped on cold cache timeout
  local user_table
  user_table=$(build_user_table "$repo_root" "$current_host")
  if [[ -n "$user_table" ]]; then
    prompt="$prompt

## Users & Agents

$user_table"
  fi

  # 7. Dev mode status (REQ-016.11-13)
  local ks_dev_path
  ks_dev_path=$(find_local_repo "$repo_root" "ncrmro/keystone")
  if [[ -n "$ks_dev_path" ]]; then
    local ks_branch ks_dirty=""
    ks_branch=$(git -C "$ks_dev_path" branch --show-current 2>/dev/null || echo "unknown")
    if ! git -C "$ks_dev_path" diff --quiet 2>/dev/null || ! git -C "$ks_dev_path" diff --cached --quiet 2>/dev/null; then
      ks_dirty=" (has uncommitted changes)"
    fi
    prompt="$prompt

---

## Development Mode

**Status**: Active — using local keystone from disk${ks_dirty}
**Path**: $ks_dev_path
**Branch**: $ks_branch

### Dev Mode Conventions

- \`ks build\` / \`ks update --dev\`: Rebuilds **home-manager profiles only** (users + agents). \`ks update --dev\` also clones or pulls managed repos first so local overrides like DeepWork library jobs appear automatically. Fast iteration, no sudo required.
- \`ks build --lock\` / \`ks update\` (default): **Full NixOS system rebuild**. Pushes keystone (forks if not a collaborator), locks flake inputs, builds, pushes nixos-config, deploys.
- Changes to keystone are NOT locked into flake.lock until \`--lock\` is used.
- When ready to lock: commit + push keystone, then run \`ks update\` (or \`ks build --lock\`)."
  fi

  printf '%s' "$prompt"
}

# --- Launch AI agent with system prompt ---
# Writes prompt to a checksummed temp file and passes it via @file
# reference in --append-system-prompt. This avoids Linux MAX_ARG_STRLEN
# (128KB per argument) — the argv only contains the small @path string,
# while claude reads the full prompt from disk.
# Usage: launch_agent local_model prompt [passthrough args...]
launch_agent() {
  local local_model="$1"; shift
  local repo_root="$1"; shift
  local current_host="$1"; shift
  local prompt="$1"; shift

  local prompt_file
  prompt_file="/tmp/ks-prompt-$(printf '%s' "$prompt" | md5sum | cut -d' ' -f1).md"
  printf '%s' "$prompt" > "$prompt_file"

  if [[ -n "$local_model" ]]; then
    if [[ -z "$current_host" ]]; then
      echo "Error: could not resolve the current host in hosts.nix, so --local cannot load home-manager Ollama settings." >&2
      exit 1
    fi
    local hm_user ollama_host default_model resolved_model
    hm_user=$(resolve_current_hm_user "$repo_root" "$current_host")
    require_ollama_enabled "$repo_root" "$current_host" "$hm_user"
    ollama_host=$(resolve_ollama_host "$repo_root" "$current_host" "$hm_user")
    default_model=$(resolve_ollama_default_model "$repo_root" "$current_host" "$hm_user")
    resolved_model=$(resolve_local_model "$local_model" "$default_model")

    if ! command -v ollama >/dev/null 2>&1; then
      echo "Error: --local requires ollama to be installed." >&2
      exit 1
    fi
    if ! command -v claude >/dev/null 2>&1; then
      echo "Error: --local requires claude to be installed." >&2
      exit 1
    fi

    ANTHROPIC_BASE_URL="$ollama_host" \
    ANTHROPIC_AUTH_TOKEN="ollama" \
      exec claude --model "$resolved_model" --append-system-prompt "@${prompt_file}" "$@"
  elif command -v claude >/dev/null 2>&1; then
    exec claude --append-system-prompt "@${prompt_file}" "$@"
  else
    echo "Error: claude is not available." >&2
    exit 1
  fi
}

cmd_agent() {
  local local_model=""
  local passthrough_args=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_agent_help
        return 0
        ;;
      --local)
        shift
        if [[ $# -gt 0 && "${1:0:1}" != "-" ]]; then
          local_model="$1"; shift
        else
          local_model="default"
        fi
        ;;
      *) passthrough_args+=("$1"); shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"
  local ks_repo
  ks_repo=$(find_keystone_repo "$repo_root")

  # Resolve current host key in hosts.nix for user table eval (REQ-014.3)
  local current_hostname current_host=""
  current_hostname=$(hostname)
  current_host=$(nix eval -f "$hosts_nix" --raw \
    --apply "hosts: let m = builtins.filter (k: (builtins.getAttr k hosts).hostname == \"$current_hostname\") (builtins.attrNames hosts); in if m == [] then \"\" else builtins.head m" \
    2>/dev/null) || current_host=""

  local prompt
  prompt=$(build_agent_prompt "$repo_root" "$hosts_nix" "$ks_repo" "$current_host")

  launch_agent "$local_model" "$repo_root" "$current_host" "$prompt" "${passthrough_args[@]+"${passthrough_args[@]}"}"
}

cmd_doctor() {
  local local_model=""
  local passthrough_args=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_doctor_help
        return 0
        ;;
      --local)
        shift
        if [[ $# -gt 0 && "${1:0:1}" != "-" ]]; then
          local_model="$1"; shift
        else
          local_model="default"
        fi
        ;;
      *) passthrough_args+=("$1"); shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"
  local ks_repo
  ks_repo=$(find_keystone_repo "$repo_root")

  local current_hostname current_host=""
  current_hostname=$(hostname)
  current_host=$(nix eval -f "$hosts_nix" --raw \
    --apply "hosts: let m = builtins.filter (k: (builtins.getAttr k hosts).hostname == \"$current_hostname\") (builtins.attrNames hosts); in if m == [] then \"\" else builtins.head m" \
    2>/dev/null) || current_host=""

  # Build shared context (REQ-014.10 — same agent as ks agent)
  local base_prompt
  base_prompt=$(build_agent_prompt "$repo_root" "$hosts_nix" "$ks_repo" "$current_host")

  # Gather current system state including fleet + agent health (REQ-014.11)
  local system_state
  system_state=$(gather_system_state "$repo_root" "$hosts_nix" "$current_host")

  # Diagnostic-focused prefix (REQ-014.10)
  local doctor_prefix
  doctor_prefix="You are a diagnostic agent for a keystone NixOS infrastructure system.
Your primary goal is to check host health, agent health, and suggest actionable fixes.

Focus areas:
- Failed or degraded systemd units (check with: systemctl --failed)
- Disk pressure (check with: df -h)
- Stale flake locks (run ks update to refresh)
- Unreachable hosts (check sshTarget connectivity via ssh)
- NixOS generation drift between hosts (compare fleet status table)
- Agent service health (task-loop, notes-sync, ssh-agent timers/services)
- Agent task queue (blocked tasks need human intervention, stale pending tasks may indicate stalls)
- Agent SSH key health (verify with: agentctl <name> exec ssh-add -l)
- Agent mail connectivity (verify with: agentctl <name> exec himalaya account list)

Always suggest concrete remediation commands. Prefer ks/agentctl commands over raw nix/systemctl."

  local prompt
  prompt="$doctor_prefix

---

$system_state

---

$base_prompt"

  launch_agent "$local_model" "$repo_root" "$current_host" "$prompt" "${passthrough_args[@]+"${passthrough_args[@]}"}"
}

# --- Main dispatch ---
if [[ $# -lt 1 ]]; then
  print_main_help >&2
  exit 1
fi

CMD="$1"; shift
case "$CMD" in
  -h|--help)
    print_main_help
    ;;
  help)
    show_help_topic "$@"
    ;;
  build)  cmd_build "$@" ;;
  grafana) cmd_grafana "$@" ;;
  update) cmd_update "$@" ;;
  switch) cmd_switch "$@" ;;
  sync-host-keys) cmd_sync_host_keys "$@" ;;
  agent)  cmd_agent "$@" ;;
  doctor) cmd_doctor "$@" ;;
  *)
    echo "Error: Unknown command '$CMD'" >&2
    echo "Known commands: help, build, grafana, update, switch, sync-host-keys, agent, doctor" >&2
    exit 1
    ;;
esac
