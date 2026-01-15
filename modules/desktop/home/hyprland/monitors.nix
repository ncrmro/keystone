{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop.monitors;
  hyprlandCfg = config.keystone.desktop.hyprland;
in
{
  options.keystone.desktop.monitors = {
    primaryDisplay = mkOption {
      type = types.str;
      default = "eDP-1";
      description = "Name of the primary display to mirror from (e.g. eDP-1).";
    };

    autoMirror = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically mirror the primary display to new/unknown monitors.";
    };

    settings = mkOption {
      type = types.listOf types.str;
      default = [ 
        ", preferred, auto, 1"
      ];
      description = "List of static monitor configurations (Hyprland syntax).";
    };
  };

  config = mkIf hyprlandCfg.enable {
    wayland.windowManager.hyprland.settings = {
      monitor = cfg.settings ++ (optional cfg.autoMirror ", preferred, auto, 1, mirror, ${cfg.primaryDisplay}");
    };
  };
}
