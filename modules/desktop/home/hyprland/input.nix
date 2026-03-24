{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop.hyprland;
  # Build kb_options based on configuration
  # - altwin:swap_alt_win: Swap Alt and Super keys for ergonomic window management
  #   Physical Alt (thumb position) → Super keycodes → Hyprland $mod
  #   Physical Super → Alt keycodes → Browser back/forward (Alt+Left/Right)
  # - ctrl:nocaps or compose:caps: Caps Lock behavior
  capsOption = if cfg.capslockAsControl then "ctrl:nocaps" else "compose:caps";
  kbOptions = "${capsOption},altwin:swap_alt_win";
in
{
  config = mkIf cfg.enable {
    wayland.windowManager.hyprland.settings = {
      input = mkDefault {
        kb_layout = "us";
        kb_options = kbOptions;
        follow_mouse = 1;
        sensitivity = 0;
        scroll_factor = 0.4; # Reduce scroll speed (omarchy default)

        touchpad = {
          natural_scroll = true;
          drag_lock = cfg.touchpad.dragLock;
        };
      };

      # Touchpad gestures for workspace switching (Hyprland 0.51+ syntax)
      # Four-finger horizontal swipe switches workspaces
      gestures = {
        gesture = [
          "4, horizontal, workspace"
          # TODO: Three-finger drag for window moving is not supported by Hyprland.
          # The upstream issue (https://github.com/hyprwm/Hyprland/issues/5473) is
          # marked "not planned" — native touchpad drag gestures that move/float windows
          # are not implemented. Re-evaluate when upstream adds support.
        ];
      };
    };
  };
}
