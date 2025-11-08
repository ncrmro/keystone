# Research: Dynamic Theming System

**Date**: 2025-11-07
**Feature**: 010-theming
**Purpose**: Technical discovery for implementing Omarchy-based theming in Keystone

## Overview

This document captures research findings for integrating the Omarchy theming standard into Keystone's terminal-dev-environment and providing architectural foundation for future desktop theming.

## 1. Omarchy Theme Structure

### Research Question
What is the complete structure of an Omarchy theme directory, and which files are required vs optional?

### Findings

An Omarchy theme is a directory containing application-specific configuration files. Based on analysis of the catppuccin theme:

**Required Files**: None (themes can be partial)

**Available Application Configurations**:
- `neovim.lua` - Neovim editor theme
- `helix.toml` - Helix editor theme (Keystone target)
- `ghostty.conf` - Ghostty terminal configuration (Keystone target)
- `alacritty.toml` - Alacritty terminal (not used in Keystone)
- `kitty.conf` - Kitty terminal (not used in Keystone)
- `btop.theme` - System monitor theme
- `mako.ini` - Notification daemon styling
- `hyprland.conf` - Hyprland compositor config
- `hyprlock.conf` - Hyprland lockscreen
- `waybar.css` - Status bar theme
- `walker.css` - Application launcher theme
- `swayosd.css` - On-screen display styling
- `vscode.json` - VS Code theme
- `chromium.theme` - Browser theme
- `icons.theme` - Icon theme definitions

**Additional Components**:
- `backgrounds/` - Directory of wallpaper images
- `preview.png` - Visual preview of theme

### Key Insight: Lazygit Configuration

**IMPORTANT**: Omarchy themes do NOT include a `lazygit.yml` or `lazygit.config` file. Lazygit configuration must be handled differently:

**Options**:
1. **Generate lazygit config from theme colors**: Parse helix.toml or another config to extract color palette and generate lazygit YAML
2. **Use lazygit's built-in theme support**: Lazygit has its own theme system - map Omarchy theme names to lazygit theme names
3. **Defer lazygit theming**: Implement only Helix and Ghostty initially (P1 requirement subset)

**Decision**: Defer lazygit theming to separate task. Initial implementation (MVP) will support Helix and Ghostty only, with lazygit theme generation added in follow-up work.

**Rationale**: Lazygit's theme format is incompatible with Omarchy's file-based approach. Generating config requires color parsing logic that adds significant complexity. Starting with 2/3 applications still delivers value.

### Decision

**Adopt Omarchy theme standard as-is** with graceful degradation for missing files:
- Applications check for their config file in active theme
- If file exists, include it in application configuration
- If missing, application uses its default theme
- No validation or enforcement of complete themes

### Alternatives Considered

1. **Create custom Keystone theme format**
   - Rejected: No ecosystem, maintenance burden, reinventing wheel
   - Omarchy has 12+ community themes ready to use

2. **Use base16 theme standard**
   - Rejected: Only handles colors, not full application configuration
   - Omarchy themes include non-color settings (fonts, layouts, etc.)

3. **Require complete themes with all supported app configs**
   - Rejected: Too rigid, prevents partial theming
   - Users should be able to theme subset of apps

## 2. NixOS Home Manager Integration Patterns

### Research Question
How should theme files and binaries be installed using home-manager? What activation patterns work best?

### Findings

**Binary Installation Pattern**:
```nix
home.file = builtins.listToAttrs (
  map (binFile: {
    name = ".local/share/omarchy/bin/${binFile}";
    value = {
      source = "${omarchySource}/bin/${binFile}";
      executable = true;
    };
  }) (builtins.attrNames (builtins.readDir "${omarchySource}/bin"))
);

home.sessionPath = [ "${config.home.homeDirectory}/.local/share/omarchy/bin" ];
```

**Theme Source Installation Pattern**:
```nix
home.file = {
  ".config/omarchy/themes/default" = {
    source = "${omarchySource}/themes/default";
    recursive = true;
  };
  ".local/share/omarchy/logo.txt" = {
    source = "${omarchySource}/logo.txt";
  };
};
```

**Activation Script Pattern** (for symlink creation):
```nix
home.activation.omarchy-theme-setup = lib.hm.dag.entryAfter ["writeBoundary"] ''
  # Create directories
  mkdir -p ${config.xdg.configHome}/omarchy/current

  # Create initial theme symlink if it doesn't exist
  if [ ! -L ${config.xdg.configHome}/omarchy/current/theme ]; then
    if [ -d ${config.xdg.configHome}/omarchy/themes/default ]; then
      ln -sf ${config.xdg.configHome}/omarchy/themes/default \
             ${config.xdg.configHome}/omarchy/current/theme
    fi
  fi
'';
```

### Key Insights

