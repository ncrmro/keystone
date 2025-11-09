{ config, lib, pkgs, ... }:

let
  cfg = config.programs.omarchy-theming;
  terminalCfg = cfg.terminal;
  
  # Path to active theme directory
  themePath = "${config.xdg.configHome}/omarchy/current/theme";
in
{
  config = lib.mkIf (cfg.enable && terminalCfg.enable) {
    # Helix editor theme integration
    programs.helix = lib.mkIf terminalCfg.applications.helix {
      # Note: The actual theme integration will be done in helix.nix
      # This module just ensures the terminal theming is enabled
      # The helix module will check for the theme file and include it if present
    };

    # Ghostty terminal theme integration
    programs.ghostty = lib.mkIf terminalCfg.applications.ghostty {
      # Note: The actual theme integration will be done in ghostty.nix
      # This module just ensures the terminal theming is enabled
      # The ghostty module will use config-file directive to include theme
    };
  };
}
