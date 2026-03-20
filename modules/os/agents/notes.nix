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

  # Task loop script: pre-fetch sources, ingest, prioritize, execute.
  # All tools (yq, jq, bash, git, claude, etc.) come from the agent's
  # home-manager profile PATH — only config values are substituted here.
  agentTaskLoopScript =
    name: agentCfg:
    let
      notesDir = agentCfg.notes.path;
      maxTasks = agentCfg.notes.taskLoop.maxTasks;
      githubUsername = agentCfg.github.username;
      forgejoUsername = agentCfg.forgejo.username;
    in
    pkgs.replaceVars ./scripts/task-loop.sh {
      notesDir = notesDir;
      inherit maxTasks githubUsername forgejoUsername;
      agentName = name;
    };

  # Scheduler script: reads SCHEDULES.yaml, creates due tasks, triggers task loop.
  # All tools come from PATH — only config values are substituted here.
  agentSchedulerScript =
    name: agentCfg:
    let
      notesDir = agentCfg.notes.path;
    in
    pkgs.replaceVars ./scripts/scheduler.sh {
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
            # Use the agent's full home-manager profile for all tools (yq, jq,
            # bash, git, claude, himalaya, etc.). Nix and /run/current-system/sw/bin
            # are added as fallbacks for system tools not in the profile.
            environment = {
              PATH = lib.mkForce "/etc/profiles/per-user/${username}/bin:/run/wrappers/bin:/run/current-system/sw/bin:${lib.makeBinPath [ pkgs.nix ]}";
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
              exec ${pkgs.bash}/bin/bash ${agentTaskLoopScript name agentCfg}
            '';
          };

          "agent-${name}-scheduler" = {
            description = "Daily scheduler for ${username}";
            unitConfig.ConditionUser = username;
            environment.PATH = lib.mkForce "/etc/profiles/per-user/${username}/bin:/run/wrappers/bin:/run/current-system/sw/bin:${lib.makeBinPath [ pkgs.nix ]}";
            serviceConfig = {
              Type = "oneshot";
              SyslogIdentifier = "agent-${name}-scheduler";
            };
            script = ''
              exec ${pkgs.bash}/bin/bash ${agentSchedulerScript name agentCfg}
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
