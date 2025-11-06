# Data Model: Terminal Development Environment Module

**Date**: 2025-11-05
**Status**: Design Phase

## Overview

This document defines the configuration data model for the terminal-dev-environment home-manager module. Since this is a configuration module (not a data-driven application), the "data model" describes the NixOS option schema that users interact with.

---

## Module Options Schema

### Top-Level Configuration

```nix
programs.terminal-dev-environment = {
  enable = boolean;      # Master enable switch
  tools = { ... };       # Tool category toggles
  extraPackages = [ ];   # Additional packages
  # Tool-specific configurations delegated to sub-modules
};
```

---

## Entity: TerminalDevEnvironment

**Description**: The top-level configuration entity representing the complete terminal development environment.

### Attributes

| Attribute | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `enable` | `boolean` | `false` | Yes | Master switch to enable/disable the entire environment |
| `tools` | `ToolsConfig` | `{}` | No | Configuration for which tool categories to enable |
| `extraPackages` | `list[Package]` | `[]` | No | Additional packages to include in the environment |

### Relationships

- **Contains** multiple `ToolConfig` entities (git, helix, zsh, zellij, lazygit, ghostty)
- **Depends on** nixpkgs package set
- **Integrates with** home-manager module system

---

## Entity: ToolsConfig

**Description**: Category-based toggles for enabling/disabling groups of tools.

### Attributes

| Attribute | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `git` | `boolean` | `true` | No | Enable Git version control and UI tools (git, lazygit) |
| `editor` | `boolean` | `true` | No | Enable Helix text editor with language servers |
| `shell` | `boolean` | `true` | No | Enable Zsh shell with productivity utilities |
| `multiplexer` | `boolean` | `true` | No | Enable Zellij terminal multiplexer |
| `terminal` | `boolean` | `true` | No | Enable Ghostty terminal emulator |

### Validation Rules

- All tool toggles default to `true` when parent `enable = true`
- Individual toggles can be set to `false` to disable specific tools
- Disabling all tools while `enable = true` is valid (only installs extraPackages)

---

## Entity: GitConfig

**Description**: Git version control system configuration.

### Attributes

| Attribute | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `enable` | `boolean` | inherited | No | Enable Git (controlled by `tools.git`) |
| `enableLfs` | `boolean` | `true` | No | Enable Git Large File Storage support |
| `enableLazygit` | `boolean` | `true` | No | Enable lazygit TUI for Git operations |
| `aliases` | `attrset[string]` | see below | No | Git command aliases |

### Default Aliases

```nix
{
  s = "switch";
  f = "fetch";
  p = "pull";
  b = "branch";
  st = "status -sb";
  co = "checkout";
  c = "commit";
}
```

### Notes

- User identity (`userName`, `userEmail`) must be configured separately via `programs.git`
- SSH signing configuration is optional and user-managed
- Module provides sensible defaults but does not enforce identity

---

## Entity: HelixConfig

**Description**: Helix modal text editor configuration with language server support.

### Attributes

| Attribute | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `enable` | `boolean` | inherited | No | Enable Helix editor (controlled by `tools.editor`) |
| `package` | `package` | `pkgs.helix` | No | Helix package to install |
| `theme` | `string` | `"default"` | No | Editor color theme |
| `settings` | `attrset` | see below | No | Editor settings (see Helix documentation) |
| `languageServers` | `list[Package]` | see below | No | Language server packages to install |

### Default Language Servers

```nix
[
  pkgs.nixfmt                              # Nix formatting
  pkgs.bash-language-server                # Shell scripts
  pkgs.yaml-language-server                # YAML files
  pkgs.dockerfile-language-server-nodejs   # Dockerfile
  pkgs.vscode-langservers-extracted        # JSON, CSS, HTML
  pkgs.marksman                            # Markdown
]
```

### Default Settings

```nix
{
  editor = {
    line-number = "relative";
    mouse = true;
    cursor-shape = {
      insert = "bar";
      normal = "block";
      select = "underline";
    };
  };
}
```

### Environment Variables

Sets `EDITOR=hx` and `VISUAL=hx` when enabled.

---

## Entity: ZshConfig

**Description**: Zsh shell configuration with oh-my-zsh, starship prompt, and productivity tools.

### Attributes

