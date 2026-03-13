#!/usr/bin/env bash
# ks — Keystone infrastructure CLI
#
# Usage: ks <command> [options]
#
# Commands:
#   build  [--dev] [HOST]           Build a NixOS configuration (no deploy)
#   update [--dev] [--boot] [HOST]  Deploy a NixOS configuration (switch or boot)
#
# Host resolution:
#   1. If HOST is provided, use it directly
#   2. Otherwise, look up the current machine's hostname in hosts.nix
#
# Repo discovery:
#   1. $NIXOS_CONFIG_DIR if set and contains hosts.nix
#   2. Git repo root of current directory if it contains hosts.nix
#   3. ~/nixos-config as fallback
#
# The --dev flag overrides keystone and agenix-secrets flake inputs with
# local submodule paths for testing uncommitted changes.

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
  local keystone_path="$repo_root/.submodules/keystone"
  local secrets_path="$repo_root/agenix-secrets"
  [[ -d "$keystone_path" ]] || { echo "Error: Missing $keystone_path" >&2; exit 1; }
  [[ -d "$secrets_path" ]] || { echo "Error: Missing $secrets_path" >&2; exit 1; }
  echo "--override-input keystone path:$keystone_path --override-input agenix-secrets path:$secrets_path"
}

# --- Commands ---

cmd_build() {
  local dev=false host=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --dev) dev=true; shift ;;
      -*) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
      *) host="$1"; shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"
  host=$(resolve_host "$hosts_nix" "$host")

  local override_args=()
  if [[ "$dev" == true ]]; then
    read -ra override_args <<< "$(dev_override_args "$repo_root")"
    echo "Dev mode: using local keystone + agenix-secrets"
  fi

  echo "Building $host..."
  nix build "$repo_root#nixosConfigurations.$host.config.system.build.toplevel" \
    "${override_args[@]}"
  echo "Build complete for $host"
}

cmd_update() {
  local dev=false mode="switch" host=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --dev) dev=true; shift ;;
      --boot) mode="boot"; shift ;;
      -*) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
      *) host="$1"; shift ;;
    esac
  done

  local repo_root
  repo_root=$(find_repo)
  local hosts_nix="$repo_root/hosts.nix"
  host=$(resolve_host "$hosts_nix" "$host")

  # Read host config
  local host_json ssh_target fallback_ip build_on_remote host_hostname
  host_json=$(nix eval -f "$hosts_nix" "$host" --json)
  ssh_target=$(echo "$host_json" | jq -r '.sshTarget // empty')
  fallback_ip=$(echo "$host_json" | jq -r '.fallbackIP // empty')
  build_on_remote=$(echo "$host_json" | jq -r '.buildOnRemote')
  host_hostname=$(echo "$host_json" | jq -r '.hostname')

  local override_args=()
  if [[ "$dev" == true ]]; then
    read -ra override_args <<< "$(dev_override_args "$repo_root")"
    echo "Dev mode: using local keystone + agenix-secrets"
  fi

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

  [[ "$mode" == "boot" ]] && echo "Reboot required to apply changes."
  echo "Update complete for $host"
}

# --- Main dispatch ---
if [[ $# -lt 1 ]]; then
  echo "Usage: ks <command> [options]" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  build  [--dev] [HOST]           Build a NixOS configuration" >&2
  echo "  update [--dev] [--boot] [HOST]  Deploy a NixOS configuration" >&2
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
