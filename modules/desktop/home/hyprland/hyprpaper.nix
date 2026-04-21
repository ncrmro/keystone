{
  config,
  lib,
  pkgs,
  keystoneInputs,
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
      package = keystoneInputs.hyprpaper.packages.${pkgs.stdenv.hostPlatform.system}.hyprpaper;
      # TODO: remove once home-manager is updated — newer HM defaults importantPrefixes to ["$" "monitor"]
      importantPrefixes = [
        "$"
        "monitor"
      ];
      settings = {
        splash = false;
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
