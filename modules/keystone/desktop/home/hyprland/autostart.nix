{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop.hyprland;
in
{
  config = mkIf cfg.enable {
    wayland.windowManager.hyprland.settings = {
      exec-once = mkDefault [
        # D-Bus activation environment - required for app notifications (Chrome, etc) to use mako
        "systemctl --user import-environment"
        "dbus-update-activation-environment --systemd --all"
        # Session startup
        "hyprlock"
        "uwsm app -- hyprsunset"
        "systemctl --user start hyprpolkitagent"
        "wl-clip-persist --clipboard regular & uwsm app -- clipse -listen"
      ];

      exec = mkDefault [
        "pkill -SIGUSR2 waybar || uwsm app -- waybar"
      ];
    };
  };
}
