# Keystone Notes — Home Manager module
#
# Syncs a git-backed notes repository on a timer using repo-sync.
# Designed for human users (agents use the NixOS-level keystone.os.agents.*.notes).
#
# Usage:
#   keystone.notes = {
#     enable = true;
#     repo = "git@github.com:user/notes.git";
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.keystone.notes;
in
{
  options.keystone.notes = {
    enable = lib.mkEnableOption "Keystone notes sync";

    repo = lib.mkOption {
      type = lib.types.str;
      description = "Git repository URL for the notes repo.";
      example = "git@github.com:user/notes.git";
    };

    path = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/notes";
      description = "Local checkout path for the notes repo.";
    };

    syncInterval = lib.mkOption {
      type = lib.types.str;
      default = "*:0/5";
      description = "Systemd calendar spec for the sync timer. Default: every 5 minutes.";
    };

    commitPrefix = lib.mkOption {
      type = lib.types.str;
      default = "vault sync";
      description = "Commit message prefix used by repo-sync.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.keystone-notes-sync = {
      Unit = {
        Description = "Sync notes repo via repo-sync";
      };

      Service = {
        Type = "oneshot";
        ExecStart = builtins.concatStringsSep " " [
          "${pkgs.keystone.repo-sync}/bin/repo-sync"
          "--repo ${lib.escapeShellArg cfg.repo}"
          "--path ${lib.escapeShellArg cfg.path}"
          "--commit-prefix ${lib.escapeShellArg cfg.commitPrefix}"
          "--log-dir ${config.home.homeDirectory}/.local/state/notes-sync/logs"
        ];
      };
    };

    systemd.user.timers.keystone-notes-sync = {
      Unit = {
        Description = "Timer for notes repo sync";
      };

      Timer = {
        OnCalendar = cfg.syncInterval;
        Persistent = true;
      };

      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
