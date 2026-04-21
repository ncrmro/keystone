# Systemd user services for desktop-triggered background work.
#
# ks-update.service runs `ks update --approve` in the background so Walker
# (and future triggers like keybinds or cron) can kick off a host update
# without opening a terminal. Approval uses pkexec via the already-running
# hyprpolkitagent; output goes to the journal; completion fires a
# notification via the ks-update-notify@.service template.
#
# Principal parity (process.keystone-principal-parity): these units are
# deliberately gated on `keystone.desktop.enable` — they're only useful on
# principals that run a graphical session. Agents declared with desktop
# access inherit the units automatically; headless principals don't get
# them. Do not move this module to a desktop-neutral location.
#
# Rationale: see issue #414 and the accompanying PR. Prior to this module
# the Walker update entry launched Ghostty and ran `ks approve -- ks update`
# inline — this moves that work to a supervised background unit so the
# success path is silent (polkit prompt + desktop notification) and the
# failure path preserves logs in the journal for on-demand review.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
  ksBin = "${pkgs.keystone.ks}/bin/ks";
  systemdBin = "${pkgs.systemd}/bin/systemd-inhibit";

  # `ks update` (invoked by ks-update.service) shells out to git, nix,
  # pkexec, and keystone-approve-exec. Systemd user units start with a
  # minimal PATH that does not include these, so spawn-by-name would fail
  # inside the unit even though it works in an interactive shell.
  #
  # `/run/current-system/sw/bin` is the NixOS system-wide toolchain and
  # contains git, nix, and keystone-approve-exec. `/run/wrappers/bin`
  # holds setuid wrappers like pkexec. Together they cover everything
  # `ks update --approve` needs for a supervised background run.
  updatePath = "/run/wrappers/bin:/run/current-system/sw/bin";

  # `ks notify` only shells out to journalctl (systemd) and notify-send
  # (libnotify). Pin those explicitly rather than relying on the system
  # path so the notifier keeps working even if the system profile
  # excludes libnotify for any reason.
  notifyPath = "${pkgs.systemd}/bin:${pkgs.libnotify}/bin";
in
{
  config = mkIf cfg.enable {
    systemd.user.services.ks-update = {
      Unit = {
        Description = "Keystone OS update (background)";
        After = [
          "graphical-session.target"
          "network-online.target"
        ];
        Wants = [ "network-online.target" ];
        OnSuccess = [ "ks-update-notify@success.service" ];
        OnFailure = [ "ks-update-notify@failure.service" ];
      };
      Service = {
        Type = "oneshot";
        Environment = [ "PATH=${updatePath}" ];
        # systemd-inhibit blocks suspend/shutdown for the duration of the
        # update so a laptop lid close mid-rebuild doesn't wedge the unit.
        ExecStart = ''
          ${systemdBin} --what=sleep:shutdown:idle \
            --why='Keystone OS update in progress' \
            --mode=block \
            ${ksBin} update --approve
        '';
        # Polkit prompts may sit for a while if the user steps away. 30 min
        # is enough to cover the largest real updates plus approval latency;
        # beyond that we surface a timeout failure via OnFailure.
        TimeoutStartSec = "30min";
      };
    };

    # Template unit invoked via OnSuccess/OnFailure on ks-update.service.
    # The instance name (%i) is either "success" or "failure" and is passed
    # through to `ks notify`, which reads the ks-update.service journal and
    # fires an appropriate desktop notification.
    systemd.user.services."ks-update-notify@" = {
      Unit = {
        Description = "Keystone update notification (%i)";
      };
      Service = {
        Type = "oneshot";
        Environment = [ "PATH=${notifyPath}" ];
        ExecStart = "${ksBin} notify ks-update.service %i";
      };
    };
  };
}
