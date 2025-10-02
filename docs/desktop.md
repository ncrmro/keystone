# Desktop Configuration

This document covers Hyprland desktop configuration for multi-monitor setups, workspace management, and navigation workflows.

## Monitor Configuration

### Identifying Your Monitors

Use `hyprctl monitors` to get monitor information:

```bash
hyprctl monitors
```

Output example:
```
Monitor eDP-1 (ID 0):
    1920x1080@60.00100 at 0x0
    description: Chimei Innolux Corporation 0x150C (eDP-1)

Monitor DP-1 (ID 1):
    2560x1440@144.00098 at 1920x0
    description: Dell Inc. DELL U2723QE (DP-1)
```

### Monitor Configuration Syntax

Use monitor descriptions for stable configuration (preferred over port names):

```bash
# Using descriptions (more stable)
monitor = desc:Dell Inc. DELL U2723QE, 2560x1440@144, 0x0, 1
monitor = desc:Chimei Innolux Corporation 0x150C, 1920x1080@60, 2560x0, 1

# Using port names (can change with hardware)
monitor = DP-1, 2560x1440@144, 0x0, 1
monitor = eDP-1, 1920x1080@60, 2560x0, 1
```

### Multi-Monitor Setup Examples

#### Vertical Left Monitor + Primary Horizontal

```bash
# Left monitor: 1080p vertical for documentation/chat
monitor = desc:ASUS PA248, 1920x1080@60, 0x0, 1, transform, 1

# Primary monitor: 1440p horizontal for development
monitor = desc:Dell Inc. DELL U2723QE, 2560x1440@144, 1080x0, 1
```

#### Triple Monitor Configuration

```bash
# Left vertical
monitor = HDMI-A-1, 1920x1080@60, 0x0, 1, transform, 1

# Center primary
monitor = DP-1, 2560x1440@144, 1080x0, 1

# Right secondary
monitor = DP-2, 1920x1080@60, 3640x360, 1
```

## Workspace Management

### Binding Workspaces to Monitors

```bash
# Vertical monitor workspaces (communication & reference)
workspace = 1, monitor:desc:ASUS PA248, default:true
workspace = 2, monitor:desc:ASUS PA248
workspace = 3, monitor:desc:ASUS PA248

# Primary monitor workspaces (development)
workspace = 4, monitor:desc:Dell Inc. DELL U2723QE, default:true
workspace = 5, monitor:desc:Dell Inc. DELL U2723QE
workspace = 6, monitor:desc:Dell Inc. DELL U2723QE
workspace = 7, monitor:desc:Dell Inc. DELL U2723QE
workspace = 8, monitor:desc:Dell Inc. DELL U2723QE
workspace = 9, monitor:desc:Dell Inc. DELL U2723QE
```

### Named Workspaces for Better Organization

```bash
# Vertical monitor: Communication and reference
workspace = name:slack, monitor:desc:ASUS PA248, default:true
workspace = name:youtube, monitor:desc:ASUS PA248
workspace = name:docs, monitor:desc:ASUS PA248

# Primary monitor: Development environments
workspace = name:code, monitor:desc:Dell Inc. DELL U2723QE, default:true
workspace = name:browser, monitor:desc:Dell Inc. DELL U2723QE
workspace = name:terminal, monitor:desc:Dell Inc. DELL U2723QE
```

### Practical Workflow Example

```bash
# Vertical monitor setup for communication
workspace = 1, monitor:desc:ASUS PA248, default:true, on-created-empty:slack
workspace = 2, monitor:desc:ASUS PA248, on-created-empty:firefox --new-window youtube.com

# Primary monitor for development
workspace = 4, monitor:desc:Dell Inc. DELL U2723QE, default:true, on-created-empty:code
workspace = 5, monitor:desc:Dell Inc. DELL U2723QE, on-created-empty:firefox --new-window localhost:3000
workspace = 6, monitor:desc:Dell Inc. DELL U2723QE, on-created-empty:firefox --new-window localhost:8080
```

## Special Workspaces (Scratchpad)

### Creating Multiple Scratchpads

```bash
# Quick access tools
bind = ALT, grave, togglespecialworkspace, main
bind = ALT, T, togglespecialworkspace, terminal
bind = ALT, N, togglespecialworkspace, notes
bind = ALT, C, togglespecialworkspace, calculator
bind = ALT, M, togglespecialworkspace, music
bind = ALT, P, togglespecialworkspace, passwords

# Auto-launch apps in scratchpads
workspace = special:terminal, on-created-empty:kitty
workspace = special:notes, on-created-empty:obsidian
workspace = special:calculator, on-created-empty:qalculate-gtk
workspace = special:music, on-created-empty:spotify
workspace = special:passwords, on-created-empty:bitwarden
```

### Moving Windows to Scratchpads

```bash
# Move current window to scratchpad
bind = $mainMod SHIFT, grave, movetoworkspace, special

# Move to specific scratchpad
bind = $mainMod SHIFT, T, movetoworkspace, special:terminal
bind = $mainMod SHIFT, N, movetoworkspace, special:notes
```

## App Placement and Privacy Rules

### Automatic App Placement

