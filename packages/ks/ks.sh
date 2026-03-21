#!/usr/bin/env bash
# ks — Keystone infrastructure CLI
#
# Usage: ks <command> [options]
#
# Commands:
#   build  [--lock] [HOSTS]                            Build home-manager profiles (or full system with --lock)
#   update [--dev] [--boot] [--pull] [--lock] [HOSTS]  Deploy (home-manager only with --dev, full system default)
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
#   3. ~/nixos-config as fallback
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
  if [[ -f "$HOME/nixos-config/hosts.nix" ]]; then
    readlink -f "$HOME/nixos-config"
    return
  fi
  echo "Error: Cannot find nixos-config repo." >&2
  echo "Set NIXOS_CONFIG_DIR or run from within the repo." >&2
  exit 1
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

  if [[ -d "$repo_root/.repos/keystone" ]]; then
    args+=(--override-input keystone "path:$repo_root/.repos/keystone")
  elif [[ -d "$repo_root/.submodules/keystone" ]]; then
    args+=(--override-input keystone "path:$repo_root/.submodules/keystone")
  fi

  if [[ -d "$repo_root/.repos/agenix-secrets" ]]; then
    args+=(--override-input agenix-secrets "path:$repo_root/.repos/agenix-secrets")
  elif [[ -d "$repo_root/agenix-secrets" ]]; then
    args+=(--override-input agenix-secrets "path:$repo_root/agenix-secrets")
  fi

  echo "${args[@]}"   # empty string if no repos found — no error, no exit
}

# --- Repo URLs (for cloning) ---
KEYSTONE_URL="git@github.com:ncrmro/keystone.git"
AGENIX_SECRETS_URL="ssh://forgejo@git.ncrmro.com:2222/ncrmro/agenix-secrets.git"

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
    git -C "$ks_path" push || {
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
      git -C "$ks_path" push
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
      git -C "$ks_path" push -u origin "$(git -C "$ks_path" branch --show-current)"
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

# --- Build home-manager activation packages only (REQ-016.1-3) ---
# Builds home-manager activationPackage for each user on each host, returning
# a newline-delimited list of "host:user:store-path" entries.
build_home_manager_only() {
  local repo_root="$1"
  shift
  local target_hosts=("$@")

  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  local build_targets=()
  local target_map=()   # host:user pairs

  for h in "${target_hosts[@]}"; do
    local users
    users=$(list_hm_users "$repo_root" "$h") || continue
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
  nix build --no-link "${build_targets[@]}" "${override_args[@]}"
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
    users=$(list_hm_users "$repo_root" "$host") || continue
    [[ -z "$users" ]] && continue

    local host_json host_hostname ssh_target fallback_ip
    host_json=$(nix eval -f "$hosts_nix" "$host" --json 2>/dev/null) || continue
    host_hostname=$(echo "$host_json" | jq -r '.hostname')
    ssh_target=$(echo "$host_json" | jq -r '.sshTarget // empty')
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')

    while IFS= read -r user; do
      # Resolve the activation package store path
      local activation_path
      activation_path=$(nix build --no-link --print-out-paths \
        "$repo_root#nixosConfigurations.$host.config.home-manager.users.\"$user\".home.activationPackage" \
        "${override_args[@]}" 2>/dev/null) || {
        echo "Error: Failed to resolve activation package for $user on $host" >&2
        continue
      }

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
# Returns the local path for a given repo name, checking .repos/ first, then legacy paths.
find_local_repo() {
  local repo_root="$1" name="$2"
  case "$name" in
    keystone)
      if [[ -d "$repo_root/.repos/keystone" ]]; then
        echo "$repo_root/.repos/keystone"
      elif [[ -d "$repo_root/.submodules/keystone" ]]; then
        echo "$repo_root/.submodules/keystone"
      fi
      ;;
    agenix-secrets)
      if [[ -d "$repo_root/.repos/agenix-secrets" ]]; then
        echo "$repo_root/.repos/agenix-secrets"
      elif [[ -d "$repo_root/agenix-secrets" ]]; then
        echo "$repo_root/agenix-secrets"
      fi
      ;;
  esac
}