| Attribute | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `enable` | `boolean` | inherited | No | Enable Zsh shell (controlled by `tools.shell`) |
| `enableOhMyZsh` | `boolean` | `true` | No | Enable oh-my-zsh framework |
| `enableStarship` | `boolean` | `true` | No | Enable starship cross-shell prompt |
| `enableZoxide` | `boolean` | `true` | No | Enable zoxide smart directory navigation |
| `enableDirenv` | `boolean` | `true` | No | Enable direnv for automatic environment loading |
| `shellAliases` | `attrset[string]` | see below | No | Shell command aliases |
| `ohMyZshPlugins` | `list[string]` | `["git"]` | No | Oh-my-zsh plugins to enable |
| `ohMyZshTheme` | `string` | `"robbyrussell"` | No | Oh-my-zsh theme |

### Default Shell Aliases

```nix
{
  l = "eza -1l";
  ls = "eza -1l";
  grep = "rg";
  g = "git";
  lg = "lazygit";
  hx = "helix";
}
```

### Integrations

- Zoxide: Activated with `z <directory>` command and zsh integration
- Direnv: Automatically loads `.envrc` files, zsh integration enabled
- Starship: Provides git-aware prompt with execution time and context

---

## Entity: ZellijConfig

**Description**: Zellij terminal multiplexer configuration.

### Attributes

| Attribute | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `enable` | `boolean` | inherited | No | Enable Zellij (controlled by `tools.multiplexer`) |
| `package` | `package` | `pkgs.zellij` | No | Zellij package to install |
| `theme` | `string` | `"tokyo-night-dark"` | No | UI theme |
| `settings` | `attrset` | see below | No | Zellij configuration options |

### Default Settings

```nix
{
  theme = "tokyo-night-dark";
  startup_tips = false;
}
```

### Notes

- Zsh integration deliberately disabled (`enableZshIntegration = false`) to avoid automatic session nesting
- Users manually launch zellij when needed
- Configuration written to `$XDG_CONFIG_HOME/zellij/config.kdl`

---

## Entity: LazygitConfig

**Description**: Lazygit terminal UI for Git operations.

### Attributes

| Attribute | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `enable` | `boolean` | inherited | No | Enable lazygit (controlled by `git.enableLazygit`) |
| `package` | `package` | `pkgs.lazygit` | No | Lazygit package to install |

### Notes

- Minimal configuration - uses lazygit defaults
- Inherits Git configuration from `programs.git`
- Launched with `lg` alias or `lazygit` command

---

## Entity: GhosttyConfig

**Description**: Ghostty GPU-accelerated terminal emulator configuration.

### Attributes

| Attribute | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `enable` | `boolean` | inherited | No | Enable Ghostty (controlled by `tools.terminal`) |
| `package` | `package` | `pkgs.ghostty` | No | Ghostty package to install |
| `enableZshIntegration` | `boolean` | `true` | No | Enable Ghostty-specific zsh shell integration |
| `settings` | `attrset` | `{}` | No | Ghostty configuration (see Ghostty documentation) |

### Example Settings

```nix
{
  theme = "catppuccin-mocha";
  font-family = "JetBrainsMono Nerd Font";
  font-size = 12;
}
```

### Notes

- Configuration written to `$XDG_CONFIG_HOME/ghostty/config`
- Shell integration provides enhanced terminal features
- Can be set as default terminal via `$TERMINAL` environment variable

---

## Configuration Validation Rules

### Assertions

1. **Tool Consistency**: If `tools.git = false`, then `git.enableLazygit` has no effect
2. **Editor Availability**: If `tools.editor = false`, `EDITOR` environment variable not set by module
3. **Shell Integration**: Shell integrations require parent tool to be enabled
   - `ghostty.enableZshIntegration` requires `tools.shell = true`
   - Zoxide/direnv integrations require `tools.shell = true`

### Type Safety

All options use explicit Nix types:
- `lib.types.bool` for boolean flags
- `lib.types.str` for string values
- `lib.types.package` for package references
- `lib.types.listOf lib.types.package` for package lists
- `lib.types.attrsOf lib.types.str` for key-value configurations

---

## Example Configuration

### Minimal (All Defaults)

```nix
{
  programs.terminal-dev-environment.enable = true;

  # User must still configure git identity
  programs.git = {
    userName = "Jane Developer";
    userEmail = "jane@example.com";
  };
}
```

This enables all tools with default settings.

### Test User Configuration (for bin/test-home-manager)

