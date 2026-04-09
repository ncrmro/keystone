{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  desktopCfg = config.keystone.desktop;
in
{
  config = mkIf desktopCfg.enable {
    services.hyprpaper = {
      enable = mkDefault true;
      # TODO: remove once home-manager is updated — newer HM defaults importantPrefixes to ["$" "monitor"]
      importantPrefixes = [
        "$"
        "monitor"
      ];
      settings = {
        splash = false;
        wallpaper = [
          {
            monitor = "";
            path = "${config.xdg.configHome}/keystone/current/background";
            fit_mode = "cover";
          }
        ];
      };
    };
  };
}