# --- Pull (clone or update) a repo ---
pull_repo() {
  local repo_root="$1" name="$2" url="$3"
  local target="$repo_root/.repos/$name"

  # Check legacy paths first — if found there, pull in-place
  local existing
  existing=$(find_local_repo "$repo_root" "$name")
  if [[ -n "$existing" ]]; then
    target="$existing"
  fi

  if [[ -e "$target/.git" ]]; then
    # Detect detached HEAD and recover by switching to the default branch before pulling
    if ! git -C "$target" symbolic-ref HEAD >/dev/null 2>&1; then
      local default_branch
      default_branch=$(git -C "$target" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
      default_branch="${default_branch:-main}"
      echo "Warning: $name is in detached HEAD state, switching to $default_branch..." >&2
      git -C "$target" checkout "$default_branch" || {
        echo "Error: failed to checkout $default_branch in $name" >&2
        return 1
      }
    fi
    echo "Pulling $name..."
    git -C "$target" pull --ff-only
  else
    echo "Cloning $name..."
    mkdir -p "$(dirname "$target")"
    git clone "$url" "$target"
  fi
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
      --dev) shift ;;  # kept for backwards compat, no-op
      --lock) lock=true; shift ;;
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
    local ks_path secrets_path
    ks_path=$(find_local_repo "$repo_root" keystone)
    secrets_path=$(find_local_repo "$repo_root" agenix-secrets)

    # Step 1: Verify repos are clean
    [[ -n "$ks_path" ]] && verify_repo_clean "$ks_path" keystone
    [[ -n "$secrets_path" ]] && verify_repo_clean "$secrets_path" agenix-secrets

    # Step 2: Push keystone with fork fallback (REQ-016.9)
    [[ -n "$ks_path" ]] && push_keystone_with_fork_fallback "$ks_path"

    # Step 3: Lock flake inputs
    echo "Locking flake inputs..."
    nix flake update keystone agenix-secrets --flake "$repo_root"

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

