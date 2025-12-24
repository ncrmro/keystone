# Keystone Desktop Module Specification

A declarative tiling window manager desktop environment built on Hyprland for NixOS.

## Overview

The Keystone Desktop provides a keyboard-driven, efficient workspace for developers and power users. It emphasizes:

- **Declarative Configuration**: All settings managed through Nix options
- **Keyboard-First Interaction**: Minimal mouse dependency with discoverable keybindings
- **Runtime Theming**: Switch themes without rebuilding the system
- **Unified Menu System**: Consistent access to all desktop functions via `Super+Escape`

## Architecture

```
desktop/
├── home/
│   ├── hyprland/           # Window manager configuration
│   │   ├── appearance.nix  # Visual settings (gaps, borders, animations)
│   │   ├── bindings.nix    # Keybindings and shortcuts
│   │   ├── layout.nix      # Tiling behavior
│   │   └── ...
│   ├── components/         # Desktop components (waybar, launcher, etc.)
│   └── scripts/            # Utility scripts (menu, screenshot, etc.)
└── SPEC.md
```

## Theming

### Theme Structure

Themes are stored in `~/.config/keystone/themes/<theme-name>/` with the following structure:

```
themes/
├── royal-green/
│   ├── hyprland.conf       # Border colors, accent colors
│   ├── waybar.css          # Status bar styling
│   ├── mako.conf           # Notification styling
│   ├── hyprlock.conf       # Lock screen styling
│   └── colors.sh           # Exported color variables for scripts
└── nord/
    └── ...
```

### Active Theme

The current theme is symlinked at `~/.config/keystone/current/theme/` and sourced by all components.

### Theme Switching

```bash
keystone-theme-switch <theme-name>
```

This command:
1. Updates the `current` symlink
2. Reloads Hyprland configuration
3. Signals waybar to reload CSS
4. Restarts mako with new config

### Color Variables

Themes export these standard variables in `colors.sh`:

| Variable | Description |
|----------|-------------|
| `KEYSTONE_COLOR_BG` | Primary background |
| `KEYSTONE_COLOR_FG` | Primary foreground |
| `KEYSTONE_COLOR_ACCENT` | Accent/highlight color |
| `KEYSTONE_COLOR_BORDER_ACTIVE` | Active window border |
| `KEYSTONE_COLOR_BORDER_INACTIVE` | Inactive window border |
| `KEYSTONE_COLOR_URGENT` | Urgent/error color |

## Menu System (Super+Escape)

The main menu provides hierarchical access to all desktop functions. Accessed via `Super+Escape` or power button.

### Menu Structure

```
Main Menu
├── Apps          → Launch application picker (walker)
├── Learn         → Documentation and keybinding reference
├── Capture       → Screenshot and screen recording
├── Toggle        → Quick toggles (idle, nightlight, waybar)
├── Style         → Theme and wallpaper selection
├── Setup         → System configuration
│   ├── Audio     → Audio device selection
│   ├── Wifi      → Network configuration
│   ├── Bluetooth → Bluetooth pairing
│   └── Monitors  → Display configuration ← NEW
├── Install       → Package installation (via nix)
├── Remove        → Package removal (via nix)
├── Update        → System update (nix flake update)
└── System        → Lock, suspend, restart, shutdown
```

### Monitor Setup Submenu

The Monitor setup menu provides runtime display configuration for laptops with external monitors.

```
Setup → Monitors
├── Auto Left      → External monitor to the left of laptop
├── Auto Right     → External monitor to the right of laptop
├── Mirror         → Clone laptop display to external monitor
├── External Only  → Disable laptop, use external only
├── Laptop Only    → Disable external, use laptop only
└── Detect         → Re-detect connected monitors
```

#### Monitor Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Auto Left** | External positioned left of laptop display | Desk setup with monitor on left |
| **Auto Right** | External positioned right of laptop display | Desk setup with monitor on right |
| **Mirror** | Same content on both displays | Presentations, screen sharing |
| **External Only** | Laptop display disabled | Docked at desk, lid closed |
| **Laptop Only** | External display disabled | Undocking, travel |
| **Detect** | Query connected monitors and show status | Troubleshooting, verification |

#### Implementation Details

Monitor configuration uses `hyprctl keyword monitor` for runtime changes:

```bash
# Auto Right: External monitor right of laptop (eDP-1)
hyprctl keyword monitor "HDMI-A-1,preferred,auto-right,1"

# Auto Left: External monitor left of laptop
hyprctl keyword monitor "HDMI-A-1,preferred,auto-left,1"

# Mirror: Clone laptop to external
hyprctl keyword monitor "HDMI-A-1,preferred,auto,1,mirror,eDP-1"

# External Only: Disable laptop display
hyprctl keyword monitor "eDP-1,disabled"
hyprctl keyword monitor "HDMI-A-1,preferred,auto,1"

# Laptop Only: Disable external
hyprctl keyword monitor "HDMI-A-1,disabled"
hyprctl keyword monitor "eDP-1,preferred,auto,1"
```