```bash
# Communication apps on vertical monitor
windowrule = workspace 1, ^(Slack)$
windowrule = workspace 1, ^(discord)$
windowrule = workspace 1, ^(element)$

# Browsers on specific workspaces
windowrule = workspace 2, title:.*YouTube.*
windowrule = workspace 4, ^(firefox)$
windowrule = workspace 5, title:.*localhost:3000.*

# Development tools
windowrule = workspace 4, ^(code)$
windowrule = workspace 4, ^(jetbrains-.*)$
windowrule = workspace 6, ^(postman)$
```

### Privacy Configuration

```bash
# Hide sensitive apps from screen recording
workspace = name:private, monitor:desc:Dell Inc. DELL U2723QE, rounding:false, decorate:false

# Chat apps in private scratchpad
bind = ALT, S, togglespecialworkspace, secure-chat
workspace = special:secure-chat, on-created-empty:signal-desktop

# Window rules for sensitive applications
windowrule = workspace special:secure-chat, ^(signal)$
windowrule = workspace special:secure-chat, ^(element)$
windowrule = workspace special:secure-chat, ^(whatsapp-for-linux)$
windowrule = workspace name:private, ^(keepassxc)$
windowrule = workspace name:private, ^(bitwarden)$
```

### Window Rule Properties

```bash
# Float specific apps
windowrule = float, ^(pavucontrol)$
windowrule = float, ^(blueman-manager)$
windowrule = float, ^(nm-connection-editor)$

# Opacity rules
windowrule = opacity 0.9, ^(kitty)$
windowrule = opacity 0.85, ^(code)$

# Size and position rules
windowrule = size 800 600, ^(calculator)$
windowrule = center, ^(calculator)$
```

## Navigation Keybindings

### Workspace Navigation

```bash
# Switch to workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9

# Move windows to workspaces
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9

# Move workspace between monitors
bind = $mainMod SHIFT, comma, movecurrentworkspacetomonitor, l
bind = $mainMod SHIFT, period, movecurrentworkspacetomonitor, r
```

### Window Management

```bash
# Window focus (vim-style)
bind = $mainMod, h, movefocus, l
bind = $mainMod, l, movefocus, r
bind = $mainMod, k, movefocus, u
bind = $mainMod, j, movefocus, d

# Window movement
bind = $mainMod SHIFT, h, movewindow, l
bind = $mainMod SHIFT, l, movewindow, r
bind = $mainMod SHIFT, k, movewindow, u
bind = $mainMod SHIFT, j, movewindow, d

# Window resizing
bind = $mainMod CTRL, h, resizeactive, -20 0
bind = $mainMod CTRL, l, resizeactive, 20 0
bind = $mainMod CTRL, k, resizeactive, 0 -20
bind = $mainMod CTRL, j, resizeactive, 0 20
```

## Keyboard as Mouse (Accessibility)

### Caps Lock Mouse Mode

*Note: This section contains placeholder configuration that requires additional implementation.*

```bash
# Mouse mode toggle with caps lock
# This requires custom scripting or additional tools

# Conceptual implementation:
# 1. Caps lock activates mouse mode
# 2. WASD or HJKL for cursor movement
# 3. Space for left click
# 4. Additional keys for right click, scroll

# Example script approach:
# bind = , Caps_Lock, exec, toggle-mouse-mode.sh

# During mouse mode:
# bind = , w, exec, ydotool mousemove_relative -- 0 -10
# bind = , s, exec, ydotool mousemove_relative -- 0 10
# bind = , a, exec, ydotool mousemove_relative -- -10 0
# bind = , d, exec, ydotool mousemove_relative -- 10 0
# bind = , space, exec, ydotool click 0xC0
```

### Alternative Implementation

```bash
# Using input-leap or similar tool for keyboard mouse
# Requires additional software installation and configuration

# Key concepts:
# - Software mouse cursor control
# - Toggle mode activation
# - Speed adjustment
# - Click simulation
```

## Example Complete Configuration

Here's a complete example for the described setup:

```bash
# Monitor setup: vertical left + horizontal primary
monitor = desc:ASUS PA248, 1920x1080@60, 0x0, 1, transform, 1
monitor = desc:Dell Inc. DELL U2723QE, 2560x1440@144, 1080x0, 1

# Workspace binding
workspace = 1, monitor:desc:ASUS PA248, default:true    # Slack
workspace = 2, monitor:desc:ASUS PA248                  # YouTube/Reference
workspace = 4, monitor:desc:Dell Inc. DELL U2723QE, default:true  # Code/IDE
workspace = 5, monitor:desc:Dell Inc. DELL U2723QE                # Dev Server 1
workspace = 6, monitor:desc:Dell Inc. DELL U2723QE                # Dev Server 2

# App placement
windowrule = workspace 1, ^(Slack)$
windowrule = workspace 2, title:.*YouTube.*
windowrule = workspace 4, ^(code)$
windowrule = workspace 5, title:.*localhost:3000.*
windowrule = workspace 6, title:.*localhost:8080.*

# Scratchpads for quick access
bind = ALT, grave, togglespecialworkspace, main
bind = ALT, T, togglespecialworkspace, terminal
workspace = special:terminal, on-created-empty:kitty

# Privacy for chat apps
bind = ALT, S, togglespecialworkspace, secure-chat
windowrule = workspace special:secure-chat, ^(signal)$
windowrule = workspace special:secure-chat, ^(whatsapp-for-linux)$
```

This configuration provides a productive workflow with dedicated spaces for communication, reference material, and multiple development environments.