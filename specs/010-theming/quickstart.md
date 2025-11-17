# Quickstart: Dynamic Theming System

**Feature**: 010-theming
**Audience**: Keystone users who want to enable unified theming
**Time to Complete**: 5-10 minutes

## What You'll Get

After following this guide, you'll have:
- Consistent visual styling across Helix editor and Ghostty terminal
- The default Omarchy theme applied to all supported applications
- Commands to quickly switch between themes (`omarchy-theme-next`)
- Ability to install community themes from Git repositories

## Prerequisites

- Keystone system with home-manager configured
- `programs.terminal-dev-environment.enable = true` in your configuration
- At minimum, Helix or Ghostty enabled in terminal-dev-environment

## Step 1: Add Omarchy Flake Input

Edit your `flake.nix` to add the Omarchy repository as an input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager.url = "github:nix-community/home-manager/release-25.05";

    # Add this:
    omarchy.url = "github:basecamp/omarchy";
    omarchy.flake = false;  # Omarchy is not a flake, treat as source
  };

  outputs = { nixpkgs, home-manager, omarchy, ... }: {
    # ... your existing outputs
  };
}
```

**Note**: Replace `github:basecamp/omarchy` with the actual Omarchy repository URL once confirmed.

## Step 2: Pass Omarchy to Home Manager Module

Update your home-manager configuration to provide the omarchy input:

```nix
{
  home-manager.users.youruser = { config, pkgs, ... }: {
    # Pass omarchy source to the module
    programs.omarchy-theming = {
      enable = true;
      package = omarchy;  # Reference the flake input
    };

    # Your existing terminal-dev-environment config
    programs.terminal-dev-environment = {
      enable = true;
      # ... other settings
    };
  };
}
```

## Step 3: Rebuild Your System

Apply the configuration changes:

```bash
# If using NixOS system configuration
sudo nixos-rebuild switch

# Or if using standalone home-manager
home-manager switch
```

**What happens during rebuild:**
- Omarchy binaries installed to `~/.local/share/omarchy/bin/`
- Default theme files installed to `~/.config/omarchy/themes/default/`
- Active theme symlink created at `~/.config/omarchy/current/theme`
- Helix and Ghostty configured to load theme settings

## Step 4: Verify Installation

Check that theming is active:

```bash
# Verify omarchy commands are in PATH
which omarchy-theme-next
# Should output: /home/youruser/.local/share/omarchy/bin/omarchy-theme-next

# Check installed themes
ls ~/.config/omarchy/themes/
# Should output: default

# Check active theme
readlink ~/.config/omarchy/current/theme
# Should output: ../themes/default or full path to default theme
```

## Step 5: Test Theme in Applications

### Test Helix
```bash
# Open a file in Helix
hx ~/.bashrc

# You should see the default Omarchy theme colors
# (darker background, specific syntax highlighting colors)
```

### Test Ghostty
```bash
# Launch a new Ghostty terminal instance
# (or restart if already running)

# You should see themed colors for:
# - Background/foreground
# - Cursor
# - Selection
# - ANSI color palette
```

## Step 6: Switch Themes (Optional)

Try cycling through available themes:

```bash
# Install a community theme
omarchy-theme-install https://github.com/catppuccin/omarchy-catppuccin
# (Replace with actual theme repository URL)

# Cycle to next theme
omarchy-theme-next

# You should see a desktop notification: "Theme set to catppuccin"

# Restart Helix/Ghostty to see the new theme applied
```

## Common Issues and Solutions

### Issue: "omarchy-theme-next: command not found"

**Cause**: PATH not updated or shell not restarted

**Solution**:
```bash
# Reload your shell configuration
exec $SHELL

# Or manually add to current session
export PATH="$HOME/.local/share/omarchy/bin:$PATH"
```

### Issue: Helix/Ghostty not showing theme changes

**Cause**: Applications load config only at startup

**Solution**:
```bash
# Restart the application after switching themes
# Close all Helix/Ghostty instances and relaunch
```

### Issue: "Theme directory not found" warnings during rebuild

**Cause**: Omarchy source doesn't have expected structure

**Solution**:
```bash
# Verify omarchy flake input structure
nix flake show path/to/omarchy

# Check that omarchy source contains:
# - bin/ directory
# - themes/default/ directory
# - logo.txt file
```

### Issue: Theme symlink is broken after rebuild

**Cause**: Theme directory was removed or renamed

**Solution**:
```bash
# Manually recreate symlink to default theme
ln -sf ~/.config/omarchy/themes/default ~/.config/omarchy/current/theme

