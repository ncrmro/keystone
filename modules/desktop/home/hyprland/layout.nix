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
    wayland.windowManager.hyprland.settings = {
      general = {
        layout = mkDefault "dwindle";
      };

      dwindle = mkDefault {
        pseudotile = true;
        preserve_split = true;
        force_split = 2;
      };

      master = mkDefault {
        new_status = "master";
      };

      windowrule = mkDefault [
        # Suppress maximize events
        "suppressevent maximize, match:class .*"

        # Force chromium into a tile to deal with --app bug
        "tile, match:class ^(chromium)$"

        # Settings management
        "float, match:class ^(org.pulseaudio.pavucontrol|blueberry.py)$"

        # Float Steam, fullscreen RetroArch
        "float, match:class ^(steam)$"
        "fullscreen, match:class ^(com.libretro.RetroArch)$"

        # Slight transparency
        "opacity 0.97 0.9, match:class .*"
        # Full opacity for video content
        "opacity 1 1, match:class ^(chromium|google-chrome|google-chrome-unstable)$, match:title .*Youtube.*"
        "opacity 1 0.97, match:class ^(chromium|google-chrome|google-chrome-unstable)$"
        "opacity 0.97 0.9, match:initialClass ^(chrome-.*-Default)$"
        "opacity 1 1, match:initialClass ^(chrome-youtube.*-Default)$"
        "opacity 1 1, match:class ^(zoom|vlc|org.kde.kdenlive|com.obsproject.Studio)$"
        "opacity 1 1, match:class ^(com.libretro.RetroArch|steam)$"

        # Fix some dragging issues with XWayland
        "nofocus, match:class ^$, match:title ^$, match:xwayland 1, match:floating 1, match:fullscreen 0, match:pinned 0"

        # Float in the middle for clipse clipboard manager
        "float, match:class (clipse)"
        "size 622 652, match:class (clipse)"
        "stayfocused, match:class (clipse)"
      ];

      # layerrule disabled until Hyprland 0.52+ syntax is confirmed
      # layerrule = mkDefault [
      #   "blur on, namespace:wofi"
      #   "blur on, namespace:waybar"
      # ];
    };
  };
}
