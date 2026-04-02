#!/usr/bin/env bash
# keystone-setup-menu — Desktop setup entrypoint for Walker/Elephant.

set -euo pipefail

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

ssh_key_subtext() {
  local state
  state="$(keystone-ssh-health 2>/dev/null || true)"
  case "$state" in
    unlocked) printf "Key loaded in ssh-agent" ;;
    locked) printf "Key not loaded — unlock available" ;;
    agent-unreachable) printf "SSH agent not reachable" ;;
    *) printf "Unknown state" ;;
  esac
}

ssh_key_preview() {
  local state
  state="$(keystone-ssh-health 2>/dev/null || true)"
  printf "SSH Key Status\n\n"
  case "$state" in
    unlocked)
      printf "✓ SSH key is loaded in ssh-agent.\n\nNo action required.\n"
      ;;
    locked)
      printf "⚠ SSH key is not loaded.\n\n"
      printf "Run: keystone-ssh-unlock\n\n"
      printf "This will prompt for your SSH key passphrase and add it to the agent.\n"
      ;;
    agent-unreachable)
      printf "✗ SSH agent is not reachable.\n\n"
      printf "Run: systemctl --user start ssh-agent\n"
      printf "Then: keystone-ssh-unlock\n"
      ;;
    *)
      printf "Could not determine SSH key state.\n"
      ;;
  esac
}

entries_json() {
  local audio_menu monitor_menu hardware_menu accounts_menu printer_menu setup_menu ssh_subtext
  audio_menu=$(keystone_cmd keystone-audio-menu)
  monitor_menu=$(keystone_cmd keystone-monitor-menu)
  hardware_menu=$(keystone_cmd keystone-hardware-menu)
  accounts_menu=$(keystone_cmd keystone-accounts-menu)
  printer_menu=$(keystone_cmd keystone-printer-menu)
  setup_menu=$(keystone_cmd keystone-setup-menu)

  # Only show SSH entry when keystone-ssh-health is available (software-key hosts)
  local ssh_entries="[]"
  if command -v keystone-ssh-health >/dev/null 2>&1; then
    ssh_subtext=$(ssh_key_subtext)
    ssh_entries=$(jq -n --arg subtext "$ssh_subtext" --arg setup_menu "$setup_menu" '
      [
        {
          Text: "SSH Key",
          Subtext: $subtext,
          Value: "ssh-key",
          Preview: ($setup_menu + " preview-ssh"),
          PreviewType: "command"
        }
      ]
    ')
  fi

  jq -n --argjson ssh_entries "$ssh_entries" '
    [
      {
        Text: "Audio",
        Subtext: "Default output and input devices",
        Value: "audio",
        SubMenu: "keystone-audio",
        Preview: ($audio_menu + " summary"),
        PreviewType: "command"
      },
      {
        Text: "Monitors",
        Subtext: "Scaling, resolution, orientation, and layout",
        Value: "monitors",
        SubMenu: "keystone-monitors",
        Preview: ($monitor_menu + " preview-setup"),
        PreviewType: "command"
      },
      {
        Text: "Printer",
        Subtext: "Default CUPS printer",
        Value: "printer",
        SubMenu: "keystone-printer",
        Preview: ($printer_menu + " summary"),
        PreviewType: "command"
      },
      {
        Text: "Hardware",
        Subtext: "Secure Boot, TPM, and hardware-key disk unlock",
        Value: "hardware",
        SubMenu: "keystone-hardware",
        Preview: ($hardware_menu + " summary"),
        PreviewType: "command"
      },
      {
        Text: "Accounts",
        Subtext: "Configured mail and calendar accounts",
        Value: "accounts",
        SubMenu: "keystone-accounts",
        Preview: ($accounts_menu + " summary"),
        PreviewType: "command"
      }
    ]
    + $ssh_entries
    + [
      {
        Text: "Wifi",
        Subtext: "Controller not implemented yet",
        Value: "blocked\tWifi\tWifi setup is not implemented yet.",
        Preview: ($setup_menu + " preview-blocked " + ("Wifi" | @sh) + " " + ("Wifi setup is not implemented yet." | @sh)),
        PreviewType: "command"
      },
      {
        Text: "Bluetooth",
        Subtext: "Controller not implemented yet",
        Value: "blocked\tBluetooth\tBluetooth setup is not implemented yet.",
        Preview: ($setup_menu + " preview-blocked " + ("Bluetooth" | @sh) + " " + ("Bluetooth setup is not implemented yet." | @sh)),
        PreviewType: "command"
      }
    ]
  ' --arg audio_menu "$audio_menu" --arg monitor_menu "$monitor_menu" --arg hardware_menu "$hardware_menu" --arg accounts_menu "$accounts_menu" --arg printer_menu "$printer_menu" --arg setup_menu "$setup_menu"
}

preview_blocked() {
  local title="$1"
  local message="$2"

  printf "%s\n\n%s\n" "$title" "$message"
}

dispatch() {
  local payload="${1:-}"
  local action="" title="" message=""

  IFS=$'\t' read -r action title message <<<"$payload"

  case "$action" in
    audio | monitors | printer | hardware | accounts)
      ;;
    ssh-key)
      if command -v keystone-ssh-unlock >/dev/null 2>&1; then
        keystone-ssh-unlock
        notify "SSH Key" "SSH key unlock attempted"
      else
        notify "SSH Key" "keystone-ssh-unlock is not available"
      fi
      ;;
    blocked)
      notify "$title" "$message"
      ;;
    *)
      printf "Unknown setup action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-setup -p "Setup" >/dev/null 2>&1 &
}

case "${1:-}" in
  open-menu)
    shift
    open_menu "$@"
    ;;
  entries-json)
    shift
    entries_json "$@"
    ;;
  preview-blocked)
    shift
    preview_blocked "$@"
    ;;
  preview-ssh)
    ssh_key_preview
    ;;
  dispatch)
    shift
    dispatch "$@"
    ;;
  *)
    echo "Usage: keystone-setup-menu {open-menu|entries-json|preview-blocked|preview-ssh|dispatch} ..." >&2
    exit 1
    ;;
esac
