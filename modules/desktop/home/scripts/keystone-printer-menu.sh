#!/usr/bin/env bash
# keystone-printer-menu — CUPS printer default controller for terminal and Elephant.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=./keystone-desktop-config.sh
source "${SCRIPT_DIR}/keystone-desktop-config.sh"

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

cups_available() {
  command -v lpstat >/dev/null 2>&1
}

cups_unavailable_reason() {
  if ! cups_available; then
    printf "lpstat is not available in PATH.\n"
    return 0
  fi

  printf "Printer defaults are unavailable.\n"
}

blocked_entry_json() {
  local title="$1"
  local reason="$2"

  jq -n --arg title "$title" --arg reason "$reason" '
    [
      {
        Text: $title,
        Subtext: $reason,
        Value: "blocked",
        Preview: ("printf " + (($title + "\n\n" + $reason + "\n") | @sh)),
        PreviewType: "command"
      }
    ]
  '
}

default_printer_name() {
  lpstat -d 2>/dev/null | awk '/system default destination:/ {print $NF}'
}

list_printers_raw() {
  # Output: one printer name per line
  lpstat -p 2>/dev/null | awk '/^printer / {print $2}'
}

printer_description() {
  local name="$1"
  # lpstat -l -p shows description; fall back to name if unavailable
  lpstat -l -p "$name" 2>/dev/null \
    | awk '/Description:/ {$1=""; sub(/^ /, ""); print; exit}' \
    || printf "%s\n" "$name"
}

printers_json() {
  local printer_menu
  printer_menu=$(keystone_cmd keystone-printer-menu)

  if ! cups_available; then
    blocked_entry_json "Printers unavailable" "$(cups_unavailable_reason)"
    return 0
  fi

  local current_default=""
  current_default=$(default_printer_name)

  local printers=()
  while IFS= read -r name; do
    [[ -n "$name" ]] && printers+=("$name")
  done < <(list_printers_raw)

  if [[ ${#printers[@]} -eq 0 ]]; then
    blocked_entry_json "No printers found" "No CUPS printers are configured on this system."
    return 0
  fi

  local entries_json="[]"
  for name in "${printers[@]}"; do
    local is_default=false
    [[ "$name" == "$current_default" ]] && is_default=true

    local icon
    icon=$(if $is_default; then printf "  "; else printf "  "; fi)

    local subtext
    if $is_default; then
      subtext="current default"
    else
      subtext="set as default"
    fi

    local entry
    entry=$(jq -n \
      --arg icon "$icon" \
      --arg name "$name" \
      --arg subtext "$subtext" \
      --arg printer_menu "$printer_menu" \
      '{
        Text: ($icon + $name),
        Subtext: $subtext,
        Value: ("set-default\t" + $name),
        Preview: ($printer_menu + " preview-printer " + ($name | @sh)),
        PreviewType: "command"
      }')
    entries_json=$(jq -n --argjson arr "$entries_json" --argjson entry "$entry" '$arr + [$entry]')
  done

  printf "%s\n" "$entries_json"
}

set_default_printer() {
  local name="$1"

  if ! cups_available; then
    printf "lpstat is not available\n" >&2
    exit 1
  fi

  lpoptions -d "$name"
  save_printer_defaults
  notify "Printer default updated" "Default printer: ${name}"
}

printer_defaults_snippet() {
  local default_printer
  default_printer=$(default_printer_name)

  printf '  keystone.desktop.printer.default = '
  if [[ -n "$default_printer" ]]; then
    printf '"%s";\n' "$default_printer"
  else
    printf 'null;\n'
  fi
}

save_printer_defaults() {
  printer_defaults_snippet | keystone_write_desktop_state_section "printer defaults"
}

apply_config_defaults() {
  if ! cups_available; then
    return 0
  fi

  if [[ -n "${KEYSTONE_PRINTER_DEFAULT:-}" ]]; then
    lpoptions -d "$KEYSTONE_PRINTER_DEFAULT"
  fi
}

open_menu() {
  walker -q >/dev/null 2>&1 || true
  setsid "$(keystone_cmd keystone-launch-walker)" -m menus:keystone-printer -p "Printers" >/dev/null 2>&1 &
}

preview_printer() {
  local name="$1"

  if ! cups_available; then
    printf "%s\n" "$(cups_unavailable_reason)"
    return 0
  fi

  local current_default=""
  current_default=$(default_printer_name)

  printf "Printer: %s\n\nCurrent default: %s\n\nSelecting this printer updates the live default and saves it into nixos-config.\n" \
    "$name" \
    "$(if [[ "$name" == "$current_default" ]]; then printf "yes"; else printf "no"; fi)"
}

summary() {
  if ! cups_available; then
    printf "Printers unavailable\n%s" "$(cups_unavailable_reason)"
    return 0
  fi

  local current_default=""
  current_default=$(default_printer_name)

  if [[ -n "$current_default" ]]; then
    printf "Default: %s\n" "$current_default"
  else
    printf "No default printer set\n"
  fi
}

dispatch() {
  local payload="${1:-}"
  local action="" name=""

  IFS=$'\t' read -r action name <<<"$payload"

  case "$action" in
    set-default)
      set_default_printer "$name"
      ;;
    blocked)
      notify "Printers unavailable" "$(cups_unavailable_reason)"
      ;;
    *)
      printf "Unknown dispatch action: %s\n" "$action" >&2
      exit 1
      ;;
  esac
}

case "${1:-}" in
  open-menu)
    shift
    open_menu "$@"
    ;;
  printers-json)
    shift
    printers_json "$@"
    ;;
  set-default)
    shift
    set_default_printer "$@"
    ;;
  preview-printer)
    shift
    preview_printer "$@"
    ;;
  summary)
    shift
    summary "$@"
    ;;
  apply-config-defaults)
    shift
    apply_config_defaults "$@"
    ;;
  save-defaults)
    shift
    save_printer_defaults "$@"
    ;;
  dispatch)
    shift
    dispatch "$@"
    ;;
  *)
    echo "Usage: keystone-printer-menu {open-menu|printers-json|set-default|preview-printer|summary|apply-config-defaults|save-defaults|dispatch} ..." >&2
    exit 1
    ;;
esac
