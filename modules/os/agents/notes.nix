# Agent notes: sync, task loop, scheduler as systemd.user.services with linger.
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib) osCfg localAgents;

  # Task loop script: pre-fetch sources, ingest, prioritize, execute
  # Uses claude from the agent's home-manager profile PATH
  agentTaskLoopScript =
    name: agentCfg:
    let
      username = "agent-${name}";
      notesDir = agentCfg.notes.path;
      maxTasks = agentCfg.notes.taskLoop.maxTasks;
    in
    pkgs.replaceVars ./scripts/task-loop.sh {
      yq = "${pkgs.yq-go}/bin/yq";
      jq = "${pkgs.jq}/bin/jq";
      date = "${pkgs.coreutils}/bin/date";
      mkdir = "${pkgs.coreutils}/bin/mkdir";
      echo = "${pkgs.coreutils}/bin/echo";
      cat = "${pkgs.coreutils}/bin/cat";
      tee = "${pkgs.coreutils}/bin/tee";
      head = "${pkgs.coreutils}/bin/head";
      seq = "${pkgs.coreutils}/bin/seq";
      find = "${pkgs.findutils}/bin/find";
      sort = "${pkgs.coreutils}/bin/sort";
      rm = "${pkgs.coreutils}/bin/rm";
      flock = "${pkgs.util-linux}/bin/flock";
      sha256sum = "${pkgs.coreutils}/bin/sha256sum";
      notesDir = notesDir;
      inherit maxTasks;
      agentName = name;
    };

  # Scheduler script: reads SCHEDULES.yaml, creates due tasks, triggers task loop
  # Pure bash, no LLM
  agentSchedulerScript =
    name: agentCfg:
    let
      username = "agent-${name}";
      notesDir = agentCfg.notes.path;
    in
    pkgs.replaceVars ./scripts/scheduler.sh {
      yq = "${pkgs.yq-go}/bin/yq";
      date = "${pkgs.coreutils}/bin/date";
      mkdir = "${pkgs.coreutils}/bin/mkdir";
      echo = "${pkgs.coreutils}/bin/echo";
      tee = "${pkgs.coreutils}/bin/tee";
      tr = "${pkgs.coreutils}/bin/tr";
      seq = "${pkgs.coreutils}/bin/seq";
      notesDir = notesDir;
      agentName = name;
    };
in
{
  config = mkIf (osCfg.enable && localAgents != { }) {
    # Notes sync via repo-sync (user services for all agents)
    systemd.user.services = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        {
          "agent-${name}-notes-sync" = {
            description = "Sync notes repo for ${username}";
            unitConfig.ConditionUser = username;
            serviceConfig = {
              Type = "oneshot";
              SyslogIdentifier = "agent-${name}-notes-sync";
              ExecStart = builtins.concatStringsSep " " [
                "${pkgs.keystone.repo-sync}/bin/repo-sync"
                "--repo ${escapeShellArg agentCfg.notes.repo}"
                "--path ${escapeShellArg agentCfg.notes.path}"
                "--commit-prefix \"vault sync\""
                "--log-dir /home/${username}/.local/state/notes-sync/logs"
              ];
            };
            environment = {
              SSH_AUTH_SOCK = "/run/agent-${name}-ssh-agent/agent.sock";
              GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=accept-new";
            };
          };

          "agent-${name}-task-loop" = {
            description = "Autonomous task loop for ${username}";
            unitConfig.ConditionUser = username;
            # Use the agent's full home-manager profile instead of cherry-picking
            # packages. /etc/profiles/per-user/ includes everything from keystone.terminal
            # (himalaya, gh, git, openssh, coreutils, bash, etc.). Nix is added
            # explicitly since it's a system tool not in the home-manager profile.
            environment = {
              PATH = lib.mkForce "/etc/profiles/per-user/${username}/bin:${lib.makeBinPath [ pkgs.nix ]}";
              SSH_AUTH_SOCK = "/run/agent-${name}-ssh-agent/agent.sock";
              GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=accept-new";
            };
            serviceConfig = {
              Type = "oneshot";
              # Agent tasks (e.g. Claude) can run for extended periods; the
              # default 90s timeout would SIGKILL mid-execution, and flock
              # handles concurrency so the timer safely skips overlapping runs.
              TimeoutStartSec = "1h";
              SyslogIdentifier = "agent-${name}-task-loop";
              LogRateLimitIntervalSec = 0;
            };
            script = ''
              exec ${agentTaskLoopScript name agentCfg}
            '';
          };

          "agent-${name}-scheduler" = {
            description = "Daily scheduler for ${username}";
            unitConfig.ConditionUser = username;
            environment.PATH = lib.mkForce "/etc/profiles/per-user/${username}/bin:${lib.makeBinPath [ pkgs.nix ]}:/run/current-system/sw/bin";
            serviceConfig = {
              Type = "oneshot";
              SyslogIdentifier = "agent-${name}-scheduler";
            };
            script = ''
              exec ${agentSchedulerScript name agentCfg}
            '';
          };
        }
      ) localAgents
    );

    systemd.user.timers = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        {
          "agent-${name}-notes-sync" = {
            wantedBy = [ "default.target" ];
            unitConfig.ConditionUser = username;
            timerConfig = {
              OnCalendar = agentCfg.notes.syncOnCalendar;
              Persistent = true;
            };
          };

          "agent-${name}-task-loop" = {
            wantedBy = [ "default.target" ];
            unitConfig.ConditionUser = username;
            timerConfig = {
              OnCalendar = agentCfg.notes.taskLoop.onCalendar;
              Persistent = true;
            };
          };

          "agent-${name}-scheduler" = {
            wantedBy = [ "default.target" ];
            unitConfig.ConditionUser = username;
            timerConfig = {
              OnCalendar = agentCfg.notes.scheduler.onCalendar;
              Persistent = true;
            };
          };
        }
      ) localAgents
    );
  };
}
