#!/usr/bin/env bash
# ks — Keystone infrastructure CLI
#
# Usage: ks <command> [options]
#
# Commands:
#   build  [--dev] [HOSTS]                      Build a NixOS configuration (no deploy)
#   update [--dev] [--boot] [--pull] [--lock] [HOSTS]  Deploy a NixOS configuration
#   sync-host-keys                              Populate hostPublicKey in hosts.nix from live hosts
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
#   SHOULD build all targets in a single nix invocation (nix parallelises internally).
#
# Deployment
#   MUST deploy hosts sequentially (not in parallel) to limit blast radius.
#   MUST obtain sudo credentials before the build phase when a local host is targeted,
#     so the user is not interrupted after a long build.
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

  # --dev is kept for backwards compat but is now a no-op (overrides always applied when repos exist)
  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

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

  # --- Handle --pull (standalone, no lock) ---
  if [[ "$pull" == true && "$lock" != true ]]; then
    pull_repo "$repo_root" keystone "$KEYSTONE_URL"
    pull_repo "$repo_root" agenix-secrets "$AGENIX_SECRETS_URL"
    echo "Pull complete."
    return
  fi

  # ── UPFRONT PHASE (skipped in --dev mode) ───────────────────────────────────
  if [[ "$lock" == true ]]; then
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

    # Step 4: Update flake.lock BEFORE building so the build validates what will be committed
    echo "Locking flake inputs..."
    nix flake update keystone agenix-secrets --flake "$repo_root"

    # Step 5: Commit flake.lock (if changed)
    if ! git -C "$repo_root" diff --quiet flake.lock; then
      echo "Committing flake.lock..."
      git -C "$repo_root" add flake.lock
      git -C "$repo_root" commit -m "chore: relock keystone + agenix-secrets"
    fi
  fi

  # Step 6: Cache sudo credentials upfront if any target is local
  # This avoids a sudo prompt interrupting the user after a long build.
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

  local SUDO_KEEPALIVE_PID=""
  if [[ "$needs_sudo" == true ]]; then
    echo "Caching sudo credentials (needed for local deploy)..."
    sudo -v
    # Keepalive: refresh every 60 s so a long build doesn't expire the ticket.
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap "kill $SUDO_KEEPALIVE_PID 2>/dev/null; trap - EXIT" EXIT
  fi

  # Always use local overrides when repos are present (--dev is now a no-op for builds)
  local override_args=()
  read -ra override_args <<< "$(local_override_args "$repo_root")"

  # ── BUILD PHASE ─────────────────────────────────────────────────────────────
  # Step 7: Build all targets in a single invocation (nix parallelises internally)
  local build_targets=()
  for h in "${target_hosts[@]}"; do
    build_targets+=("$repo_root#nixosConfigurations.$h.config.system.build.toplevel")
  done

  echo "Building: ${target_hosts[*]}..."
  nix build "${build_targets[@]}" "${override_args[@]}"

  # ── POST-BUILD PHASE (skipped in --dev mode) ────────────────────────────────
  # Step 8: Push flake.lock only after a successful build
  if [[ "$lock" == true ]]; then
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

# --- Main dispatch ---
if [[ $# -lt 1 ]]; then
  echo "Usage: ks <command> [options]" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  build  [--dev] [HOSTS]                      Build NixOS configurations" >&2
  echo "  update [--dev] [--boot] [--pull] [--lock] [HOSTS]  Deploy NixOS configurations" >&2
  echo "  sync-host-keys                              Populate hostPublicKey in hosts.nix from live hosts" >&2
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
  *)
    echo "Error: Unknown command '$CMD'" >&2
    echo "Known commands: build, update, sync-host-keys" >&2
    exit 1
    ;;
esac