1. **DAG Ordering**: `entryAfter ["writeBoundary"]` ensures activation runs AFTER all files are written but before final setup
2. **Idempotency**: Check for symlink existence before creating (`if [ ! -L ... ]`)
3. **Relative Symlinks**: Use full paths in activation script for clarity
4. **Binary Discovery**: Use `builtins.readDir` for automatic binary enumeration (don't hardcode filenames)

### Decision

**Use activation script for initial symlink setup, preserve user changes on rebuild**

Implementation:
- Install theme sources via `home.file` (declarative)
- Install binaries via `home.file` with `executable = true`
- Create initial `current/theme` symlink via `home.activation`
- Never overwrite existing symlinks (allows user customization)

### Alternatives Considered

1. **Fully declarative symlink management**
   - Rejected: Would overwrite user theme choices on every rebuild
   - Breaks UX requirement for persistent theme selection

2. **SystemD user service for theme management**
   - Rejected: Overkill for one-time setup
   - Activation scripts are simpler and standard for home-manager

3. **Imperative user script (not managed by Nix)**
   - Rejected: Violates declarative infrastructure principle
   - Would require manual setup on new systems

## 3. Application Configuration Integration

### Research Question
How do Helix, Ghostty, and Lazygit load external theme configuration? What's the integration mechanism?

### Helix Integration

**Method**: Theme selection via `theme` setting in `config.toml`

```toml
theme = "catppuccin"  # References a built-in or runtime theme file
```

Helix searches for themes in:
1. Built-in themes (compiled into binary)
2. `~/.config/helix/themes/`
3. Runtime theme directories

**Omarchy Integration Strategy**:
- Omarchy provides `helix.toml` with theme configuration, NOT a helix theme file
- Approach: Use Nix to merge base helix config with Omarchy's helix.toml
- The Omarchy helix.toml likely contains color overrides and editor settings

**Alternative**: If Omarchy helix.toml is actually a theme file, symlink it to `~/.config/helix/themes/current.toml` and set `theme = "current"`

**Decision**: Test Omarchy helix.toml structure to determine if it's a theme file or config override, then use appropriate integration method.

### Ghostty Integration

**Method**: Configuration file inclusion via `config-file` directive

```
config-file = ~/.config/omarchy/current/ghostty.conf
```

**Omarchy Integration Strategy**:
- Ghostty supports loading additional config files
- Nix-managed base config at `~/.config/ghostty/config`
- Add `config-file` directive pointing to active Omarchy theme
- Theme settings layer on top of base configuration

**Decision**: Use Ghostty's `config-file` directive to include theme from `~/.config/omarchy/current/ghostty.conf`

### Lazygit Integration

**Problem**: Omarchy themes don't include lazygit configuration

**Research Findings**:
- Lazygit uses YAML configuration at `~/.config/lazygit/config.yml`
- Lazygit has built-in theme system separate from file-based config
- No standard mapping between Omarchy themes and lazygit themes

**Options**:
1. Generate lazygit config from Omarchy theme colors (complex, requires color parsing)
2. Map Omarchy theme names to lazygit built-in themes (limited, fragile)
3. Defer lazygit theming to future work (pragmatic)

**Decision**: DEFER lazygit theming - not in MVP scope
- Reduces complexity significantly
- Helix + Ghostty still deliver cohesive terminal experience (2/3 applications)
- Lazygit theming can be added later with proper color extraction logic
- Update spec to reflect Helix + Ghostty as P1, Lazygit as P2/P3

### Decision Summary

**Immediate Implementation** (P1):
- Helix: Merge/include Omarchy helix.toml (method TBD based on file structure)
- Ghostty: Use `config-file` directive to include theme

**Deferred** (P2):
- Lazygit: Requires color extraction and config generation

### Alternatives Considered

1. **Implement all three applications immediately**
   - Rejected: Lazygit integration is complex, delays MVP
   - Delivering 2/3 apps provides value sooner

2. **Skip Omarchy entirely for lazygit, use manual config**
   - Rejected: Inconsistent UX, users would have mismatched themes
   - Better to defer than ship half-working feature

## 4. Omarchy Binary Behavior

### Research Question
What do the omarchy management binaries actually do? How do they manipulate filesystem state?

### omarchy-theme-next

**Behavior**:
1. Lists themes in `~/.config/omarchy/themes/` (alphabetical)
2. Reads current theme from `~/.config/omarchy/current/theme` symlink
3. Finds next theme (with wrap-around)
4. Updates `current/theme` symlink to point to new theme
5. Sends desktop notification

**Implementation**: Pure bash script, no dependencies beyond coreutils and notify-send

**Key Insight**: Entirely safe to use as-is - no privileged operations, only symlink manipulation

### omarchy-theme-install

**Behavior**:
1. Accepts git repository URL
2. Extracts theme name from URL (removes "omarchy-" prefix, "-theme" suffix)
3. Clones repository to `~/.config/omarchy/themes/<theme-name>/`
4. Removes existing theme with same name (if present)
5. Calls `omarchy-theme-set` to activate new theme

**Dependencies**: git, standard shell utilities

**Key Insight**: Requires network access and git. Works as-is in NixOS environment.

### omarchy-theme-set

**Behavior**:
1. Accepts theme name as argument
2. Validates theme exists in `~/.config/omarchy/themes/`
3. Updates `current/theme` symlink to selected theme
4. Sends desktop notification

**Key Insight**: Simple symlink update, works perfectly with our architecture

### Decision

**Use Omarchy binaries unmodified**:
- Install all binaries from omarchy source via `home.file`
- Add bin directory to PATH via `home.sessionPath`
- No patching or wrapping needed
- Scripts are simple, well-tested, and safe

### Alternatives Considered

1. **Reimplement theme management in Nix**
   - Rejected: Reinventing wheel, loses upstream improvements
   - Omarchy scripts are stable and well-designed

2. **Wrap omarchy scripts with Nix-aware versions**
   - Rejected: Unnecessary complexity
   - Scripts already do exactly what we need

## 5. Desktop Module Architecture

### Research Question
How should the desktop theming module be structured to support future Hyprland integration without implementing it now?

### Findings

**Hyprland Theme Configuration**:
- Hyprland uses `hyprland.conf` for configuration
- Omarchy themes include `hyprland.conf`, `hyprlock.conf`, `waybar.css`, etc.
- Same pattern as terminal apps: include theme files in compositor config

**Desktop Module Requirements** (from spec):
- Must be enableable without errors
- Must provide access to active Omarchy theme path
- Must not implement full theming (stub only)

### Decision

**Create minimal desktop.nix module**:
```nix
{ config, lib, ... }:

let
  cfg = config.programs.omarchy-theming.desktop;
  themingCfg = config.programs.omarchy-theming;
in
{
  options.programs.omarchy-theming.desktop = {
    enable = lib.mkEnableOption "desktop theming (Hyprland)";
  };

  config = lib.mkIf (themingCfg.enable && cfg.enable) {
    # Stub: No implementation yet
    # Future: Hyprland config inclusion, waybar theming, etc.

    # Expose theme path for manual use
    home.sessionVariables.OMARCHY_THEME_PATH =
      "${config.xdg.configHome}/omarchy/current/theme";
  };
}
```

**Rationale**:
- Satisfies "must be enableable" requirement
- Provides environment variable for future integration
- No risk of breaking existing desktop setup
- Clear TODO markers for future work

### Alternatives Considered

1. **Implement full Hyprland theming immediately**
   - Rejected: Out of scope per spec, delays MVP
   - Desktop theming is P3, not needed for terminal workflow

2. **Skip desktop module entirely**
   - Rejected: Spec explicitly requires architectural foundation
   - Module structure establishes pattern for future work

## Implementation Priority

Based on research findings, recommended implementation order:

### Phase 1: Foundation (P1)
1. Omarchy binary installation
2. Default theme installation
3. Activation script for initial symlink setup
4. PATH configuration

### Phase 2: Terminal Integration (P1)
5. Helix theme integration
6. Ghostty theme integration
7. Extension of terminal-dev-environment module

### Phase 3: Desktop Stub (P3)
8. Desktop module creation
9. Environment variable exposure

### Phase 4: Deferred (P2)
10. Lazygit theme generation and integration

## Open Questions

1. **Helix theme file format**: Need to inspect actual Omarchy helix.toml to determine integration method
   - **Resolution approach**: Test with catppuccin theme, check file structure
   - **Fallback**: If unclear, use simple file inclusion and rely on Helix's config merging

2. **Theme directory enumeration**: Should we pre-install multiple Omarchy themes or just default?
   - **Research needed**: Check if Omarchy source includes all 12 themes or just infrastructure
   - **Fallback**: Install only default theme, users can install more via omarchy-theme-install

3. **Notification requirements**: Do theme-next/theme-set notifications require specific desktop environment?
   - **Resolution**: Test in Keystone client environment, may need notify-send package
   - **Fallback**: Notifications are nice-to-have, not critical for functionality

## References

- [Omarchy GitHub Repository](https://github.com/basecamp/omarchy)
- [Omarchy-Nix Reference Implementation](https://github.com/ncrmro/omarchy-nix/blob/feat/submodule-omarchy-arch/modules/home-manager/omarchy-defaults.nix)
- [Helix Configuration Documentation](https://docs.helix-editor.com/configuration.html)
- [Ghostty Configuration Guide](https://ghostty.org/docs/config)
- [Home Manager Manual - Activation Scripts](https://nix-community.github.io/home-manager/index.xhtml#sec-activation-scripts)

## Conclusion

Research confirms that:
1. Omarchy theme standard is well-suited for Keystone integration
2. Home-manager provides appropriate patterns for theme installation and activation
3. Helix and Ghostty have clear integration paths
4. Lazygit theming should be deferred due to complexity
5. Desktop module can be implemented as stub for future work

All technical unknowns from plan.md Technical Context section have been resolved. Proceeding to Phase 1 (data model and contracts).
