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

      # Hyprland 0.53+ windowrule syntax: action [value], match:condition
      # Boolean rules like tile/float/fullscreen need a value (1/on or 0/off)
      windowrule = mkDefault [
        # Suppress maximize events
        "suppressevent maximize, match:class .*"

        # Force chromium into a tile to deal with --app bug
        "tile 1, match:class ^(chromium)$"

        # Settings management - float pavucontrol and blueberry
        "float 1, match:class ^(org.pulseaudio.pavucontrol|blueberry.py)$"

        # Float Steam, fullscreen RetroArch
        "float 1, match:class ^(steam)$"
        "fullscreen 1, match:class ^(com.libretro.RetroArch)$"

        # Slight transparency for all windows
        "opacity 0.97 0.9, match:class .*"
        # Full opacity for video content
        "opacity 1 1, match:class ^(chromium|google-chrome|google-chrome-unstable)$, match:title .*Youtube.*"
        "opacity 1 0.97, match:class ^(chromium|google-chrome|google-chrome-unstable)$"
        "opacity 0.97 0.9, match:initialClass ^(chrome-.*-Default)$"
        "opacity 1 1, match:initialClass ^(chrome-youtube.*-Default)$"
        "opacity 1 1, match:class ^(zoom|vlc|org.kde.kdenlive|com.obsproject.Studio)$"
        "opacity 1 1, match:class ^(com.libretro.RetroArch|steam)$"

        # Fix some dragging issues with XWayland
        "nofocus 1, match:class ^$, match:title ^$, match:xwayland 1, match:floating 1, match:fullscreen 0, match:pinned 0"

        # Float in the middle for clipse clipboard manager
        "float 1, match:class (clipse)"
        "size 622 652, match:class (clipse)"
        "stayfocused 1, match:class (clipse)"
      ];

      # layerrule disabled until Hyprland 0.52+ syntax is confirmed
      # layerrule = mkDefault [
      #   "blur on, namespace:wofi"
      #   "blur on, namespace:waybar"
      # ];
    };
  };
}
