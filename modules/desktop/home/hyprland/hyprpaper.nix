{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.desktop.hyprland;
in {
  config = mkIf cfg.enable {
    services.hyprpaper = {
      enable = mkDefault true;
      settings = {
        preload = [
          "${config.xdg.configHome}/keystone/current/background"
        ];
        wallpaper = [
          ",${config.xdg.configHome}/keystone/current/background"
        ];
      };
    };
  };
}
