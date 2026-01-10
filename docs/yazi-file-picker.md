# Yazi File Picker Integration

This document explains how to enable Yazi as the default file picker in the Keystone desktop environment for browsers and other applications.

## Overview

The Keystone desktop includes configuration scaffolding for using Yazi (the terminal file manager) as a file picker in browsers like Firefox and Chromium. This integration uses the XDG Desktop Portal system to intercept file picker requests and redirect them to a terminal window running Yazi.

## Current Status

**Configuration files are pre-created but the feature requires an external package.**

The following files are automatically created when the desktop module is enabled:

- `~/.config/xdg-desktop-portal/portals.conf` - Portal backend configuration
- `~/.config/xdg-desktop-portal-termfilechooser/config` - Yazi wrapper script configuration

## Enabling Yazi File Picker

To enable yazi as your file picker, you need to install `xdg-desktop-portal-termfilechooser`:

### Option 1: Install from AUR (Arch Linux)

```bash
yay -S xdg-desktop-portal-termfilechooser-git
```

### Option 2: Build from Source

```bash
git clone https://github.com/boydaihungst/xdg-desktop-portal-termfilechooser
cd xdg-desktop-portal-termfilechooser
cargo build --release
sudo cp target/release/xdg-desktop-portal-termfilechooser /usr/local/bin/
```

### Option 3: Add to Your Nix Configuration

If you can successfully package `xdg-desktop-portal-termfilechooser`, add it to your configuration:

```nix
# In your NixOS configuration
xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-termfilechooser ];
```

### Enable the Portal Backend

After installing, edit `~/.config/xdg-desktop-portal/portals.conf` and uncomment the line:

```ini
[preferred]
default=gtk
org.freedesktop.impl.portal.FileChooser=termfilechooser
```

## How It Works

1. **Portal Backend**: `xdg-desktop-portal-termfilechooser` acts as a bridge between browsers and terminal applications
2. **Yazi Wrapper**: A shell script (`yazi-file-picker`) launches Ghostty terminal with Yazi in chooser mode
3. **File Selection**: When you click "Browse" in a browser, Yazi opens in a terminal window
4. **Selection Return**: Selected files are passed back to the browser via the portal system

## Browser Configuration

### Firefox

The desktop module automatically configures Firefox to use XDG portals for file selection. If you manually configure Firefox, set:

```
about:config -> widget.use-xdg-desktop-portal.file-picker = 1
```

### Chromium/Chrome

Launch with these flags or set environment variables:

```bash
chromium --enable-features=UseOzonePlatform --ozone-platform=wayland
```

Or set in your environment:

```bash
export GTK_USE_PORTAL=1
```

## Limitations

- **Linux Only**: This integration relies on DBus/Portal architecture specific to Linux
- **Save Dialogs**: "Save As" dialogs require manual filename entry in Yazi
- **Updates**: Browser or portal updates may occasionally break the integration
- **Terminal Required**: Requires a graphical terminal emulator (Ghostty is used by default)

## Customization

The Yazi wrapper script is located in your nix store and launched via the portal config. To customize:

1. The wrapper script opens Yazi in Ghostty terminal
2. You can modify terminal settings in `ghostty.nix`
3. Yazi configuration follows your normal Yazi settings

## Troubleshooting

### File picker doesn't open

1. Check if `xdg-desktop-portal-termfilechooser` is running:
   ```bash
   ps aux | grep xdg-desktop-portal
   ```

2. Verify portal configuration:
   ```bash
   cat ~/.config/xdg-desktop-portal/portals.conf
   ```

3. Restart the portal service:
   ```bash
   systemctl --user restart xdg-desktop-portal.service
   ```

### Yazi doesn't show selected file

Ensure you're pressing Enter to select the file in Yazi, not just navigating to it.

## Alternative: Use GTK File Picker

If you prefer the standard GTK file picker (default), the portal configuration already includes it. Simply don't uncomment the termfilechooser line in `portals.conf`.

## References

- [XDG Desktop Portal](https://flatpak.github.io/xdg-desktop-portal/)
- [xdg-desktop-portal-termfilechooser](https://github.com/boydaihungst/xdg-desktop-portal-termfilechooser)
- [Yazi File Manager](https://github.com/sxyazi/yazi)
