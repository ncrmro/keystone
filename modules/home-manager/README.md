# Desktop Hyprland Home Manager Module

This module provides a complete Hyprland desktop environment configuration for Keystone users using Home Manager.

## Features

- **Hyprland Window Manager**: Modern Wayland compositor with smooth animations
- **Complete Desktop Environment**: 
  - Waybar status bar
  - Mako notification daemon
  - Walker application launcher
  - Hyprpaper wallpaper manager
  - Hypridle idle management
  - Hyprlock screen lock
- **Development Tools**: Git, Neovim, Starship prompt
- **Terminal Environment**: Zsh with completions and syntax highlighting
- **Fonts**: JetBrains Mono Nerd Font and other essential fonts
- **Theming**: Dark Adwaita GTK theme

## Usage

To use this module in your Home Manager configuration:

```nix
{
  imports = [
    ./modules/home-manager
  ];
  
  keystone = {
    desktop = {
      enable = true;
      monitors = [ "DP-1,1920x1080@60,0x0,1" ]; # Optional: configure monitors
      wallpaper = "~/Pictures/my-wallpaper.jpg"; # Optional: set wallpaper path
    };
  };
}
```

## Configuration Options

The module provides the following configuration options via `keystone.desktop`:

- `enable`: Boolean to enable the desktop environment
- `monitors`: List of monitor configurations for Hyprland
- `wallpaper`: Path to wallpaper image file

## Key Bindings

- `Super + Return`: Open terminal (Alacritty)
- `Super + Q`: Close window
- `Super + M`: Exit Hyprland
- `Super + E`: Open file manager (Nautilus)
- `Super + R`: Open application launcher (Walker)
- `Super + F`: Fullscreen window
- `Super + V`: Toggle floating
- `Super + H/J/K/L`: Move focus (vim-style)
- `Super + 1-9`: Switch workspaces
- `Super + Shift + 1-9`: Move window to workspace

## Requirements

This module requires:
- NixOS with Home Manager
- Wayland support
- Audio system (PipeWire/PulseAudio)

## File Structure

```
modules/home-manager/
├── default.nix              # Main module file
├── hyprland.nix             # Hyprland configuration
├── hyprland/
│   ├── configuration.nix    # Main Hyprland settings
│   ├── autostart.nix        # Startup applications
│   ├── bindings.nix         # Key bindings
│   ├── envs.nix            # Environment variables
│   ├── input.nix           # Input configuration
│   ├── looknfeel.nix       # Visual settings
│   └── windows.nix         # Window rules
├── hypridle.nix            # Idle management
├── hyprlock.nix            # Screen lock
├── hyprpaper.nix           # Wallpaper
├── waybar.nix              # Status bar
├── mako.nix                # Notifications
├── walker.nix              # App launcher
├── fonts.nix               # Font configuration
├── git.nix                 # Git configuration
├── starship.nix            # Shell prompt
└── zsh.nix                 # Zsh shell
```

## Customization

Users can override any configuration by importing specific modules and modifying the settings. The module is designed to be modular and extensible.