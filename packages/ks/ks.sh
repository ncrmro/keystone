#!/usr/bin/env bash
# ks — Keystone infrastructure CLI
#
# Usage: ks <command> [options]
#
# Commands:
#   build  [--dev] [HOSTS]                      Build a NixOS configuration (no deploy)
#   update [--dev] [--boot] [--pull] [--lock] [HOSTS]  Deploy a NixOS configuration
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

# --- Build --dev override args ---
dev_override_args() {
  local repo_root="$1"
  local keystone_path=""
  local secrets_path=""

  # Keystone: prefer .repos/keystone, fallback to .submodules/keystone
  if [[ -d "$repo_root/.repos/keystone" ]]; then
    keystone_path="$repo_root/.repos/keystone"
  elif [[ -d "$repo_root/.submodules/keystone" ]]; then
    keystone_path="$repo_root/.submodules/keystone"
  else
    echo "Error: Cannot find keystone repo at .repos/keystone or .submodules/keystone" >&2
    exit 1
  fi

  # Secrets: prefer .repos/agenix-secrets, fallback to agenix-secrets/
  if [[ -d "$repo_root/.repos/agenix-secrets" ]]; then
    secrets_path="$repo_root/.repos/agenix-secrets"
  elif [[ -d "$repo_root/agenix-secrets" ]]; then
    secrets_path="$repo_root/agenix-secrets"
  else
    echo "Error: Cannot find agenix-secrets repo at .repos/agenix-secrets or agenix-secrets/" >&2
    exit 1
  fi

  echo "--override-input keystone path:$keystone_path --override-input agenix-secrets path:$secrets_path"
}

# --- Repo URLs (for cloning) ---
KEYSTONE_URL="git@github.com:ncrmro/keystone.git"
AGENIX_SECRETS_URL="ssh://forgejo@git.ncrmro.com:2222/ncrmro/agenix-secrets.git"

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

cmd_build() {
  local dev=false hosts_arg=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --dev) dev=true; shift ;;
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

  local override_args=()
  if [[ "$dev" == true ]]; then
    read -ra override_args <<< "$(dev_override_args "$repo_root")"
    echo "Dev mode: using local keystone + agenix-secrets"
  fi

  local build_targets=()
  for h in "${target_hosts[@]}"; do
    build_targets+=("$repo_root#nixosConfigurations.$h.config.system.build.toplevel")
  done

  echo "Building: ${target_hosts[*]}..."
  nix build "${build_targets[@]}" "${override_args[@]}"
  echo "Build complete for: ${target_hosts[*]}"
}

cmd_update() {
  local dev=false mode="switch" hosts_arg="" pull=false lock=true
  while [[ $# -gt 0 ]]; do
    case $1 in
      --dev) dev=true; lock=false; shift ;;
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

  # --- Handle --pull ---
  if [[ "$pull" == true ]]; then
    pull_repo "$repo_root" keystone "$KEYSTONE_URL"
    pull_repo "$repo_root" agenix-secrets "$AGENIX_SECRETS_URL"
    if [[ "$lock" != true ]]; then
      echo "Pull complete."
      return
    fi
  fi

  # --- Handle locking/clean checks ---
  if [[ "$lock" == true ]]; then
    # Pull if not already done
    if [[ "$pull" != true ]]; then
      pull_repo "$repo_root" keystone "$KEYSTONE_URL"
      pull_repo "$repo_root" agenix-secrets "$AGENIX_SECRETS_URL"
    fi

    # Verify repos are clean
    local ks_path secrets_path
    ks_path=$(find_local_repo "$repo_root" keystone)
    secrets_path=$(find_local_repo "$repo_root" agenix-secrets)
    [[ -n "$ks_path" ]] && verify_repo_clean "$ks_path" keystone
    [[ -n "$secrets_path" ]] && verify_repo_clean "$secrets_path" agenix-secrets
  fi

  local override_args=()
  if [[ "$dev" == true ]]; then
    read -ra override_args <<< "$(dev_override_args "$repo_root")"
    echo "Dev mode: using local keystone + agenix-secrets"
  fi

  # --- Verify all hosts with local builds ---
  local build_targets=()
  for h in "${target_hosts[@]}"; do
    build_targets+=("$repo_root#nixosConfigurations.$h.config.system.build.toplevel")
  done
  
  echo "Verifying builds for: ${target_hosts[*]}..."
  nix build "${build_targets[@]}" "${override_args[@]}"

  # --- Locking and Pushing ---
  if [[ "$lock" == true ]]; then
    # Lock flake inputs
    echo "Locking flake inputs..."
    nix flake update keystone agenix-secrets --flake "$repo_root"

    # Commit flake.lock
    if ! git -C "$repo_root" diff --quiet flake.lock; then
      echo "Committing flake.lock..."
      git -C "$repo_root" add flake.lock
      git -C "$repo_root" commit -m "chore: relock keystone + agenix-secrets"
    fi

    # Pull/rebase nixos-config before pushing to handle concurrent commits
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
  fi

  # --- Sequential Deployment ---
  # Note: Risky hosts should be placed last in the list.
  for host in "${target_hosts[@]}"; do
    # Read host config
    local host_json ssh_target fallback_ip build_on_remote host_hostname
    host_json=$(nix eval -f "$hosts_nix" "$host" --json)
    ssh_target=$(echo "$host_json" | jq -r '.sshTarget // empty')
    fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')
    build_on_remote=$(echo "$host_json" | jq -r '.buildOnRemote')
    host_hostname=$(echo "$host_json" | jq -r '.hostname')

    local current_hostname
    current_hostname=$(hostname)
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

# --- Main dispatch ---
if [[ $# -lt 1 ]]; then
  echo "Usage: ks <command> [options]" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  build  [--dev] [HOSTS]                      Build NixOS configurations" >&2
  echo "  update [--dev] [--boot] [--pull] [--lock] [HOSTS]  Deploy NixOS configurations" >&2
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
  *)
    echo "Error: Unknown command '$CMD'" >&2
    echo "Known commands: build, update" >&2
    exit 1
    ;;
esac
