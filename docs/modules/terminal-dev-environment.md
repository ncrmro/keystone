# Terminal Development Environment Module

A composable home-manager module that provides an opinionated, cohesive terminal development stack for Keystone users.

## Overview

The `terminal-dev-environment` module installs and configures a complete set of terminal-based development tools:

- **Helix** - Modal text editor with language servers (Nix, Bash, YAML, JSON, Dockerfile, Markdown)
- **Git** - Version control with sensible aliases and LFS support
- **Lazygit** - Beautiful terminal UI for Git operations
- **Zsh** - Modern shell with oh-my-zsh, auto-suggestions, and syntax highlighting
- **Starship** - Fast, customizable prompt showing git status and context
- **Zoxide** - Smart directory navigation that learns your habits
- **Direnv** - Automatic environment loading for project-specific setups
- **Zellij** - Terminal multiplexer with tabs and panes
- **Ghostty** - GPU-accelerated terminal emulator with Wayland support

## Quick Start

### Minimal Configuration

```nix
{
  imports = [ <keystone>/home-manager/modules/terminal-dev-environment ];

  programs.terminal-dev-environment.enable = true;

  # Required: Configure your git identity
  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";
  };
}
```

Then rebuild:
```bash
home-manager switch
```

All tools will be available immediately.

## Module Options

### `programs.terminal-dev-environment.enable`

- **Type**: `boolean`
- **Default**: `false`
- **Description**: Master switch to enable/disable the entire environment

### `programs.terminal-dev-environment.tools`

Individual toggles for tool categories (all default to `true` when module is enabled):

- `git` - Git version control and lazygit UI
- `editor` - Helix text editor with language servers
- `shell` - Zsh with starship, zoxide, direnv integrations
- `multiplexer` - Zellij terminal multiplexer
- `terminal` - Ghostty terminal emulator

### `programs.terminal-dev-environment.extraPackages`

- **Type**: `listOf package`
- **Default**: `[]`
- **Description**: Additional packages to include in the environment
- **Example**: `[ pkgs.ripgrep pkgs.fd pkgs.bat ]`

## Customization Examples

### Disable Specific Tools

```nix
{
  programs.terminal-dev-environment = {
    enable = true;
    tools.multiplexer = false;  # Don't install zellij
    tools.terminal = false;     # Using different terminal
  };
}
```

### Override Tool Configurations

All tool configurations use `lib.mkDefault`, so you can override any setting:

```nix
{
  programs.terminal-dev-environment.enable = true;

  # Override helix theme
  programs.helix.settings.theme = "gruvbox";

  # Add custom zsh aliases
  programs.zsh.shellAliases = {
    vim = "helix";
    cat = "bat";
  };

  # Configure git SSH signing
  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";
    signing = {
      signByDefault = true;
      key = "~/.ssh/id_ed25519";
    };
    extraConfig.gpg.format = "ssh";
  };
}
```

### Add Extra Packages

```nix
{
  programs.terminal-dev-environment = {
    enable = true;
    extraPackages = with pkgs; [
      ripgrep
      fd
      bat
      docker
      kubectl
    ];
  };
}
```

## Integration with Keystone Client

Use with Keystone's Hyprland desktop:

```nix
{
  imports = [
    <keystone>/modules/client
    <keystone>/home-manager/modules/terminal-dev-environment
  ];

  keystone.client.enable = true;
  programs.terminal-dev-environment.enable = true;

  # Set ghostty as default terminal for Hyprland
  home.sessionVariables.TERMINAL = "ghostty";
}
```

## Headless Server Usage

For servers without GUI:

```nix
{
  programs.terminal-dev-environment = {
    enable = true;
    tools.terminal = false;  # No GUI terminal emulator
  };
}
```

## Tool Reference

### Helix Editor

**Environment Variables**:
- `EDITOR=hx`
- `VISUAL=hx`

**Key Bindings** (normal mode):
- `i` - Insert mode
- `Esc` - Normal mode
- `:w` - Save
- `:q` - Quit
- `Space f` - File picker
- `gd` - Go to definition (LSP)

### Git Aliases

```bash
git s    # git switch
git f    # git fetch
git p    # git pull
git b    # git branch
git st   # git status -sb
git co   # git checkout
git c    # git commit
```

### Shell Aliases

```bash
l       # eza -1l
ls      # eza -1l
grep    # rg (ripgrep)
g       # git
lg      # lazygit
hx      # helix
```

### Zoxide Navigation

```bash
# After visiting directories normally
cd ~/code/keystone
cd ~/documents/notes

# Jump with partial names
z keystone   # Jumps to ~/code/keystone
z notes      # Jumps to ~/documents/notes
```

### Direnv Auto-loading

```bash
# Create .envrc in your project
echo 'use flake' > .envrc
direnv allow

# Environment loads automatically when you cd into the directory
```

## Troubleshooting

### Helix language servers not working

Verify language servers are installed:
```bash
which bash-language-server yaml-language-server nil nixfmt
```

Check Helix health for a specific language:
```bash
hx --health nix
```

### Zsh completions not working

Regenerate completions:
```bash
rm -rf ~/.cache/zsh
exec zsh
```

### Git signing fails

Ensure SSH key exists:
```bash
ls -la ~/.ssh/id_ed25519
ssh-add -L
```

## See Also

- [Quickstart Guide](../../specs/008-terminal-dev-environment/quickstart.md) - Detailed usage guide
- [Data Model](../../specs/008-terminal-dev-environment/data-model.md) - Complete option schema
- [Research](../../specs/008-terminal-dev-environment/research.md) - Design decisions
