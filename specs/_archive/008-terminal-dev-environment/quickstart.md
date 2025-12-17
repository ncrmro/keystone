# Quickstart: Terminal Development Environment Module

**Target Audience**: Keystone users who want a complete terminal-based development setup
**Time to Setup**: 5-10 minutes
**Prerequisites**: NixOS 25.05 with home-manager configured

---

## What You Get

A fully configured terminal development environment including:

- **Helix** - Modal text editor with language servers for Nix, Bash, YAML, JSON, Dockerfile, Markdown
- **Git** - Version control with sensible aliases and optional SSH signing
- **Lazygit** - Beautiful terminal UI for Git operations
- **Zsh** - Modern shell with oh-my-zsh, auto-suggestions, and syntax highlighting
- **Starship** - Fast, customizable prompt showing git status and context
- **Zoxide** - Smart directory navigation that learns your habits
- **Direnv** - Automatic environment loading for project-specific setups
- **Zellij** - Terminal multiplexer with tabs and panes
- **Ghostty** - GPU-accelerated terminal emulator with Wayland support

---

## Quick Start (3 Steps)

### Step 1: Add Module to Your Configuration

```nix
# In your home-manager configuration
{
  imports = [
    <keystone>/home-manager/modules/terminal-dev-environment
  ];

  programs.terminal-dev-environment.enable = true;

  # Required: Configure your git identity
  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";
  };
}
```

### Step 2: Rebuild

```bash
home-manager switch
# or
nixos-rebuild switch  # if using system-level home-manager
```

### Step 3: Start Using

```bash
# Open a new terminal or reload shell
exec zsh

# Try the tools
hx README.md          # Open file in Helix
lg                    # Launch Lazygit
zellij                # Start terminal multiplexer
z projects/keystone   # Smart navigation with zoxide (after cd'ing around)
```

---

## Customization Examples

### Example 1: Minimal Setup (Just Editor + Git)

```nix
{
  programs.terminal-dev-environment = {
    enable = true;

    # Disable tools you don't need
    tools = {
      git = true;
      editor = true;
      shell = false;       # Use your own shell setup
      multiplexer = false; # Don't use zellij
      terminal = false;    # Using different terminal
    };
  };

  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";
  };
}
```

### Example 2: Full Setup with Customizations

```nix
{
  programs.terminal-dev-environment = {
    enable = true;
    # All tools enabled by default

    # Add extra packages
    extraPackages = with pkgs; [
      ripgrep
      fd
      bat
      eza
    ];
  };

  # Override helix theme
  programs.helix.settings.theme = "gruvbox";

  # Add custom zsh aliases
  programs.zsh.shellAliases = {
    vim = "helix";
    cat = "bat";
    find = "fd";
  };

  # Configure git with SSH signing
  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";
    signing = {
      signByDefault = true;
      key = "~/.ssh/id_ed25519";
    };
    extraConfig = {
      gpg.format = "ssh";
    };
  };

  # Customize ghostty terminal
  programs.ghostty.settings = {
    theme = "catppuccin-mocha";
    font-family = "JetBrainsMono Nerd Font";
    font-size = 13;
  };
}
```

### Example 3: Server Setup (No GUI Terminal)

```nix
{
  programs.terminal-dev-environment = {
    enable = true;

    # Disable GUI terminal for headless server
    tools.terminal = false;
  };

  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";
  };
}
```

---

## Using with Keystone Client Module

The terminal development environment works seamlessly with Keystone's Hyprland desktop:

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

  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";
  };
}
```

Now pressing `Super+Enter` in Hyprland will open Ghostty with your configured shell.

---

## Tool Reference

### Helix Editor

**Open files:**
```bash
hx filename.md
hx src/main.rs
```

**Key bindings (normal mode):**
- `i` - Enter insert mode
- `Esc` - Return to normal mode
- `Return` - Save file (custom binding)
- `:q` - Quit
- `:wq` - Save and quit
- `Space f` - File picker
- `Space b` - Buffer picker
- `Space /` - Global search
- `gd` - Go to definition (when LSP available)

**Environment variables set:**
- `EDITOR=hx`
- `VISUAL=hx`

### Git & Lazygit

**Git aliases available:**
```bash
git s    # git switch
git f    # git fetch
git p    # git pull
git b    # git branch
git st   # git status -sb
git co   # git checkout
git c    # git commit
```

**Lazygit TUI:**
```bash
lg    # or 'lazygit'
```

Use arrow keys to navigate, `?` for help, `q` to quit.

### Zsh Shell

**Aliases:**
```bash
l       # eza -1l (list files)
ls      # eza -1l (list files)
grep    # rg (ripgrep)
g       # git
lg      # lazygit
hx      # helix
```

**Smart navigation with zoxide:**
```bash
# After cd'ing to directories a few times
cd ~/code/keystone
cd ~/documents/notes
cd ~/projects/website

