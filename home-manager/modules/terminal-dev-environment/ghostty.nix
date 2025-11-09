{ config, lib, pkgs, ... }:

let
  cfg = config.programs.terminal-dev-environment;
  themingCfg = config.programs.omarchy-theming or { };
  
  # Check if theming is enabled and ghostty theming is specifically enabled
  themingEnabled = themingCfg.enable or false 
    && themingCfg.terminal.enable or false 
    && themingCfg.terminal.applications.ghostty or false;
    
  # Path to omarchy ghostty theme config
  ghosttyThemePath = "${config.xdg.configHome}/omarchy/current/theme/ghostty.conf";
in
{
  config = lib.mkIf (cfg.enable && cfg.tools.terminal) {
    programs.ghostty = {
      enable = true;
      enableZshIntegration = lib.mkDefault true;
      
      # Merge theme configuration if omarchy theming is enabled
      settings = lib.mkMerge [
        (lib.mkDefault { })
        (lib.mkIf themingEnabled {
          # Ghostty supports config-file directive to include additional config
          # This allows the base config to stay declarative while themes are loaded dynamically
          config-file = ghosttyThemePath;
        })
      ];
    };
  };
}
