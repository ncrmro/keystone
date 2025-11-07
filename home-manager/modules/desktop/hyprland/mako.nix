{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.desktop.hyprland;
in {
  config = lib.mkIf (cfg.enable && cfg.components.mako) {
    services.mako = {
      enable = true;

      # Default notification settings
      defaultTimeout = 5000; # 5 seconds

      # Visual settings
      backgroundColor = "#2b303b";
      textColor = "#ffffff";
      borderColor = "#33ccff";
      borderSize = 2;
      borderRadius = 10;

      # Position and layout
      anchor = "top-right";
      margin = "10";
      padding = "10";

      # Size constraints
      width = 300;
      height = 100;

      # Font
      font = "CaskaydiaMono Nerd Font 11";

      # Icons
      icons = true;
      maxIconSize = 64;

      # Group notifications
      groupBy = "app-name";
    };
  };
}
