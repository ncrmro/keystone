# Omarchy Theming Module

The Omarchy theming module provides unified visual styling across terminal and desktop applications using the [Omarchy](https://github.com/basecamp/omarchy) theming standard.

## Features

- **Unified Theming**: Consistent colors and styling across Helix editor, Ghostty terminal, and more
- **Easy Theme Switching**: Change themes with a single command (`omarchy-theme-next`)
- **Community Themes**: Install themes from Git repositories
- **Persistent Preferences**: Theme selection survives system rebuilds
- **Modular Design**: Enable theming for specific applications independently

## Quick Start

### Minimal Configuration

```nix
{
  # Enable terminal dev environment (required)
  programs.terminal-dev-environment = {
    enable = true;
    tools = {
      editor = true;    # Helix
      terminal = true;  # Ghostty
    };
  };

  # Enable theming with all defaults
  programs.omarchy-theming.enable = true;
}
```

After rebuilding your system:

```bash
# Switch themes
omarchy-theme-next

# Install a custom theme
omarchy-theme-install https://github.com/catppuccin/omarchy-catppuccin

# Set specific theme
omarchy-theme-set catppuccin
```

## Configuration Options

### Basic Options

- `programs.omarchy-theming.enable` - Master switch for theming system
- `programs.omarchy-theming.package` - Override omarchy source package (default: uses flake input)

### Terminal Theming

- `programs.omarchy-theming.terminal.enable` - Enable terminal app theming (default: true)
- `programs.omarchy-theming.terminal.applications.helix` - Theme Helix editor (default: true)
- `programs.omarchy-theming.terminal.applications.ghostty` - Theme Ghostty terminal (default: true)

### Desktop Theming

- `programs.omarchy-theming.desktop.enable` - Desktop theming stub (not yet implemented, default: false)

## Examples

See the `examples/theming/` directory for complete examples:

- **basic.nix** - Minimal theming setup
- **terminal-only.nix** - Terminal theming without desktop
- **selective-apps.nix** - Theme only specific applications

## File Locations

The module manages these filesystem locations:

**Managed by Nix (declarative):**
- `~/.config/omarchy/themes/default/` - Default theme files
- `~/.local/share/omarchy/bin/*` - Omarchy binaries
- `~/.local/share/omarchy/logo.txt` - Omarchy logo

**User-managed (preserved across rebuilds):**
- `~/.config/omarchy/current/theme` - Active theme symlink (your theme choice)
- `~/.config/omarchy/themes/<custom>/` - User-installed themes

## Theme Management Commands

After enabling the module, these commands are available:

- `omarchy-theme-next` - Cycle to next theme (alphabetical order)
- `omarchy-theme-set <name>` - Set specific theme by name
- `omarchy-theme-install <git-url>` - Install theme from Git repository
- `ls ~/.config/omarchy/themes/` - List installed themes
- `readlink ~/.config/omarchy/current/theme` - Show active theme

## How It Works

### Theme Persistence

Your theme selection persists across system rebuilds:

1. **Initial Setup**: On first activation, the module creates a symlink to the default theme
2. **Theme Switching**: When you run `omarchy-theme-next`, the symlink is updated
3. **System Rebuilds**: The activation script checks if the symlink exists and preserves it
4. **Result**: Your theme choice is never reset, even after `nixos-rebuild` or `home-manager switch`

### Application Integration

#### Ghostty Terminal

Ghostty uses the `config-file` directive to include theme configuration:

```
# Base ghostty config (managed by Nix)
font-size = 12

# Theme config included dynamically
config-file = ~/.config/omarchy/current/theme/ghostty.conf
```

#### Helix Editor

Helix theme integration depends on the structure of omarchy's `helix.toml` file. The module is prepared to integrate the theme, but the exact method may need adjustment based on testing with actual omarchy themes.

## Troubleshooting

### Theme not applied after switching

Applications load configuration at startup. Restart the application to see theme changes:

```bash
# Close and reopen Helix/Ghostty
```

### "Command not found" errors

The omarchy binaries are added to PATH via `home.sessionPath`. Reload your shell:

```bash
exec $SHELL
# or
source ~/.zshrc  # if using Zsh
```

### Broken symlink

If the theme symlink becomes broken, the activation script will automatically fix it on next rebuild:

```bash
home-manager switch
```

Or manually recreate it:

```bash
ln -sf ~/.config/omarchy/themes/default ~/.config/omarchy/current/theme
```

## Architecture

The module is organized into submodules for maintainability:

- **default.nix** - Main module with options and orchestration
- **binaries.nix** - Omarchy binary installation and PATH configuration
- **activation.nix** - Symlink management via home-manager activation script
- **terminal.nix** - Terminal application integration
- **desktop.nix** - Desktop theming stub (future Hyprland integration)

## Dependencies

**Required:**
- `programs.terminal-dev-environment` - For terminal application integration
- Omarchy source (configured as flake input)

**Optional:**
- Helix editor (`programs.terminal-dev-environment.tools.editor`)
- Ghostty terminal (`programs.terminal-dev-environment.tools.terminal`)

## Limitations

### Current Implementation

1. **Helix Integration**: Theme integration method may need adjustment based on actual omarchy theme structure
2. **Desktop Theming**: Desktop module is a stub - Hyprland theming not yet implemented
3. **Lazygit**: Not included in initial implementation (omarchy themes don't provide lazygit config)

### Design Constraints

- Theme switching requires application restart (no hot-reload)
- Installing custom themes requires network access and Git
- Themes must follow omarchy directory structure

## Future Work

- Complete Helix theme integration testing
- Implement Hyprland desktop theming
- Add Lazygit theme generation from color palette
- Support for additional terminal applications
- Theme preview/gallery functionality

## References

- [Omarchy GitHub Repository](https://github.com/basecamp/omarchy)
- [Specification](../../specs/010-theming/spec.md)
- [Implementation Plan](../../specs/010-theming/plan.md)
- [Research Notes](../../specs/010-theming/research.md)
