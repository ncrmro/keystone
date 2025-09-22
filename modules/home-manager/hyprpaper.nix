{
  config,
  lib,
  ...
}: let
  cfg = config.keystone;
  wallpaperPath = 
    if cfg ? desktop && cfg.desktop ? wallpaper
    then cfg.desktop.wallpaper
    else "~/Pictures/wallpaper.jpg";
in {
  services.hyprpaper = {
    enable = true;
    settings = {
      ipc = "on";
      splash = false;
      splash_offset = 2.0;
      
      preload = [
        wallpaperPath
      ];
      
      wallpaper = [
        ",${wallpaperPath}"
      ];
    };
  };
}