#!/usr/bin/env bash
# keystone-ssh-unlock — Unlock a software SSH key by adding it to ssh-agent.
#
# Uses SSH_ASKPASS for passphrase entry when running in a desktop session,
# allowing Wayland-safe GUI prompts without privilege escalation.
#
# Askpass backend: lxqt-openssh-askpass
#   - Qt-based, Wayland-native, no X11 dependency
#   - Minimal, well-maintained, and packaged in nixpkgs
#   - Preferred over ssh-askpass-fullscreen (X11-only) and ksshaskpass (KDE-heavy)
#
# Usage:
#   keystone-ssh-unlock                    # unlock with default key
#   keystone-ssh-unlock /path/to/key       # unlock a specific key

set -euo pipefail

KEY_FILE="${1:-$HOME/.ssh/id_ed25519}"

# Ensure SSH_AUTH_SOCK is available
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
  if [[ -S "${XDG_RUNTIME_DIR:-}/ssh-agent" ]]; then
    export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent"
  else
    printf "Error: SSH_AUTH_SOCK is not set and no agent socket found.\n" >&2
    printf "Start the ssh-agent service: systemctl --user start ssh-agent\n" >&2
    exit 1
  fi
fi

if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
  printf "Error: SSH_AUTH_SOCK points to a missing socket: %s\n" "$SSH_AUTH_SOCK" >&2
  printf "Start the ssh-agent service: systemctl --user start ssh-agent\n" >&2
  exit 1
fi

if [[ ! -f "$KEY_FILE" ]]; then
  printf "Error: SSH key file not found: %s\n" "$KEY_FILE" >&2
  exit 1
fi

# Check if key is already loaded
if ssh-add -l 2>/dev/null | grep -q "$KEY_FILE"; then
  printf "SSH key is already loaded: %s\n" "$KEY_FILE"
  exit 0
fi

# In a desktop session, use SSH_ASKPASS for the passphrase prompt.
# SSH_ASKPASS is set to lxqt-openssh-askpass by the desktop module's environment.
# If SSH_ASKPASS is already set (e.g. by agenix auto-load), respect that.
if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
  if [[ -z "${SSH_ASKPASS:-}" ]]; then
    # Try lxqt-openssh-askpass first (Wayland-safe, Qt-based)
    if command -v lxqt-openssh-askpass >/dev/null 2>&1; then
      export SSH_ASKPASS="lxqt-openssh-askpass"
      export SSH_ASKPASS_REQUIRE="prefer"
    fi
  fi
fi

# Add the key to the agent
if ssh-add "$KEY_FILE"; then
  printf "SSH key unlocked: %s\n" "$KEY_FILE"
else
  printf "Failed to unlock SSH key: %s\n" "$KEY_FILE" >&2
  exit 1
fi
