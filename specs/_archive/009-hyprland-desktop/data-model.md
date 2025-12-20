# Data Model: Hyprland Desktop Environment

## Overview

This feature involves configuration modules rather than traditional data entities. The "entities" in this context are the NixOS module options and configurations that define the desktop environment.

## Module Entities

### 1. NixOS Desktop Module (`modules/client/desktop/hyprland.nix`)

**Purpose**: System-level configuration for the Hyprland desktop environment.

**Key Attributes**:
- `enable`: Boolean option to activate the desktop module
- `greetd`: Configuration for the login manager
- `systemPackages`: List of system-level packages (hyprlock, hypridle, chromium)

**Validation Rules**:
- When enabled, greetd service must be configured
- Required packages must be available in nixpkgs

**Relationships**:
- Depends on: Base NixOS system configuration
- Integrates with: home-manager for user-level configuration

### 2. Keystone Desktop Hyprland Module (`modules/keystone/desktop/home/hyprland/default.nix`)

**Purpose**: User-level configuration for the Hyprland desktop environment.

**Key Attributes**:
- `enable`: Boolean option to activate the user desktop module
- `monitors`: List of monitor configuration strings for Hyprland
- `terminal`: Default terminal application (default: `uwsm app -- ghostty`)
- `fileManager`: Default file manager application (default: `uwsm app -- nautilus --new-window`)
- `browser`: Default browser application (default: `uwsm app -- chromium --new-window --ozone-platform=wayland`)
- `scale`: Display scale factor (default: `2` for HiDPI displays)
- `modifierKey`: Primary modifier key for keybindings (default: `ALT`, options: `SUPER`, `ALT`, `CTRL`)
- `capslockAsControl`: Remap Caps Lock to Control key (default: `true`)

**Example Configuration**:
```nix
{
  keystone.desktop.hyprland = {
    enable = true;
    modifierKey = "ALT";        # Use ALT as the primary modifier
    capslockAsControl = true;   # Remap Caps Lock to Control
    scale = 1;                  # For non-HiDPI displays
  };
}
```

**Sub-modules**:
- `appearance.nix`: Visual styling and appearance settings
- `autostart.nix`: Applications to start with the session
- `bindings.nix`: Keyboard shortcuts (uses `modifierKey` option)
- `environment.nix`: Environment variables
- `hypridle.nix`: Idle management configuration
- `hyprlock.nix`: Screen lock configuration
- `hyprpaper.nix`: Wallpaper configuration
- `hyprsunset.nix`: Night light configuration
- `input.nix`: Input device settings (uses `capslockAsControl` option)
- `layout.nix`: Window layout settings

**Validation Rules**:
- When enabled, Hyprland must be installed at system level
- Configuration files must be syntactically valid

**Relationships**:
- Depends on: NixOS desktop module being enabled
- Integrates with: `terminal-dev-environment` module (passive integration via shared terminal)

## Configuration Flow

1. **Boot**: System boots with greetd enabled (from NixOS module)
2. **Login**: User sees greetd login prompt
3. **Session Start**: Upon authentication, greetd launches uwsm
4. **Desktop Load**: uwsm starts Hyprland session with user configuration from home-manager
5. **Components Launch**: Waybar, hyprpaper, mako start automatically as part of session
6. **Idle Monitoring**: hypridle monitors for inactivity and triggers hyprlock when needed

## State Transitions

### Session State
- `boot` → `login_prompt` (greetd starts)
- `login_prompt` → `authenticating` (user enters credentials)
- `authenticating` → `session_starting` (uwsm launches)
- `session_starting` → `active` (Hyprland running)
- `active` → `idle` (no user activity)
- `idle` → `locked` (hypridle triggers hyprlock)
- `locked` → `active` (user unlocks)

## Package Lists

### System-Level Packages (NixOS Module)
- hyprlock
- hypridle
- chromium

### User-Level Packages (Home-Manager Module)
- ghostty
- hyprpaper
- waybar
- mako
- hyprshot
- hyprpicker
- hyprsunset
- brightnessctl
- pamixer
- playerctl
- gnome-themes-extra
- pavucontrol
- wl-clipboard
- glib