cmd_update() {
  local mode="switch" hosts_arg="" pull=false lock=true
  while [[ $# -gt 0 ]]; do
    case $1 in
      --dev) lock=false; shift ;;
      --boot) mode="boot"; shift ;;
      --pull) pull=true; shift ;;
      --lock) lock=true; shift ;;
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

  # --- Handle --pull (standalone, no lock) ---
  if [[ "$pull" == true && "$lock" != true ]]; then
    pull_repo "$repo_root" keystone "$KEYSTONE_URL"
    pull_repo "$repo_root" agenix-secrets "$AGENIX_SECRETS_URL"
    echo "Pull complete."
    return
  fi

  # ── DEV MODE: home-manager only (REQ-016.2) ──────────────────────────────────
  if [[ "$lock" != true ]]; then
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
  git -C "$repo_root" pull --ff-only

  # Step 2: Pull keystone + agenix-secrets
  pull_repo "$repo_root" keystone "$KEYSTONE_URL"
  pull_repo "$repo_root" agenix-secrets "$AGENIX_SECRETS_URL"

  # Step 3: Verify repos are clean and fully pushed before locking
  local ks_path secrets_path
  ks_path=$(find_local_repo "$repo_root" keystone)
  secrets_path=$(find_local_repo "$repo_root" agenix-secrets)
  [[ -n "$ks_path" ]] && verify_repo_clean "$ks_path" keystone
  [[ -n "$secrets_path" ]] && verify_repo_clean "$secrets_path" agenix-secrets

  # Step 3.5: Push keystone with fork fallback (REQ-016.8-9)
  [[ -n "$ks_path" ]] && push_keystone_with_fork_fallback "$ks_path"

  # Step 4: Update flake.lock BEFORE building so the build validates what will be committed
  echo "Locking flake inputs..."
  nix flake update keystone agenix-secrets --flake "$repo_root"

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
  nix build --no-link "${build_targets[@]}" "${override_args[@]}"

  # ── POST-BUILD PHASE ────────────────────────────────────────────────────────
  # Step 8: Push flake.lock only after a successful build
  echo "Pushing nixos-config..."
  if ! git -C "$repo_root" pull --rebase origin "$(git -C "$repo_root" branch --show-current)" 2>&1; then
    echo ""
    echo "ERROR: Failed to rebase nixos-config against origin."
    echo "Resolve conflicts manually, then run: git push"
    exit 1
  fi
  if ! git -C "$repo_root" push 2>&1; then
    echo ""
    echo "ERROR: Failed to push nixos-config."
    echo "Run 'git pull --rebase && git push' to retry."
    exit 1
  fi

  # ── DEPLOY PHASE ────────────────────────────────────────────────────────────
  # Step 9: Sequential deployment — risky hosts should be placed last in the list.
  for host in "${target_hosts[@]}"; do
    local host_json ssh_target fallback_ip build_on_remote host_hostname
    host_json=$(nix eval -f "$hosts_nix" "$host" --json)
    ssh_target=$(echo "$host_json" | jq -r '.sshTarget // empty')
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')
    build_on_remote=$(echo "$host_json" | jq -r '.buildOnRemote')
    host_hostname=$(echo "$host_json" | jq -r '.hostname')

    if [[ "$host_hostname" == "$current_hostname" ]]; then
      # LOCAL deploy
      echo "Deploying $host locally ($mode)..."
      sudo nixos-rebuild "$mode" --flake "$repo_root#$host" "${override_args[@]}"
    else
      # REMOTE deploy
      if [[ -z "$ssh_target" ]]; then
        echo "Error: $host has no sshTarget (local-only host). Cannot deploy remotely." >&2
        exit 1
      fi

      local resolved="$ssh_target"
      if [[ -n "$fallback_ip" ]]; then
        if ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${ssh_target}" true 2>/dev/null; then
          echo "Using Tailscale: $ssh_target"
        else
          resolved="$fallback_ip"
          echo "Tailscale unavailable, using LAN: $fallback_ip"
        fi
      fi

      local remote_args=(--target-host "root@$resolved")
      if [[ "$build_on_remote" == "true" ]]; then
        remote_args+=(--build-host "root@$resolved")
      fi

      echo "Deploying $host to root@$resolved ($mode)..."
      nixos-rebuild "$mode" --flake "$repo_root#$host" "${remote_args[@]}" "${override_args[@]}"
    fi

    [[ "$mode" == "boot" ]] && echo "Reboot required to apply changes for $host."
    echo "Update complete for $host"
  done
}