# Later, jump with partial names
z keystone   # Jumps to ~/code/keystone
z notes      # Jumps to ~/documents/notes
z website    # Jumps to ~/projects/website
```

**Auto-load environments with direnv:**
```bash
# In your project directory, create .envrc:
echo 'use flake' > .envrc
direnv allow

# Directory environment loads automatically when you cd into it
```

### Zellij Multiplexer

**Start session:**
```bash
zellij
```

**Key bindings (default mode is locked):**
- `Ctrl+g` - Enter mode selection
- `Ctrl+p` - Pane mode (split, move, close panes)
- `Ctrl+t` - Tab mode (new, switch, close tabs)
- `Ctrl+q` - Quit zellij

**Tip:** Zellij intentionally does not auto-start to avoid nested sessions.

### Ghostty Terminal

**Launch:**
```bash
ghostty
```

**Features:**
- GPU-accelerated rendering
- Native Wayland support
- Font ligature support
- Shell integration (shows current directory in title)

---

## Troubleshooting

### Issue: Helix language servers not working

**Solution:** Verify language servers are installed:
```bash
which bash-language-server
which yaml-language-server
which nixfmt
```

If missing, ensure the module is enabled and rebuild.

### Issue: Zsh completions not working

**Solution:** Completions are generated on first shell start. Try:
```bash
rm -rf ~/.cache/zsh
exec zsh
```

### Issue: Zoxide not finding directories

**Solution:** Zoxide learns from your navigation. Use `cd` normally for a while, then `z` will work:
```bash
# Navigate normally first
cd ~/code/project1
cd ~/code/project2
cd ~/documents

# Now z will work
z project1  # Success!
```

### Issue: Git signing fails

**Solution:** Ensure your SSH key exists and is configured:
```bash
ls -la ~/.ssh/id_ed25519      # Check key exists
ssh-add -L                     # Verify key is loaded

# Generate key if missing
ssh-keygen -t ed25519 -C "your.email@example.com"
```

---

## Next Steps

### Learn More

- **Helix Tutorial**: Run `hx --tutor` for interactive tutorial
- **Zellij Layouts**: Create custom layouts in `~/.config/zellij/layouts/`
- **Starship Config**: Customize prompt at `~/.config/starship.toml`
- **Ghostty Themes**: Explore themes at `~/.config/ghostty/themes/`

### Advanced Usage

Add language-specific packages to your configuration:

```nix
{
  programs.terminal-dev-environment = {
    enable = true;
    extraPackages = with pkgs; [
      # Rust
      rustc
      cargo
      rust-analyzer

      # Python
      python3
      python3Packages.pip
      python3Packages.poetry

      # Node.js
      nodejs
      nodePackages.typescript-language-server

      # Go
      go
      gopls
    ];
  };

  # Configure helix for additional languages
  programs.helix = {
    languages.language = [
      {
        name = "rust";
        language-servers = [ "rust-analyzer" ];
      }
      {
        name = "python";
        language-servers = [ "pyright" ];
      }
    ];
  };
}
```

### Integration with Development Tools

The terminal environment works great with:

- **devenv** / **direnv**: Automatic project environment loading
- **nix-shell** / **nix develop**: Isolated development environments
- **docker**: Container management (install via extraPackages)
- **kubernetes**: kubectl and k9s (install via extraPackages)

---

## Complete Working Example

Put this in `~/.config/home-manager/home.nix`:

```nix
{ config, pkgs, ... }:
{
  imports = [
    <keystone>/home-manager/modules/terminal-dev-environment
  ];

  # Basic info
  home.username = "youruser";
  home.homeDirectory = "/home/youruser";
  home.stateVersion = "25.05";

  # Enable terminal dev environment
  programs.terminal-dev-environment.enable = true;

  # Configure git identity (required)
  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}
```

Then:
```bash
home-manager switch
exec zsh
```

Done! You now have a complete terminal development environment.
