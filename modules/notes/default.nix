# Keystone Notes — Home Manager module  [EXPERIMENTAL]
#
# EXPERIMENTAL: This module is not part of the stable v1 surface.
# It may change significantly or be restructured in future releases.
#
# Syncs a git-backed notes repository on a timer using repo-sync.
# Used by both human users and agents.
# See specs/REQ-018-repo-management/requirements.md
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
  pathHasParentTraversal = path: builtins.elem ".." (lib.splitString "/" path);
  sshAuthSock =
    if
      lib.hasAttrByPath [
        "keystone"
        "terminal"
        "ssh"
        "authSock"
      ] config
    then
      config.keystone.terminal.ssh.authSock
    else
      "%t/ssh-agent";

  notesGitignore = ''
    # Local shell and environment state
    .direnv/
    .env
    .env.local
    .venv/
    __pycache__/

    # Nix local outputs
    result
    result-*

    # OS/editor junk
    .DS_Store
    Thumbs.db
  '';

  dailyRolloverScript = pkgs.writeShellScript "keystone-notes-daily-rollover" ''
    set -euo pipefail

    NOTES_PATH=${lib.escapeShellArg cfg.path}
    DAILY_REL=${lib.escapeShellArg cfg.daily.symlinkPath}
    JOURNAL_REL=${lib.escapeShellArg cfg.daily.journalPath}
    TODAY_FILE_NAME="$(date +${lib.escapeShellArg cfg.daily.dateFormat}).md"

    DAILY_PATH="$NOTES_PATH/$DAILY_REL"
    JOURNAL_PATH="$NOTES_PATH/$JOURNAL_REL"
    TARGET_REL="$JOURNAL_REL/$TODAY_FILE_NAME"
    TARGET_PATH="$NOTES_PATH/$TARGET_REL"

    if [[ ! -d "$NOTES_PATH/.git" ]]; then
      exit 0
    fi

    ${pkgs.coreutils}/bin/mkdir -p \
      "$JOURNAL_PATH" \
      "$(${pkgs.coreutils}/bin/dirname "$DAILY_PATH")"

    DAILY_REAL="$(${pkgs.coreutils}/bin/realpath -m "$DAILY_PATH")"
    TARGET_REAL="$(${pkgs.coreutils}/bin/realpath -m "$TARGET_PATH")"

    if [[ "$DAILY_REAL" == "$TARGET_REAL" ]]; then
      echo "keystone-notes-daily-rollover: daily.symlinkPath resolves to today's journal target; refusing to replace the note with a symlink" >&2
      exit 1
    fi

    if [[ -L "$DAILY_PATH" ]] && [[ "$(${pkgs.coreutils}/bin/readlink "$DAILY_PATH")" == "$TARGET_REL" ]]; then
      if [[ ! -e "$TARGET_PATH" ]]; then
        : > "$TARGET_PATH"
      fi
      exit 0
    fi

    if [[ -e "$DAILY_PATH" ]] && [[ ! -L "$DAILY_PATH" ]]; then
      if [[ "$(${pkgs.coreutils}/bin/realpath -m "$DAILY_PATH")" != "$(${pkgs.coreutils}/bin/realpath -m "$TARGET_PATH")" ]]; then
        if [[ ! -e "$TARGET_PATH" ]]; then
          ${pkgs.coreutils}/bin/mv "$DAILY_PATH" "$TARGET_PATH"
        else
          if ! ${pkgs.diffutils}/bin/cmp -s "$DAILY_PATH" "$TARGET_PATH"; then
            printf '\n' >> "$TARGET_PATH"
            ${pkgs.coreutils}/bin/cat "$DAILY_PATH" >> "$TARGET_PATH"
          fi
          ${pkgs.coreutils}/bin/rm -f "$DAILY_PATH"
        fi
      fi
    fi

    if [[ ! -e "$TARGET_PATH" ]]; then
      : > "$TARGET_PATH"
    fi

    TMP_LINK="$DAILY_PATH.tmp"
    ${pkgs.coreutils}/bin/ln -sfn "$TARGET_REL" "$TMP_LINK"
    ${pkgs.coreutils}/bin/mv -Tf "$TMP_LINK" "$DAILY_PATH"
  '';

  notesSyncScript = pkgs.writeShellScript "keystone-notes-sync" ''
    set -euo pipefail

    NOTES_GIT_DIR=${lib.escapeShellArg "${cfg.path}/.git"}

    repo_sync() {
      ${pkgs.keystone.repo-sync}/bin/repo-sync \
        --repo ${lib.escapeShellArg cfg.repo} \
        --path ${lib.escapeShellArg cfg.path} \
        --commit-prefix ${lib.escapeShellArg cfg.commitPrefix} \
        --log-dir ${lib.escapeShellArg "${config.home.homeDirectory}/.local/state/notes-sync/logs"}
    }

    if [[ ! -d "$NOTES_GIT_DIR" ]]; then
      repo_sync

      # First-run daily rollover needs a second sync pass because repo-sync is
      # responsible for the initial clone.
      ${lib.optionalString cfg.daily.enable ''
        ${dailyRolloverScript}
        repo_sync
      ''}
    else
      ${lib.optionalString cfg.daily.enable ''
        ${dailyRolloverScript}
      ''}
      repo_sync
    fi
  '';
in
{
  imports = [ ../shared/experimental.nix ];

  options.keystone.notes = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.keystone.experimental;
      description = "Enable Keystone notes sync (EXPERIMENTAL). Auto-enabled when keystone.experimental = true.";
    };

    repo = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Git repository URL for the notes repo. Empty disables sync.";
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

    sync = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the systemd sync service and timer. Disable when another mechanism handles sync (e.g. NixOS-level agent sync).";
      };
    };

    daily = {
      enable = lib.mkEnableOption "git-tracked daily note rollover";

      symlinkPath = lib.mkOption {
        type = lib.types.str;
        default = "daily.md";
        description = "Path to the current daily note entrypoint, relative to the notes repo root.";
      };

      journalPath = lib.mkOption {
        type = lib.types.str;
        default = "journal";
        description = "Directory for dated daily notes, relative to the notes repo root.";
      };

      dateFormat = lib.mkOption {
        type = lib.types.str;
        default = "%Y-%m-%d";
        description = "Format string passed to date(1) when deriving the dated daily note filename.";
      };
    };

  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optionals cfg.daily.enable [
      {
        assertion =
          !lib.hasPrefix "/" cfg.daily.symlinkPath && !pathHasParentTraversal cfg.daily.symlinkPath;
        message = "keystone.notes.daily.symlinkPath must stay under keystone.notes.path and must not contain '..' segments.";
      }
      {
        assertion =
          !lib.hasPrefix "/" cfg.daily.journalPath && !pathHasParentTraversal cfg.daily.journalPath;
        message = "keystone.notes.daily.journalPath must stay under keystone.notes.path and must not contain '..' segments.";
      }
    ];

    systemd.user.services.keystone-notes-sync = lib.mkIf (cfg.sync.enable && cfg.repo != "") {
      Unit = {
        Description = "Sync notes repo via repo-sync";
      };

      Service = {
        Type = "oneshot";
        Environment = [
          "SSH_AUTH_SOCK=${sshAuthSock}"
        ];
        ExecStart = "${notesSyncScript}";
      };
    };

    systemd.user.timers.keystone-notes-sync = lib.mkIf (cfg.sync.enable && cfg.repo != "") {
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
