{
  config,
  lib,
  pkgs,
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
            "bind \"Ctrl t\"" = {
              NewTab = { };
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

    programs.zsh = {
      enable = true;
      shellAliases = {
        # Better unix commands
        l = "eza -1l";
        ls = "eza -1l";
        grep = "rg";
        # Local Development
        g = "git";
        lg = "lazygit";
      };
      history.size = 100000;
      zplug.enable = lib.mkForce false;
      oh-my-zsh = {
        enable = true;
        plugins = [ "git" ];
        theme = "robbyrussell";
      };
    };

    home.packages = with pkgs; [
      # GNU Make - Build automation tool
      # https://www.gnu.org/software/make/
      gnumake

      # Lazygit - Simple terminal UI for git commands
      # https://github.com/jesseduffield/lazygit
      lazygit

      # Ripgrep - Fast search tool that recursively searches directories
      # https://github.com/BurntSushi/ripgrep
      ripgrep

      # Yazi - Blazing fast terminal file manager written in Rust
      # https://github.com/sxyazi/yazi
      yazi
    ];
  };
}