# --- Find keystone repo (where conventions/ lives) ---
# Returns the path to the local keystone repo clone, or empty string if not found.
find_keystone_repo() {
  local repo_root="$1"
  local ks_path
  ks_path=$(find_local_repo "$repo_root" keystone)
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
# NOTE: ks update requires sudo. Agents MUST NOT run it directly.
# This documentation is injected as reference knowledge so the agent can
# explain the workflow to humans or understand the deploy pipeline.
ks_update_workflow_docs() {
  cat <<'WFDOC'
## ks update Workflow (Reference Only — requires sudo, human-only)

> **WARNING**: `ks update` calls `sudo nixos-rebuild switch`. Agents MUST NOT
> run this command. Use `ks build` to test changes, then ask a human to deploy.

`ks update [--dev] [--boot] [--pull] [--lock] [HOSTS]`

Steps executed in order:

1. **Pull** nixos-config (`git pull --ff-only`)
2. **Pull** keystone and agenix-secrets repos (clone if absent)
3. **Verify** keystone and agenix-secrets are clean and fully pushed
4. **Lock** flake inputs (`nix flake update keystone agenix-secrets`)
5. **Commit** flake.lock if changed (`git commit flake.lock -m "chore: relock ..."`)
6. **Build** all target hosts in a single `nix build` invocation (Nix parallelises internally)
7. **Push** nixos-config (rebase + push)
8. **Deploy** hosts sequentially: local hosts via `sudo nixos-rebuild switch`,
   remote hosts via `nixos-rebuild switch --target-host root@<sshTarget>`

### Flags

| Flag | Effect |
|------|--------|
| `--dev` | Home-manager only: build + activate user/agent profiles, skip system rebuild |
| `--boot` | Use `nixos-rebuild boot` instead of `switch` (reboot required to apply) |
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

`ks` auto-detects local keystone and agenix-secrets clones and passes
`--override-input` flags to every `nix build` / `nixos-rebuild` call —
no manual flags needed.

### Detected Paths (in order)

| Input | Paths checked |
|-------|---------------|
| keystone | `<repo>/.repos/keystone`, `<repo>/.submodules/keystone` |
| agenix-secrets | `<repo>/.repos/agenix-secrets`, `<repo>/agenix-secrets/` |

### Equivalent Manual Command

```bash
nix build .#nixosConfigurations.HOSTNAME.config.system.build.toplevel \
  --override-input keystone path:$(pwd)/.repos/keystone \
  --no-link
```

### Workflow for Keystone Changes

1. Edit files in `.repos/keystone/` (or `.submodules/keystone/`)
2. Test with `ks build --dev` (builds with local overrides, no deploy)
3. Once satisfied, commit + push keystone
4. Ask a human to run `ks update` (requires sudo) for deployment
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
  ks_dev_path=$(find_local_repo "$repo_root" keystone)
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

- \`ks build\` / \`ks update --dev\`: Rebuilds **home-manager profiles only** (users + agents). Fast iteration, no sudo required.
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
  local prompt="$1"; shift

  local prompt_file
  prompt_file="/tmp/ks-prompt-$(printf '%s' "$prompt" | md5sum | cut -d' ' -f1).md"
  printf '%s' "$prompt" > "$prompt_file"

  if [[ -n "$local_model" ]]; then
    local model_arg="$local_model"
    [[ "$model_arg" == "default" ]] && model_arg=""
    if command -v ollama >/dev/null 2>&1; then
      exec ollama run ${model_arg:+"$model_arg"} --system "$(cat "$prompt_file")" "$@"
    else
      echo "Error: --local requires ollama to be installed." >&2
      exit 1
    fi
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

  launch_agent "$local_model" "$prompt" "${passthrough_args[@]+"${passthrough_args[@]}"}"
}

cmd_doctor() {
  local local_model=""
  local passthrough_args=()

  while [[ $# -gt 0 ]]; do
    case $1 in
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
  system_state=$(gather_system_state "$repo_root" "$hosts_nix")

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

  launch_agent "$local_model" "$prompt" "${passthrough_args[@]+"${passthrough_args[@]}"}"
}

# --- Main dispatch ---
if [[ $# -lt 1 ]]; then
  echo "Usage: ks <command> [options]" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  build  [--lock] [HOSTS]                            Build (home-manager only; --lock for full system)" >&2
  echo "  update [--dev] [--boot] [--pull] [--lock] [HOSTS]  Deploy (--dev for home-manager only)" >&2
  echo "  sync-host-keys                                   Populate hostPublicKey in hosts.nix from live hosts" >&2
  echo "  agent  [--local [MODEL]] [args...]               Launch AI agent with keystone OS context" >&2
  echo "  doctor [--local [MODEL]] [args...]               Launch diagnostic AI agent with system state" >&2
  echo "" >&2
  echo "HOSTS: Comma-separated list of host names (e.g. host1,host2). Defaults to current host." >&2
  echo "Note: Risky hosts should be placed last (e.g. workstation,ocean)." >&2
  echo "" >&2
  echo "Repo discovery: \$NIXOS_CONFIG_DIR > git root > ~/nixos-config" >&2
  exit 1
fi

CMD="$1"; shift
case "$CMD" in
  build)  cmd_build "$@" ;;
  update) cmd_update "$@" ;;
  sync-host-keys) cmd_sync_host_keys "$@" ;;
  agent)  cmd_agent "$@" ;;
  doctor) cmd_doctor "$@" ;;
  *)
    echo "Error: Unknown command '$CMD'" >&2
    echo "Known commands: build, update, sync-host-keys, agent, doctor" >&2
    exit 1
    ;;
esac
