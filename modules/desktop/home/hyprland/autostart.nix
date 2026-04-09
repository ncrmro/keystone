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
      exec-once = mkDefault [
        # D-Bus activation environment - required for app notifications (Chrome, etc) to use mako
        "systemctl --user import-environment"
        "dbus-update-activation-environment --systemd --all"
        # Session startup. The first graphical interaction MUST be the startup
        # lock. If it does not come up, keystone-startup-lock exits the session
        # rather than exposing an unlocked desktop.
        "keystone-startup-lock"
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