# Or rebuild to let activation script fix it
home-manager switch
```

## Next Steps

### Install Additional Themes

Browse community themes and install your favorites:

```bash
# Example theme installations (URLs may vary)
omarchy-theme-install https://github.com/rose-pine/omarchy-rose-pine
omarchy-theme-install https://github.com/catppuccin/omarchy-catppuccin
omarchy-theme-install https://github.com/nordtheme/omarchy-nord

# List installed themes
ls ~/.config/omarchy/themes/

# Set specific theme
omarchy-theme-set rose-pine
```

### Customize Theme Behavior

Edit your configuration to customize which applications use theming:

```nix
programs.omarchy-theming = {
  enable = true;

  terminal = {
    enable = true;
    applications = {
      helix = true;    # Theme Helix
      ghostty = false; # Don't theme Ghostty (use its defaults)
    };
  };
};
```

### Enable Desktop Theming (Future)

When Hyprland theming is implemented, enable it:

```nix
programs.omarchy-theming = {
  enable = true;

  terminal.enable = true;

  # This will theme Hyprland, waybar, etc. (NOT YET IMPLEMENTED)
  desktop.enable = true;
};
```

### Create Your Own Theme

Fork an existing theme and customize:

```bash
# Clone a theme repository
git clone https://github.com/basecamp/omarchy my-custom-theme
cd my-custom-theme/themes/default

# Edit theme files
vim helix.toml    # Customize Helix colors
vim ghostty.conf  # Customize Ghostty colors

# Create a new theme directory
mkdir ../my-theme
cp helix.toml ../my-theme/
cp ghostty.conf ../my-theme/

# Create a repository and push
git init
git add .
git commit -m "My custom Omarchy theme"
git remote add origin https://github.com/yourusername/omarchy-my-theme
git push -u origin main

# Install your custom theme
omarchy-theme-install https://github.com/yourusername/omarchy-my-theme
```

## Configuration Reference

### Minimal Configuration

```nix
{
  programs.omarchy-theming.enable = true;
}
```

### Full Configuration with All Options

```nix
{
  programs.omarchy-theming = {
    enable = true;

    # Optional: override package source
    package = omarchy;

    terminal = {
      enable = true;
      applications = {
        helix = true;
        ghostty = true;
      };
    };

    desktop = {
      enable = false;  # Stub - not yet implemented
    };
  };
}
```

### Integration with terminal-dev-environment

```nix
{
  programs.terminal-dev-environment = {
    enable = true;
    tools = {
      editor = true;     # Required for Helix theming
      terminal = true;   # Required for Ghostty theming
      git = true;
      shell = true;
    };
  };

  programs.omarchy-theming = {
    enable = true;
    # Automatically integrates with enabled tools above
  };
}
```

## Understanding Theme Persistence

**Important**: Your theme choice persists across system rebuilds!

```bash
# Select a theme
omarchy-theme-set catppuccin

# Rebuild your system
nixos-rebuild switch

# Your theme is STILL catppuccin (not reset to default)
```

**How it works:**
- Nix manages theme **sources** (the files in `~/.config/omarchy/themes/`)
- You manage theme **selection** (the symlink at `~/.config/omarchy/current/theme`)
- The symlink is created once during initial activation, then preserved forever
- You can change themes freely without touching your Nix configuration

**To reset to default theme:**
```bash
# Manually update symlink
ln -sf ~/.config/omarchy/themes/default ~/.config/omarchy/current/theme

# Or use omarchy command
omarchy-theme-set default
```

## Getting Help

- **Module Documentation**: See `docs/modules/omarchy-theming.md` in Keystone repository
- **Omarchy Documentation**: Visit omarchy.org (if available) or GitHub repository
- **Keystone Issues**: Report problems at https://github.com/ncrmro/keystone/issues
- **Community Themes**: Browse GitHub for "omarchy-" or "omarchy-theme-" repositories

## Summary

You've successfully enabled Omarchy theming! Key takeaways:

✅ Unified visual styling across terminal applications
✅ Easy theme switching with `omarchy-theme-next`
✅ Access to 12+ community themes via `omarchy-theme-install`
✅ Theme preferences persist across system rebuilds
✅ Graceful degradation if theme files are missing

Enjoy your beautifully themed terminal environment!
