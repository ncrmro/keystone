# Selective Application Theming Example
#
# This example shows how to theme only specific applications.
# Useful if you want themed Ghostty but prefer Helix's default colors.

{ config, ... }:

{
  # Enable terminal development environment
  programs.terminal-dev-environment = {
    enable = true;
    tools = {
      editor = true;
      terminal = true;
      shell = true;
      git = true;
    };
  };

  # Enable theming for Ghostty only
  programs.omarchy-theming = {
    enable = true;
    
    terminal = {
      enable = true;
      applications = {
        # Don't theme Helix - it will use its default theme
        helix = false;
        
        # Only theme Ghostty terminal
        ghostty = true;
      };
    };
  };
}