```nix
# vms/test-server/home-manager/home.nix
# Used by bin/test-home-manager script for automated testing
{ config, pkgs, ... }:
{
  imports = [ /home/ncrmro/code/ncrmro/keystone/home-manager/modules/terminal-dev-environment ];

  programs.terminal-dev-environment.enable = true;

  programs.git = {
    userName = "Test User";
    userEmail = "testuser@keystone-test-vm";
  };
}
```

This configuration is used by the bin/test-home-manager self-contained test script which:
- Installs home-manager for testuser via nix-channel
- Copies config to testuser's ~/.config/home-manager/
- Runs `home-manager switch` as testuser
- Verifies all tools installed and functional
- Returns exit code 0 on success, 1 on failure (fails bin/test-deployment if verification fails)

**Automated Verification Checks:**
- Home-manager successfully installed for testuser
- All tools in PATH: helix, git, zsh, zellij, lazygit, ghostty
- Zsh is testuser's default shell ($SHELL check)
- Helix LSPs functional (nixfmt, bash-language-server, etc.)
- Lazygit launches successfully
- Zellij starts with configured theme (tokyo-night-dark)
- Shell aliases work: lg, hx, g
- Starship prompt active in zsh
- Zoxide navigation functional

### Customized (Selective Tools)

```nix
{
  programs.terminal-dev-environment = {
    enable = true;

    # Disable terminal multiplexer
    tools.multiplexer = false;

    # Add custom packages
    extraPackages = with pkgs; [
      ripgrep
      fd
      bat
    ];
  };

  # Override helix theme
  programs.helix.settings.theme = "gruvbox";

  # Override zsh aliases
  programs.zsh.shellAliases = {
    vim = "helix";
    vi = "helix";
  };

  programs.git = {
    userName = "Jane Developer";
    userEmail = "jane@example.com";
  };
}
```

### Advanced (Fine-grained Control)

```nix
{
  programs.terminal-dev-environment = {
    enable = true;

    # Use only specific tools
    tools = {
      git = true;
      editor = true;
      shell = false;      # Custom shell setup
      multiplexer = false;
      terminal = false;   # Using different terminal
    };
  };

  # Completely custom helix configuration
  programs.helix = {
    enable = true;  # Redundant when tools.editor = true, but explicit
    settings = {
      theme = "nord";
      editor = {
        line-number = "absolute";
        soft-wrap.enable = true;
      };
    };
  };

  programs.git = {
    userName = "Jane Developer";
    userEmail = "jane@example.com";
    signing = {
      signByDefault = true;
      key = "~/.ssh/id_ed25519";
    };
  };
}
```

---

## State Transitions

Since this is a declarative configuration system, there are no runtime state transitions. However, we can describe the evaluation flow:

```
User Configuration (programs.terminal-dev-environment.enable = true)
  ↓
Module Evaluation (lib.mkIf cfg.enable)
  ↓
Tool Configuration Generation
  ├─→ Git configuration      (if tools.git = true)
  ├─→ Helix configuration    (if tools.editor = true)
  ├─→ Zsh configuration      (if tools.shell = true)
  ├─→ Zellij configuration   (if tools.multiplexer = true)
  └─→ Ghostty configuration  (if tools.terminal = true)
  ↓
Home-Manager Build
  ↓
System Activation
  ↓
User Shell Environment (all tools available)
```

---

## Module Dependencies

### Required Inputs

- `config`: Home-manager configuration state
- `lib`: Nixpkgs library functions
- `pkgs`: Nixpkgs package set (25.05 stable)

### Optional Inputs

- Custom package overlays for alternative versions
- User-provided theme files or configurations

### Exports

The module exports configured programs and environment to:
- `$PATH`: All tool binaries
- `$EDITOR` / `$VISUAL`: Set to `hx` (helix)
- `$XDG_CONFIG_HOME`: Tool configuration files
- Shell environment: Aliases, functions, integrations

---

## Summary

The terminal-dev-environment module provides a declarative configuration schema for a cohesive set of development tools. The data model emphasizes:

1. **Simplicity**: Single `enable` for complete environment
2. **Flexibility**: Individual tool toggles for granular control
3. **Overrideability**: All defaults use `lib.mkDefault` for easy user overrides
4. **Type Safety**: Explicit types prevent configuration errors
5. **Composability**: Integrates cleanly with other home-manager modules
