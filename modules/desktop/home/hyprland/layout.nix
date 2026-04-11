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

      # Hyprland 0.54+ windowrule syntax: "action value, match:field pattern"
      # tile/float need an explicit "on" — bare "tile" or "float" is a parse error.
      # match:class matches WM_CLASS; multiple match: clauses AND together.
      windowrule = mkDefault [
        # Chromium --app mode misidentifies windows as popups, so they float
        # and overlap your tiled layout. Force them back into tiles.
        "tile on, match:class ^(chromium)$"

        # Volume and bluetooth panels are small fixed dialogs — floating
        # keeps them out of the tiling grid where they'd get awkwardly stretched.
        "float on, match:class ^(org.pulseaudio.pavucontrol|blueberry.py)$"

        # Subtle transparency gives depth cues between focused and background
        # windows. 0.97 focused / 0.9 unfocused is barely perceptible but
        # makes the active window pop without feeling like frosted glass.
        # Video, streaming, and gaming apps get full opacity so content
        # isn't washed out.
        "opacity 0.97 0.9, match:class .*"
        "opacity 1 1, match:class ^(chromium|google-chrome|google-chrome-unstable)$, match:title .*Youtube.*"
        "opacity 1 0.97, match:class ^(chromium|google-chrome|google-chrome-unstable)$"
        "opacity 0.97 0.9, match:class ^(chrome-.*-Default)$"
        "opacity 1 1, match:class ^(chrome-youtube.*-Default)$"
        "opacity 1 1, match:class ^(zoom|vlc|org.kde.kdenlive|com.obsproject.Studio)$"
        "opacity 1 1, match:class ^(com.libretro.RetroArch|steam)$"

        # Clipse clipboard picker should appear as a centered overlay you can
        # quickly select from and dismiss — not a tiled pane.
        "float on, match:class (clipse)"
        "size 622 652, match:class (clipse)"

        # Quick-capture notes inbox opens as a floating dialog so you can
        # jot something down without disrupting your workspace layout.
        "float on, match:class ^(com.mitchellh.ghostty)$, match:title ^(keystone-notes-inbox)$"
        "center on, match:class ^(com.mitchellh.ghostty)$, match:title ^(keystone-notes-inbox)$"
        "size 1000 700, match:class ^(com.mitchellh.ghostty)$, match:title ^(keystone-notes-inbox)$"
      ];

      # layerrule disabled until Hyprland 0.52+ syntax is confirmed
      # layerrule = mkDefault [
      #   "blur on, namespace:wofi"
      #   "blur on, namespace:waybar"
      # ];
    };
  };
}
