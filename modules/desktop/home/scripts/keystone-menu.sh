#!/bin/bash

# Keystone Menu - A hierarchical menu system using Walker

# Set to true when going directly to a submenu, so we can exit directly
BACK_TO_EXIT=false

back_to() {
  local parent_menu="$1"

  if [[ "$BACK_TO_EXIT" == "true" ]]; then
    exit 0
  elif [[ -n "$parent_menu" ]]; then
    "$parent_menu"
  else
    show_main_menu
  fi
}

menu() {
  local prompt="$1"
  local options="$2"
  local extra="$3"

  read -r -a args <<<"$extra"

  echo -e "$options" | keystone-launch-walker --dmenu --width 295 --minheight 1 --maxheight 630 -p "$prompt…" "${args[@]}" 2>/dev/null
}

not_implemented() {
  notify-send "Not implemented" "$1" -t 2000
}

open_url() {
  xdg-open "$1" &
}

# ============== LEARN MENU ==============
show_learn_menu() {
  case $(menu "Learn" "  Keybindings\n  Hyprland\n  NixOS") in
  *Keybindings*) keystone-menu-keybindings ;;
  *Hyprland*) open_url "https://wiki.hypr.land/" ;;
  *NixOS*) open_url "https://wiki.nixos.org/" ;;
  *) show_main_menu ;;
  esac
}

# ============== CAPTURE MENU ==============
show_capture_menu() {
  case $(menu "Capture" "  Screenshot\n  Screenrecord") in
  *Screenshot*) show_screenshot_menu ;;
  *Screenrecord*) keystone-screenrecord ;;
  *) show_main_menu ;;
  esac
}

show_screenshot_menu() {
  case $(menu "Screenshot" "  Snap with Editing\n  Straight to Clipboard") in
  *Editing*) keystone-screenshot smart ;;
  *Clipboard*) keystone-screenshot smart clipboard ;;
  *) show_capture_menu ;;
  esac
}

show_toggle_menu() {
  case $(menu "Toggle" "󰅶  Idle Inhibitor\n󰔎  Nightlight\n󰍜  Top Bar") in
  *Idle*) keystone-idle-toggle ;;
  *Nightlight*) keystone-nightlight-toggle ;;
  *Bar*) not_implemented "Toggle waybar" ;;
  *) show_main_menu ;;
  esac
}

# ============== STYLE MENU ==============
show_style_menu() {
  case $(menu "Style" "󰸌  Theme\n  Background") in
  *Theme*) show_theme_menu ;;
  *Background*) not_implemented "Background switcher" ;;
  *) show_main_menu ;;
  esac
}

show_theme_menu() {
  # Get available themes from keystone themes directory
  THEMES_DIR="$HOME/.config/keystone/themes"
  if [[ ! -d "$THEMES_DIR" ]]; then
    notify-send "No themes found" "Themes directory not found at $THEMES_DIR" -t 3000
    show_style_menu
    return
  fi

  # Build theme list
  theme_list=""
  for theme in "$THEMES_DIR"/*/; do
    theme_name=$(basename "$theme")
    theme_list="${theme_list}󰸌  ${theme_name}\n"
  done

  # Remove trailing newline
  theme_list="${theme_list%\\n}"

  selected=$(echo -e "$theme_list" | keystone-launch-walker --dmenu --width 350 --minheight 1 --maxheight 630 -p "Theme…" 2>/dev/null)

  if [[ -n "$selected" ]]; then
    # Extract theme name (remove icon prefix)
    theme_name=$(echo "$selected" | sed 's/^󰸌  //')
    keystone-theme-switch "$theme_name"
  else
    show_style_menu
  fi
}

# ============== SETUP MENU ==============
show_setup_menu() {
  case $(menu "Setup" "  Audio\n  Wifi\n󰂯  Bluetooth\n󰍹  Monitors") in
  *Audio*) not_implemented "Audio setup" ;;
  *Wifi*) not_implemented "WiFi setup" ;;
  *Bluetooth*) not_implemented "Bluetooth setup" ;;
  *Monitors*) not_implemented "Monitor setup" ;;
  *) show_main_menu ;;
  esac
}

# ============== INSTALL MENU ==============
show_install_menu() {
  not_implemented "Install menu - use nix instead"
  show_main_menu
}

# ============== REMOVE MENU ==============
show_remove_menu() {
  not_implemented "Remove menu - use nix instead"
  show_main_menu
}

# ============== UPDATE MENU ==============
show_update_menu() {
  not_implemented "Update menu - use nix flake update"
  show_main_menu
}

# ============== SYSTEM MENU ==============
show_system_menu() {
  case $(menu "System" "  Lock\n󰤄  Suspend\n󰜉  Restart\n󰐥  Shutdown") in
  *Lock*) hyprlock ;;
  *Suspend*) systemctl suspend ;;
  *Restart*) systemctl reboot ;;
  *Shutdown*) systemctl poweroff ;;
  *) show_main_menu ;;
  esac
}

# ============== MAIN MENU ==============
show_main_menu() {
  go_to_menu "$(menu "Go" "󰀻  Apps\n󰧑  Learn\n  Capture\n󰔎  Toggle\n  Style\n  Setup\n󰉉  Install\n󰭌  Remove\n  Update\n  System")"
}

go_to_menu() {
  case "${1,,}" in
  *apps*) walker ;;
  *learn*) show_learn_menu ;;
  *capture*) show_capture_menu ;;
  *toggle*) show_toggle_menu ;;
  *style*) show_style_menu ;;
  *setup*) show_setup_menu ;;
  *install*) show_install_menu ;;
  *remove*) show_remove_menu ;;
  *update*) show_update_menu ;;
  *system*) show_system_menu ;;
  esac
}

if [[ -n "$1" ]]; then
  BACK_TO_EXIT=true
  go_to_menu "$1"
else
  show_system_menu
fi
