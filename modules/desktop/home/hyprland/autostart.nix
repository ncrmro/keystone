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
        # Only start hyprsunset if the GPU supports CTM (color transform).
        # virtio-gpu in VMs lacks CTM, and hyprsunset's CTM commits block
        # all page-flips, freezing the display.
        "sh -c 'for card in /sys/class/drm/card*/device/driver; do readlink -f $card 2>/dev/null; done | grep -q virtio || uwsm app -- hyprsunset'"
        "systemctl --user start hyprpolkitagent"
        "wl-clip-persist --clipboard regular & uwsm app -- clipse -listen"
      ];

      exec = mkDefault [
        "pkill -SIGUSR2 waybar || uwsm app -- waybar"
      ];
    };
  };
}
