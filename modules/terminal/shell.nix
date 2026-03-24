# Shell environment — Zsh, starship prompt, zoxide, direnv, zellij, and CLI tools.
# Includes zellij layout presets (dev, ops, write) for the context system.
#
# Implements REQ-002 (FR-001: Shell Environment, FR-003: Terminal Multiplexer)
# See conventions/tool.nix-devshell.md
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
in
{
  config = mkIf cfg.enable {
    # Starship - A minimal, blazing-fast, and infinitely customizable prompt for any shell
    # Shows git status, language versions, execution time, and more in your terminal prompt
    # https://starship.rs/
    programs.starship.enable = true;

    # Zoxide - A smarter cd command that learns your navigation patterns
    # Tracks your most used directories and lets you jump to them with 'z <partial-name>'
    # Example: 'z proj' jumps to ~/code/projects, 'zi' for interactive selection
    # https://github.com/ajeetdsouza/zoxide
    programs.zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    # Direnv - Unclutter your .profile
    # Loads and unloads environment variables depending on the current directory
    # https://direnv.net/
    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    # Zellij - A terminal multiplexer with layouts, panes, and tabs
    # Modern alternative to tmux/screen with built-in session management
    # https://zellij.dev/
    programs.zellij = {
      enable = true;
      enableZshIntegration = false;
      settings = {
        theme = "current";
        startup_tips = false;
        pane_frames = false;
        keybinds = {
          normal = {
            # Previous tab: Ctrl+PgUp
            "bind \"Ctrl PageUp\"" = {
              GoToPreviousTab = { };
            };
            # Next tab: Ctrl+PgDn
            "bind \"Ctrl PageDown\"" = {
              GoToNextTab = { };
            };
            # Previous tab (alternative): Ctrl+Shift+Tab
            "bind \"Ctrl Shift Tab\"" = {
              GoToPreviousTab = { };
            };
            # Next tab (alternative): Ctrl+Tab
            "bind \"Ctrl Tab\"" = {
              GoToNextTab = { };
            };
            # New tab: Ctrl+T
            # Enforce naming in-client to avoid the multi-client CLI rename-tab issue.
            "bind \"Ctrl t\"" = {
              NewTab = { };
              UndoRenameTab = { };
              SwitchToMode = "RenameTab";
              TabNameInput = 0;
            };
            # Close tab: Ctrl+W
            "bind \"Ctrl w\"" = {
              CloseTab = { };
            };
            # Unbind default Ctrl+G (conflict with Claude Code)
            "unbind \"Ctrl g\"" = [ ];
            # Lock mode: Ctrl+Shift+G
            "bind \"Ctrl Shift g\"" = {
              SwitchToMode = "locked";
            };
            # Unbind default Ctrl+O (conflict with Claude Code and lazygit)
            "unbind \"Ctrl o\"" = [ ];
            # Session mode: Ctrl+Shift+O
            "bind \"Ctrl Shift o\"" = {
              SwitchToMode = "session";
            };
          };
        };
      };
    };

    # Zellij layouts — pre-configured tab presets for context system
    # Used by: pz --layout <name>, keystone-context <slug> --layout <name>
    xdg.configFile."zellij/layouts/dev.kdl".source = ./layouts/dev.kdl;
    xdg.configFile."zellij/layouts/ops.kdl".source = ./layouts/ops.kdl;
    xdg.configFile."zellij/layouts/write.kdl".source = ./layouts/write.kdl;

    # Fzf - A command-line fuzzy finder
    # https://github.com/junegunn/fzf
    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    # Bat - A cat(1) clone with wings (syntax highlighting and Git integration)
    # https://github.com/sharkdp/bat
    programs.bat = {
      enable = true;
    };

    programs.zsh = {
      enable = true;
      enableCompletion = mkDefault true;
      autosuggestion.enable = mkDefault true;
      syntaxHighlighting.enable = mkDefault true;
      shellAliases = {
        # Better unix commands
        l = "eza -1l";
        ls = "eza -1l";
        grep = "rg";
        # Local Development
        g = "git";
        lg = "lazygit";
        # Terminal utilities
        ztab = "zellij action rename-tab";
        zs = "zesh connect"; # Zellij session manager with zoxide integration
        y = "yazi";
      };
      history.size = 100000;
      zplug.enable = lib.mkForce false;
      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "colored-man-pages"
        ];
        theme = "robbyrussell";
      };
    };

    home.packages = with pkgs; [
      # Bottom - Graphical process/system monitor
      # https://github.com/ClementTsang/bottom
      bottom

      # Dust - A more intuitive version of du in rust
      # https://github.com/bootandy/dust
      dust

      # Fd - A simple, fast and user-friendly alternative to 'find'
      # https://github.com/sharkdp/fd
      fd

      # Ncdu - NCurses Disk Usage
      # https://dev.yorhel.nl/ncdu
      ncdu

      # Sd - Intuitive find & replace CLI (sed alternative)
      # https://github.com/chmln/sd
      sd

      # Tealdeer - A fast tldr client in Rust (simplified man pages)
      # https://github.com/dbrgn/tealdeer
      tealdeer

      # Direnv - Unclutter your .profile
      # https://direnv.net/
      direnv

      # Ghostty terminfo - Required for SSH connections from Ghostty terminal
      # Without this, remote systems don't recognize TERM="xterm-ghostty" and
      # ncurses applications fail with "cannot initialize terminal type" errors.
      # This enables proper terminal handling when SSHing into this machine from Ghostty.
      ghostty.terminfo

      # Eza - Modern replacement for ls with colors and git integration
      # https://github.com/eza-community/eza
      eza

      # Glow - Render markdown on the CLI with style
      # https://github.com/charmbracelet/glow
      glow

      # GNU Make - Build automation tool
      # https://www.gnu.org/software/make/
      gnumake

      # Htop - Interactive process viewer
      # https://htop.dev/
      htop

      # GitHub CLI - GitHub's official command line tool
      # https://cli.github.com/
      gh

      # Lazygit - Simple terminal UI for git commands
      # https://github.com/jesseduffield/lazygit
      lazygit

      # Ripgrep - Fast search tool that recursively searches directories
      # https://github.com/BurntSushi/ripgrep
      ripgrep

      # Tree - Display directory structure as a tree
      # https://mama.indstate.edu/users/ice/tree/
      tree

      # Yazi - Blazing fast terminal file manager written in Rust
      # https://github.com/sxyazi/yazi
      yazi

      # Zesh - Zellij session manager with zoxide integration
      # https://github.com/roberte777/zesh
      # Provided via keystone overlay
      pkgs.keystone.zesh

      # ks - Keystone infrastructure CLI (build and deploy NixOS configurations)
      pkgs.keystone.ks

      # Jq - Lightweight command-line JSON processor
      # https://jqlang.github.io/jq/
      jq

      # Yq - Portable command-line YAML processor
      # https://github.com/mikefarah/yq
      yq-go

      # Nixfmt - Official Nix code formatter (RFC style)
      # https://github.com/NixOS/nixfmt
      nixfmt-rfc-style
    ];
  };
}
