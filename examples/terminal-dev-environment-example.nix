{ config, pkgs, ... }:

# Basic example: Enable terminal development environment with all defaults
{
  imports = [
    ../home-manager/modules/terminal-dev-environment
  ];

  # Enable the terminal development environment module
  programs.terminal-dev-environment.enable = true;

  # Required: Configure your git identity
  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";
  };

  # Optional: Add extra packages
  # programs.terminal-dev-environment.extraPackages = with pkgs; [
  #   ripgrep
  #   fd
  #   bat
  # ];

  # Optional: Override individual tool configurations
  # programs.helix.settings.theme = "gruvbox";
  # programs.zsh.shellAliases.vim = "helix";

  # Optional: Disable specific tools
  # programs.terminal-dev-environment.tools.multiplexer = false;
}
