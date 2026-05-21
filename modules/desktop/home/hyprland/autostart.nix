{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  desktopCfg = config.keystone.desktop;
  hyprSettings = config.wayland.windowManager.hyprland.settings;
in
{
  config = mkIf desktopCfg.enable {
    # SECURITY: Build-time guard — if a module accidentally replaces or
    # reorders the exec-once list (e.g., bare assignment, mkDefault, or
    # mkBefore), this assertion stops the build before an unlocked desktop
    # can be deployed. See convention os.hyprland-autostart.
    assertions = [
      {
        assertion =
          let
            userVisible = builtins.filter (
              cmd:
              !(
                lib.hasPrefix "systemctl --user import-environment" cmd
                || lib.hasPrefix "dbus-update-activation-environment" cmd
              )
            ) hyprSettings.exec-once;
          in
          userVisible != [ ] && lib.hasPrefix desktopCfg.startupLockCommand (builtins.head userVisible);
        message = ''
          SECURITY: ${desktopCfg.startupLockCommand} must be the first non-D-Bus
          Hyprland exec-once entry.
          The desktop session MUST start locked to prevent exposing an unlocked
          desktop after reboot. A module likely reordered exec-once with mkBefore
          or replaced the base list from autostart.nix with bare assignment or
          mkDefault. See convention os.hyprland-autostart.
        '';
      }
    ];

    wayland.windowManager.hyprland.settings = {
      exec-once = [
        # D-Bus activation environment - required for app notifications (Chrome, etc) to use mako
        "systemctl --user import-environment"
        "dbus-update-activation-environment --systemd --all"
        # Session startup. The first graphical interaction MUST be the startup
        # lock. If it does not come up, the lock command exits the session
        # rather than exposing an unlocked desktop.
        desktopCfg.startupLockCommand
        # Only start hyprsunset if the GPU supports CTM (color transform).
        # virtio-gpu in VMs lacks CTM, and hyprsunset's CTM commits block
        # all page-flips, freezing the display.
        "sh -c 'for card in /sys/class/drm/card*/device/driver; do readlink -f $card 2>/dev/null; done | grep -q virtio || uwsm app -- hyprsunset'"
        "systemctl --user start hyprpolkitagent"
        "wl-clip-persist --clipboard regular & uwsm app -- clipse -listen"
      ];

      exec = [
        # SIGUSR2 reloads waybar's config in place. No `|| uwsm app -- waybar`
        # fallback — home-manager's `programs.waybar` already enables a
        # `waybar.service` user unit (via `programs.waybar.systemd.enable`,
        # default true on Linux), which is the canonical start path for the
        # bar. Spawning waybar here as a fallback on Hyprland's config
        # processing produced a second, parallel waybar at session start
        # (one from this line, one from the systemd unit) — visually stacked
        # bars on the same monitor, with the Hyprland-spawned one stuck on
        # the previous theme after `keystone-theme-switch` (which only
        # restarts waybar.service).
        #
        # If waybar isn't running when this line fires, pkill exits
        # non-zero and the line is a no-op. waybar.service then starts as
        # part of graphical-session.target. On subsequent `hyprctl reload`s,
        # SIGUSR2 reloads the live waybar in place.
        "pkill -SIGUSR2 waybar"
      ];
    };
  };
}
