# Keystone Desktop Implementation Plan

This document outlines the technical implementation details and the NixOS module structure for the Keystone Desktop environment components described in `spec.md`.

## Technology Stack

The Keystone Desktop leverages the following key technologies:

*   **Hyprland**: The Wayland tiling window manager, serving as the core desktop environment.
*   **Bash**: Shell scripting for custom utilities and menu logic.
*   **Walker**: A Wayland-native application launcher (dmenu-style) used for interactive menus.
*   **Hyprlock**: A Wayland-native screen locker.
*   **Hyprsunset**: A Wayland-native blue light filter daemon.
*   **Hypridle**: An idle management daemon for Wayland.
*   **Waybar**: A highly customizable Wayland bar for status display.
*   **systemd**: Linux init system, used for service management (e.g., suspend, reboot, poweroff) and user services.
*   **Nix / Home Manager**: The declarative configuration system used to manage all desktop components, ensuring reproducibility and consistency.
*   **jq**: Command-line JSON processor, used for parsing Hyprland's output for keybinding generation.
*   **awk**: Text processing utility, used for parsing and formatting keybinding information.
*   **xkbcli**: Utility for inspecting XKB (X Keyboard Extension) configuration, used in keybinding display.
*   **playerctl**: Command-line utility for controlling media players.
*   **brightnessctl**: Command-line utility for controlling screen brightness.
*   **pamixer / wpctl**: Command-line utilities for audio control.
*   **gsettings**: Command-line interface to GSettings, used for managing GTK/GNOME settings.
*   **xdg-open**: Utility for opening files, URLs, etc., with the default application.
*   **notify-send**: Utility for sending desktop notifications.
*   **grim**: Wayland screenshot tool.
*   **slurp**: Wayland utility for selecting a region.
*   **swappy**: Wayland screenshot editor and annotation tool.
*   **wl-clipboard**: Wayland clipboard utilities.
*   **gpu-screen-recorder**: Wayland screen recording tool.

## NixOS Module Documentation

The implementation of the Keystone Desktop components is primarily managed through Home Manager modules, ensuring a declarative and modular approach. The relevant modules within the `.submodules/keystone/modules/keystone/desktop/` path are as follows:

### 1. Menu System (`dt-menu-001`)

*   **Module Path**: `home/scripts/default.nix`
*   **Description**: This module defines and packages the `keystone-menu` shell script.
*   **Script Name**: `keystone-menu.sh`
*   **Technology**: Bash, Walker.
*   **Functionality**: Implements the hierarchical menu system for accessing various desktop functions, including system power options, theme switching, nightlight schedule/intensity configuration, and utility toggles. It leverages `walker` for the interactive menu interface.

### 2. Keybindings Help (`dt-help-001`)

*   **Module Path**: `home/scripts/default.nix`
*   **Description**: This module defines and packages the `keystone-menu-keybindings` shell script.
*   **Script Name**: `keystone-menu-keybindings.sh`
*   **Technology**: Bash, `hyprctl`, `jq`, `awk`, `xkbcli`, Walker.
*   **Functionality**: Dynamically extracts and formats active Hyprland keybindings into a human-readable, searchable list, displayed using `walker`.

### 3. Status Bar (`dt-bar-001`)

*   **Module Path**: `home/components/waybar.nix`
*   **Description**: Configures the Waybar status bar, including its layout, modules, and styling.
*   **Technology**: Waybar, Bash (for custom modules like screen recording indicator).
*   **Functionality**: Provides a highly customized status bar displaying system information (CPU, battery, network, audio, clock), workspace navigation, and custom indicators. The screen recording indicator is specifically tied to `gpu-screen-recorder` via a signal.

### 4. Screen Locking (`dt-lock-001`)

*   **Module Path**: `home/hyprland/hyprlock.nix`
*   **Description**: Configures the Hyprlock screen locker.
*   **Technology**: Hyprlock.
*   **Functionality**: Sets up the appearance and behavior of the screen locker, including background, input field, and fingerprint authentication.

### 5. Lock Inhibition (`dt-inhibit-001`)

*   **Module Path**: `home/hyprland/hypridle.nix`
*   **Description**: Configures the Hypridle daemon for idle management and lock inhibition.
*   **Technology**: Hypridle.
*   **Functionality**: Prevents automatic screen locking or suspension based on defined rules (e.g., during full-screen video playback) and allows for manual toggling of inhibition.

### 6. Night Light (`dt-night-001`)

*   **Module Path**: `home/hyprland/hyprsunset.nix`
*   **Description**: Configures the Hyprsunset blue light filter.
*   **Technology**: Hyprsunset, Bash (for configuration scripts).
*   **Functionality**: Defines the default sunset profiles. The module now supports user-configurable schedules and intensities, which are managed and updated via a dedicated script integrated into the menu system.
*   **Toggle Script**: `home/scripts/default.nix` defines `keystoneNightlightToggle`.
*   **Configuration Script**: `home/scripts/default.nix` defines a script (e.g., `keystoneNightlightConfig`) for managing schedule and intensity, called from `keystone-menu.sh`.

### 7. Theming System (`dt-theme-001`)

*   **Module Path**: `home/theming/default.nix`
*   **Description**: Manages the deployment of theme assets and the theme switching mechanism.
*   **Technology**: Bash (for `keystone-theme-switch`), `ln`, `systemctl`, `gsettings`, `xdg-open`, `chromium`, Nix/Home Manager file management.
*   **Functionality**: Handles the copying of theme files (Waybar, Hyprlock, Mako, Ghostty, Helix, Zellij, etc.) from `omarchy` or custom sources, creates symlinks for the active theme, and provides the `keystone-theme-switch` script to dynamically apply theme changes across various desktop components.

### 8. Screen Recording and Screenshots (`dt-record-001`, `dt-shot-001`)

*   **Module Path**: `home/scripts/default.nix`
*   **Description**: This module defines and packages the `keystone-screenrecord` and `keystone-screenshot` shell scripts.
*   **Script Names**: `keystone-screenrecord.sh`, `keystone-screenshot.sh`
*   **Technology**: Bash, `gpu-screen-recorder`, `grim`, `slurp`, `swappy`, `wl-clipboard`, `systemd` (for managing recording process).
*   **Functionality**:
    *   `keystone-screenrecord.sh`: Manages starting and stopping screen recordings, using `gpu-screen-recorder`. It integrates with Waybar to display a recording indicator.
    *   `keystone-screenshot.sh`: Captures screenshots using `grim` and `slurp`. It can optionally open the screenshot in `swappy` for editing/annotation and integrates with `wl-clipboard` for clipboard operations.

### 9. Hyprland Keybindings

*   **Module Path**: `home/hyprland/bindings.nix`
*   **Description**: Defines the global keyboard shortcuts for the Hyprland window manager.
*   **Technology**: Hyprland.
*   **Functionality**: Maps key combinations to actions, including launching applications, managing windows, navigating workspaces, and triggering custom scripts like `keystone-menu`, `keystone-menu-keybindings`, `keystone-screenrecord`, `keystone-screenshot`, and `keystoneNightlightToggle`. This module contains the `Mod + Escape` binding that triggers the `keystone-menu`.
