# Aether NixOS Module

This module provides [Aether](https://github.com/bjarneo/aether), a visual theming application for Omarchy desktop environments.

## Features

Aether is a comprehensive theming tool that provides:

- **Intelligent Color Extraction** - Advanced ImageMagick-based algorithm with automatic image classification
- **Smart Palette Generation** - Adaptive strategies ensure readability and preserve image aesthetics
- **Image Filter Editor** - Apply blur, exposure, vignette, grain, and 12 presets before color extraction
- **Wallpaper Browsing** - Integrated wallhaven.cc browser, local wallpaper manager, and favorites system
- **Color Presets** - 10 popular themes: Dracula, Nord, Gruvbox, Tokyo Night, Catppuccin, and more
- **Advanced Color Tools** - Harmony generator, gradients, and adjustment sliders
- **Blueprint System** - Save and share themes as JSON files
- **Multi-App Support** - Hyprland, Waybar, Kitty, Alacritty, btop, Mako, and 15+ more applications

## Usage

Enable Aether in your NixOS configuration:

```nix
{
  keystone.client = {
    enable = true;
    desktop.aether.enable = true;
  };
}
```

## Configuration Options

### `keystone.client.desktop.aether.enable`

Type: `boolean`

Default: `false`

Enable the Aether theming application.

### `keystone.client.desktop.aether.package`

Type: `package`

Default: `pkgs.aether`

The Aether package to use. Override this if you want to use a custom build or version.

## Command Line Usage

Once enabled, Aether can be launched from the command line:

```bash
# Launch Aether GUI
aether

# Launch with a specific wallpaper
aether --wallpaper /path/to/image.png
aether -w /path/to/image.png

# List saved blueprint themes
aether --list-blueprints
aether -l

# Apply a blueprint by name
aether --apply-blueprint BLUEPRINT_NAME
aether -a BLUEPRINT_NAME
```

## Dependencies

The module automatically installs all required dependencies:

- GJS (GNOME JavaScript bindings)
- GTK 4
- Libadwaita 1
- libsoup3 (HTTP client library for wallhaven API)
- ImageMagick (color extraction and image filter processing)

### Optional Dependencies

- **hyprshade** - Screen shader manager for shader effects (not included by default)

To enable shader support, install hyprshade separately:

```nix
{
  environment.systemPackages = with pkgs; [ hyprshade ];
}
```

## Integration

Aether is designed to work seamlessly with the Omarchy desktop environment and Hyprland. It generates configuration files for:

- Hyprland
- Waybar
- Kitty
- Alacritty
- btop
- Mako
- And many more applications

Generated theme configurations are saved to your home directory and can be applied to your desktop environment.

## Example Configuration

Complete client configuration with Aether:

```nix
{
  keystone.client = {
    enable = true;
    
    desktop = {
      hyprland.enable = true;
      audio.enable = true;
      greetd.enable = true;
      packages.enable = true;
      aether.enable = true;  # Enable Aether theming
    };
  };
}
```

## See Also

- [Aether GitHub Repository](https://github.com/bjarneo/aether)
- [Omarchy Desktop Environment](https://github.com/basecamp/omarchy)
- Keystone Client Module Documentation