#### Auto-Detection

The monitor script should:
1. Query connected monitors via `hyprctl monitors -j`
2. Identify laptop display (typically `eDP-1` or `eDP-2`)
3. Identify external displays (HDMI-A-*, DP-*)
4. Apply appropriate configuration based on selection

```bash
# Get connected monitors
hyprctl monitors -j | jq -r '.[].name'

# Get monitor details
hyprctl monitors -j | jq '.[] | {name, description, make, model}'
```

#### Persistence

Monitor configurations are runtime-only by default. For persistent configurations:
- Add to `keystone.desktop.hyprland.monitors` in Nix config
- Or save to `~/.config/keystone/monitors.conf` for user overrides

### Menu Keybinding

| Keybinding | Action |
|------------|--------|
| `$mod+Escape` | Open main menu |
| `XF86PowerOff` | Open system submenu directly |
| `$mod+K` | Open keybindings reference |

## Keybindings Reference

> **Note**: `$mod` refers to the configured modifier key (default: `ALT`, configurable via `modifierKey` option)

### Core Navigation

| Keybinding | Action |
|------------|--------|
| `$mod+Return` | Open terminal |
| `$mod+Space` | Application launcher |
| `$mod+B` | Open browser |
| `$mod+E` | Open file manager |
| `$mod+W` | Close active window |

### Window Management

| Keybinding | Action |
|------------|--------|
| `$mod+H/L` | Move focus left/right |
| `$mod+Arrow` | Move focus in direction |
| `$mod+Shift+Arrow` | Swap window in direction |
| `$mod+F` | Toggle fullscreen |
| `$mod+Shift+V` | Toggle floating |
| `$mod+T` | Toggle split direction |

### Workspaces

| Keybinding | Action |
|------------|--------|
| `$mod+1-0` | Switch to workspace 1-10 |
| `$mod+Shift+1-0` | Move window to workspace |
| `$mod+Tab` | Next workspace |
| `$mod+Shift+Tab` | Previous workspace |
| `$mod+S` | Toggle scratchpad |

### Utilities

| Keybinding | Action |
|------------|--------|
| `Print` | Screenshot with editing |
| `Shift+Print` | Screenshot to clipboard |
| `$mod+Ctrl+V` | Clipboard history |
| `$mod+Ctrl+E` | Emoji picker |
| `$mod+Ctrl+I` | Toggle idle inhibitor |
| `$mod+Ctrl+N` | Toggle nightlight |

## Nix Options

```nix
keystone.desktop.hyprland = {
  enable = mkEnableOption "Hyprland window manager";

  monitors = mkOption {
    type = types.listOf types.str;
    default = [ ",preferred,auto,1" ];
    description = "Monitor configuration strings";
  };

  scale = mkOption {
    type = types.int;
    default = 2;
    description = "Display scale factor (1 or 2)";
  };

  terminal = mkOption {
    type = types.str;
    default = "uwsm app -- ghostty";
  };

  browser = mkOption {
    type = types.str;
    default = "uwsm app -- chromium";
  };

  fileManager = mkOption {
    type = types.str;
    default = "uwsm app -- nautilus";
  };

  modifierKey = mkOption {
    type = types.str;
    default = "ALT";
    description = "Primary modifier key for keybindings (SUPER, ALT, CTRL)";
  };

  capslockAsControl = mkOption {
    type = types.bool;
    default = true;
    description = "Remap Caps Lock to Control key";
  };
};
```

### Input Configuration

The desktop module supports keyboard remapping options:

| Option | Default | Description |
|--------|---------|-------------|
| `modifierKey` | `ALT` | Primary modifier for all keybindings (`$mod`) |
| `capslockAsControl` | `true` | Remaps Caps Lock to Control via `ctrl:nocaps` |

**Example: Restore traditional keybindings**

```nix
keystone.desktop.hyprland = {
  enable = true;
  modifierKey = "SUPER";        # Use Super/Windows key as modifier
  capslockAsControl = false;    # Keep Caps Lock as Caps Lock
};
```

## Future Considerations

- **Per-Monitor Workspaces**: Assign specific workspaces to specific monitors
- **Monitor Profiles**: Save and recall named monitor configurations
- **Hot-Plug Handling**: Automatic configuration when monitors connect/disconnect
- **Resolution Presets**: Quick access to common resolutions for presentations
