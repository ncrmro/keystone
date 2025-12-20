{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.desktop.hyprland;
  # Build kb_options based on configuration
  # If capslockAsControl is true, use ctrl:nocaps, otherwise use compose:caps
  kbOptions = if cfg.capslockAsControl then "ctrl:nocaps" else "compose:caps";
in {
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

      # Note: workspace_swipe was removed in Hyprland 0.51+
      # Use new gesture syntax if needed: gesture = fingers, direction, action
    };
  };
}
