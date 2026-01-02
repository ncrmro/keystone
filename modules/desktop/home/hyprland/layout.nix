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

      # Hyprland 0.52+ windowrule syntax
      # See: https://wiki.hypr.land/Configuring/Window-Rules/
      windowrule = mkDefault [
        # Settings management - float pavucontrol and blueberry
        "float on, match:class ^(org.pulseaudio.pavucontrol|blueberry.py)$"

        # Float Steam, fullscreen RetroArch
        "float on, match:class ^(steam)$"
        "fullscreen on, match:class ^(com.libretro.RetroArch)$"

        # Slight transparency for all windows
        "opacity 0.97 0.9, match:class .*"
        # Full opacity for video content
        "opacity 1 1, match:class ^(chromium|google-chrome|google-chrome-unstable)$, match:title .*Youtube.*"
        "opacity 1 0.97, match:class ^(chromium|google-chrome|google-chrome-unstable)$"
        "opacity 1 1, match:class ^(zoom|vlc|org.kde.kdenlive|com.obsproject.Studio)$"
        "opacity 1 1, match:class ^(com.libretro.RetroArch|steam)$"

        # Float in the middle for clipse clipboard manager
        "float on, match:class (clipse)"
        "size 622 652, match:class (clipse)"
      ];

      # layerrule disabled until Hyprland 0.52+ syntax is confirmed
      # Hyprland 0.52+ layerrule syntax: "rule value, namespace"
      # layerrule = mkDefault [
      #   "blur on, wofi"
      #   "blur on, waybar"
      # ];
    };
  };
}
