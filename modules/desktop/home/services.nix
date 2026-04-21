# Systemd user services for desktop-triggered background work.
#
# ks-update.service runs `ks update --approve` in the background so Walker
# (and future triggers like keybinds or cron) can kick off a host update
# without opening a terminal. Approval uses pkexec via the already-running
# hyprpolkitagent; output goes to the journal; completion fires a
# notification via the ks-update-notify@.service template.
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
        ExecStart = "${ksBin} notify ks-update.service %i";
      };
    };
  };
}
