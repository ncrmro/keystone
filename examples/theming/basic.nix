# Minimal Omarchy Theming Example
#
# This example shows the simplest way to enable Omarchy theming
# for terminal applications.

{ config, ... }:

{
  # Enable terminal development environment
  programs.terminal-dev-environment = {
    enable = true;
    tools = {
      editor = true;    # Helix editor
      terminal = true;  # Ghostty terminal
      shell = true;
      git = true;
    };
  };

  # Enable Omarchy theming with all defaults
  programs.omarchy-theming = {
    enable = true;
    # All other options use defaults:
    # - terminal.enable = true
    # - terminal.applications.helix = true
    # - terminal.applications.ghostty = true
    # - desktop.enable = false
  };

  # After rebuild, you can:
  # - Open Helix and see themed colors: hx myfile.txt
  # - Open Ghostty and see themed colors: ghostty
  # - Switch themes: omarchy-theme-next
  # - Install custom themes: omarchy-theme-install <git-url>
}
