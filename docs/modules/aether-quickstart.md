# Aether Quick Start Guide

This guide shows you how to enable and use Aether on your Keystone client system.

## Installation

### 1. Enable in Configuration

Add to your NixOS configuration:

```nix
{
  keystone.client.desktop.aether.enable = true;
}
```

### 2. Rebuild System

```bash
sudo nixos-rebuild switch
```

## First Use

### Launch Aether

```bash
aether
```

### Load a Wallpaper

```bash
aether --wallpaper ~/Pictures/wallpaper.jpg
```

### Using the GUI

1. **Wallpaper Selection**: Click the wallpaper area to browse and select an image
2. **Color Extraction**: Click "Extract Colors" to generate a palette from your wallpaper
3. **Color Adjustment**: Use the sliders to adjust vibrance, contrast, and temperature
4. **Apply Theme**: Click "Apply" to generate configuration files for your desktop apps

### Working with Blueprints

Save your current theme:
1. Click the Blueprint button in the toolbar
2. Enter a name for your theme
3. Click "Save"

Apply a saved theme:
```bash
aether --apply-blueprint MY_THEME_NAME
```

List all saved themes:
```bash
aether --list-blueprints
```

## Supported Applications

Aether generates configuration for:

- **Window Manager**: Hyprland
- **Status Bar**: Waybar  
- **Terminals**: Kitty, Alacritty, Foot, WezTerm
- **Editors**: Neovim (37 themes), VSCode, Zed
- **System Tools**: btop, cava
- **Notifications**: Mako, Dunst
- **Launchers**: Rofi, Wofi, Fuzzel
- And more!

## Tips

1. **Image Filters**: Apply filters to your wallpaper before color extraction for better results
2. **Color Lock**: Lock specific colors you want to preserve while adjusting others
3. **Presets**: Start with built-in presets (Dracula, Nord, etc.) and customize from there
4. **Shaders**: Install hyprshade for screen shader effects (install separately)

## Troubleshooting

### Aether won't launch

Ensure you've rebuilt your system after enabling the module:
```bash
sudo nixos-rebuild switch
```

### No wallpapers showing

Check that you have images in your Pictures directory or use the wallhaven.cc browser built into Aether.

### Theme not applying

Generated configuration files are in `~/.config/` under each application's directory. Some applications may need to be restarted to pick up new themes.

## Advanced Usage

### Custom Package

Use a specific version or fork:

```nix
{
  keystone.client.desktop.aether = {
    enable = true;
    package = pkgs.callPackage ./my-aether-fork { };
  };
}
```

### With Shader Support

Install hyprshade for shader effects:

```nix
{
  keystone.client.desktop.aether.enable = true;
  environment.systemPackages = with pkgs; [ hyprshade ];
}
```

## More Information

- [Aether Documentation](docs/modules/aether.md)
- [Aether GitHub Repository](https://github.com/bjarneo/aether)
- [Example Configuration](examples/aether-client.nix)
