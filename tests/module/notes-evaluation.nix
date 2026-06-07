{
  pkgs,
  self,
  home-manager,
}:
let
  normalizeCommand =
    value: if builtins.isList value then builtins.concatStringsSep "\n" value else value;

  evalNotesWithOs =
    osConfig: extraModules:
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = if osConfig == null then { } else { inherit osConfig; };
      modules = [
        self.homeModules.notes
        {
          nixpkgs.overlays = [ self.overlays.default ];
          home.username = "testuser";
          home.homeDirectory = "/home/testuser";
          home.stateVersion = "25.05";

          keystone.notes = {
            enable = true;
            repo = "git@example.com:test/notes.git";
          };
        }
      ]
      ++ extraModules;
    }).config;

  evalNotes = evalNotesWithOs null;

  osConfigFor = hostName: notesDailyHost: {
    networking.hostName = hostName;
    keystone.services.notesDaily.host = notesDailyHost;
  };

  enabledConfig = evalNotes [
    {
      keystone.notes = {
        syncInterval = "hourly";
        daily.enable = true;
      };
    }
  ];

  disabledConfig = evalNotes [ ];

  singletonHostConfig = evalNotesWithOs (osConfigFor "ocean" "ocean") [ ];

  singletonClientConfig = evalNotesWithOs (osConfigFor "ncrmro-laptop" "ocean") [ ];

  singletonClientExplicitResult = builtins.tryEval (
    evalNotesWithOs (osConfigFor "ncrmro-laptop" "ocean") [
      {
        keystone.notes.daily.enable = true;
      }
    ]
  );

  badConfigResult = builtins.tryEval (evalNotes [
    {
      keystone.notes.daily = {
        enable = true;
        symlinkPath = "/tmp/daily.md";
      };
    }
  ]);

  parentTraversalResult = builtins.tryEval (evalNotes [
    {
      keystone.notes.daily = {
        enable = true;
        symlinkPath = "../daily.md";
      };
    }
  ]);

  enabledExecStart = normalizeCommand enabledConfig.systemd.user.services.keystone-notes-sync.Service.ExecStart;
  disabledExecStart = normalizeCommand disabledConfig.systemd.user.services.keystone-notes-sync.Service.ExecStart;
  singletonHostExecStart = normalizeCommand singletonHostConfig.systemd.user.services.keystone-notes-sync.Service.ExecStart;
  singletonClientExecStart = normalizeCommand singletonClientConfig.systemd.user.services.keystone-notes-sync.Service.ExecStart;
  execStartPost = normalizeCommand (
    enabledConfig.systemd.user.services.keystone-notes-sync.Service.ExecStartPost or ""
  );
  timerCalendar = enabledConfig.systemd.user.timers.keystone-notes-sync.Timer.OnCalendar;
  assertionTripped = !badConfigResult.success;
  parentTraversalAssertionTripped = !parentTraversalResult.success;
  singletonClientAssertionTripped = !singletonClientExplicitResult.success;
  boolString = value: if value then "true" else "false";
in
pkgs.runCommand "notes-evaluation" { } ''
    set -euo pipefail
    errors=0

    enabled_script="${enabledExecStart}"
    disabled_script="${disabledExecStart}"
    exec_start_post_file="$TMPDIR/exec-start-post.sh"
    rollover_helper="$(grep -o '/nix/store/[^[:space:]]*-keystone-notes-daily-rollover' "$enabled_script" | head -n 1 || true)"

    cat >"$exec_start_post_file" <<'EOF_EXEC_START_POST'
  ${execStartPost}
  EOF_EXEC_START_POST

    check() {
      if [ "$1" = "true" ]; then
        echo "PASS: $2"
      else
        echo "FAIL: $2" >&2
        errors=$((errors + 1))
      fi
    }

    if ! grep -Fq 'keystone-notes-daily-rollover' "$enabled_script"; then
      echo "FAIL: daily-enabled sync script does not invoke rollover helper" >&2
      cat "$enabled_script" >&2
      errors=$((errors + 1))
    else
      echo "PASS: daily-enabled sync script invokes rollover helper"
    fi

    if [ -z "$rollover_helper" ] || ! grep -Fq 'TARGET_REL="$JOURNAL_REL/$TODAY_FILE_NAME"' "$rollover_helper"; then
      echo "FAIL: daily-enabled sync script does not derive the dated journal target" >&2
      if [ -n "$rollover_helper" ]; then
        cat "$rollover_helper" >&2
      else
        cat "$enabled_script" >&2
      fi
      errors=$((errors + 1))
    else
      echo "PASS: daily-enabled sync script derives the dated journal target"
    fi

    if [ -z "$rollover_helper" ] || ! grep -Fq 'if [[ "$DAILY_REAL" == "$TARGET_REAL" ]]' "$rollover_helper"; then
      echo "FAIL: daily-enabled sync script does not guard against daily/target path aliasing" >&2
      if [ -n "$rollover_helper" ]; then
        cat "$rollover_helper" >&2
      else
        cat "$enabled_script" >&2
      fi
      errors=$((errors + 1))
    else
      echo "PASS: daily-enabled sync script guards against daily/target path aliasing"
    fi

    if ! grep -Fq '/bin/repo-sync' "$enabled_script"; then
      echo "FAIL: daily-enabled sync script does not wrap repo-sync" >&2
      cat "$enabled_script" >&2
      errors=$((errors + 1))
    else
      echo "PASS: daily-enabled sync script wraps repo-sync"
    fi

    if grep -Fq 'keystone-notes-daily-rollover' "$disabled_script"; then
      echo "FAIL: daily-disabled sync script should not invoke rollover helper" >&2
      cat "$disabled_script" >&2
      errors=$((errors + 1))
    else
      echo "PASS: daily-disabled sync script skips rollover helper"
    fi

    singleton_host_script="${singletonHostExecStart}"
    singleton_client_script="${singletonClientExecStart}"

    if ! grep -Fq 'keystone-notes-daily-rollover' "$singleton_host_script"; then
      echo "FAIL: notesDaily singleton host should invoke rollover helper by default" >&2
      cat "$singleton_host_script" >&2
      errors=$((errors + 1))
    else
      echo "PASS: notesDaily singleton host invokes rollover helper by default"
    fi

    if grep -Fq 'keystone-notes-daily-rollover' "$singleton_client_script"; then
      echo "FAIL: notesDaily non-host should not invoke rollover helper by default" >&2
      cat "$singleton_client_script" >&2
      errors=$((errors + 1))
    else
      echo "PASS: notesDaily non-host skips rollover helper by default"
    fi

    check "${boolString singletonClientAssertionTripped}" \
      "notesDaily non-host explicit daily enable trips the module assertion"

    if [ "${timerCalendar}" != "hourly" ]; then
      echo "FAIL: expected timer OnCalendar=hourly, got '${timerCalendar}'" >&2
      errors=$((errors + 1))
    else
      echo "PASS: timer respects custom OnCalendar"
    fi

    check "${boolString assertionTripped}" \
      "absolute daily symlink paths trip the module assertion"

    check "${boolString parentTraversalAssertionTripped}" \
      "parent traversal in daily symlink paths trips the module assertion"

    if [ "$errors" -gt 0 ]; then
      echo "$errors test(s) failed" >&2
      exit 1
    fi

    touch "$out"
''
