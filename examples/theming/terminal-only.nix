# Terminal-Only Theming Example
#
# This example shows how to enable theming for terminal applications
# without enabling the desktop theming stub.

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

  # Enable only terminal theming
  programs.omarchy-theming = {
    enable = true;
    
    terminal = {
      enable = true;
      applications = {
        helix = true;
        ghostty = true;
      };
    };
    
    # Explicitly disable desktop theming
    desktop = {
      enable = false;
    };
  };
}
