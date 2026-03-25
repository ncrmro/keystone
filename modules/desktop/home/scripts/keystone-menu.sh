#!/usr/bin/env bash

set -euo pipefail

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
  local extra="${3:-}"

  read -r -a args <<<"$extra"

  echo -e "$options" | keystone-launch-walker --dmenu --width 295 --minheight 1 --maxheight 630 -p "$prompt…" "${args[@]}" 2>/dev/null
}

not_implemented() {
  notify-send "Not implemented" "$1" -t 2000
}

open_url() {
  xdg-open "$1" &
}

session_name_matches_slug() {
  local session_name="$1"
  local project_slug="$2"

  [[ "$session_name" == "$project_slug" || "$session_name" == "${project_slug}-"* ]] \
    || [[ "$session_name" == "obs-${project_slug}" || "$session_name" == "obs-${project_slug}-"* ]]
}

session_slug_for_project() {
  local session_name="$1"
  local project_slug="$2"

  if [[ "$session_name" == "obs-${project_slug}" || "$session_name" == "$project_slug" ]]; then
    printf "main\n"
  elif [[ "$session_name" == "obs-${project_slug}-"* ]]; then
    printf "%s\n" "${session_name#"obs-${project_slug}-"}"
  elif [[ "$session_name" == "${project_slug}-"* ]]; then
    printf "%s\n" "${session_name#"${project_slug}-"}"
  else
    printf "main\n"
  fi
}

session_title_for_project() {
  local project_slug="$1"
  local session_slug="${2:-main}"

  if [[ "$session_slug" == "main" || -z "$session_slug" ]]; then
    printf "%s\n" "$project_slug"
  else
    printf "%s-%s\n" "$project_slug" "$session_slug"
  fi
}

find_client_for_title() {
  local expected_title="$1"

  hyprctl clients -j 2>/dev/null | jq -r --arg expected_title "$expected_title" '
    map(
      select(.class == "com.mitchellh.ghostty")
      | select(.title == $expected_title or (.title | startswith($expected_title + " | ")))
    )
    | sort_by(.focusHistoryID)
    | .[0]
    | if . == null then "" else "\(.address)\t\(.workspace.name)" end
  '
}

switch_to_active_project_context() {
  local project_slug="$1"
  local zellij_output="$2"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local session_name
    session_name=$(printf "%s\n" "$line" | awk '{print $1}')

    if session_name_matches_slug "$session_name" "$project_slug" && ! printf "%s\n" "$line" | grep -q "EXITED"; then
      local session_slug expected_title client_info client_address workspace_name
      session_slug=$(session_slug_for_project "$session_name" "$project_slug")
      expected_title=$(session_title_for_project "$project_slug" "$session_slug")
      client_info=$(find_client_for_title "$expected_title")

      if [[ -n "$client_info" ]]; then
        client_address=${client_info%%$'\t'*}
        workspace_name=${client_info#*$'\t'}
        hyprctl dispatch workspace "$workspace_name" >/dev/null 2>&1
        hyprctl dispatch focuswindow "address:${client_address}" >/dev/null 2>&1
        return 0
      fi

      launch_project_context "$project_slug" "$session_slug"
      return 0
    fi
  done <<< "$zellij_output"

  launch_project_context "$project_slug"
}

launch_project_context() {
  local project_slug="$1"
  local session_slug="${2:-}"

  if [[ -n "$session_slug" ]]; then
    ghostty -e pz "$project_slug" "$session_slug" &
  else
    ghostty -e pz "$project_slug" &
  fi
}

prompt_for_session_slug() {
  menu "Session slug (optional)" ""
}

# ============== CONTEXTS MENU ==============
show_contexts_menu() {
  # Check if pz is available for project discovery
  if ! command -v pz >/dev/null 2>&1; then
    notify-send "pz not found" "Project session manager (pz) is required for contexts" -t 3000
    back_to show_main_menu
    return
  fi

  # Build list of active contexts from zellij sessions
  local zellij_output
  zellij_output=$(zellij list-sessions --no-formatting 2>/dev/null || true)
  
  local projects
  projects=$(pz discover-slugs 2>/dev/null || echo "")

  local context_list=""
  
  # Show every registered project and mark whether it has a live session.
  for slug in $projects; do
    local has_live_session=false
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue

      local session_name
      session_name=$(printf "%s\n" "$line" | awk '{print $1}')

      if session_name_matches_slug "$session_name" "$slug" && ! printf "%s\n" "$line" | grep -q "EXITED"; then
        has_live_session=true
        break
      fi
    done <<< "$zellij_output"

    if [[ "$has_live_session" == "true" ]]; then
      context_list="${context_list}●  ${slug}\n"
    else
      context_list="${context_list}○  ${slug}\n"
    fi
  done

  if [[ -z "$context_list" ]]; then
    notify-send "No contexts" "No projects found via pz" -t 2000
    back_to show_main_menu
    return
  fi

  context_list="${context_list%\\n}"
  selected=$(echo -e "$context_list" | keystone-launch-walker --dmenu --width 350 --minheight 1 --maxheight 630 -p "Context…" 2>/dev/null) || { back_to show_main_menu; return; }

  if [[ -n "$selected" ]]; then
    local selected_slug
    selected_slug=$(echo "$selected" | awk '{print $2}')
    if echo "$selected" | grep -q "^●"; then
      switch_to_active_project_context "$selected_slug" "$zellij_output"
    else
      local session_slug
      session_slug=$(prompt_for_session_slug) || { back_to show_main_menu; return; }
      launch_project_context "$selected_slug" "$session_slug"
    fi
  else
    back_to show_main_menu
  fi
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
  go_to_menu "$(menu "Go" "󰀻  Apps\n  Contexts\n󰧑  Learn\n  Capture\n󰔎  Toggle\n  Style\n  Setup\n󰉉  Install\n󰭌  Remove\n  Update\n  System")"
}

go_to_menu() {
  case "${1,,}" in
  *apps*) walker ;;
  *contexts*) show_contexts_menu ;;
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

if [[ -n "${1:-}" ]]; then
  BACK_TO_EXIT=true
  go_to_menu "$1"
else
  show_main_menu
fi
