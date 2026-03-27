# Agent notes: task loop, scheduler as systemd.user.services with linger.
# Notes sync is handled by the home-manager notes module (keystone-notes-sync).
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
  builtInTaskLoopProfiles = {
    embedding = {
      claude = { };
      gemini = { };
      codex = { };
    };
    fast = {
      claude = {
        model = "haiku";
        fallbackModel = "sonnet";
        effort = "low";
      };
      gemini = {
        model = "gemini-3-flash-preview";
      };
      codex = { };
    };
    medium = {
      claude = {
        model = "sonnet";
        fallbackModel = "opus";
        effort = "medium";
      };
      gemini = {
        model = "auto-gemini-3";
      };
      codex = { };
    };
    max = {
      claude = {
        model = "opus";
        effort = "max";
      };
      gemini = {
        model = "auto-gemini-3";
      };
      codex = { };
    };
  };

  serializeTaskLoopStage =
    stageCfg:
    builtins.toJSON {
      profile = stageCfg.profile;
      provider = stageCfg.provider;
      model = stageCfg.model;
      fallbackModel = stageCfg.fallbackModel;
      effort = stageCfg.effort;
    };

  projectIndexHelper = pkgs.writeShellScriptBin "keystone-project-index" (
    builtins.readFile ./scripts/project-index.sh
  );

  # Task loop script: pre-fetch sources, ingest, prioritize, execute.
  # All tools (yq, jq, bash, git, claude, etc.) come from the agent's
  # home-manager profile PATH — only config values are substituted here.
  agentTaskLoopScript =
    name: agentCfg:
    let
      notesDir = agentCfg.notes.path;
      maxTasks = agentCfg.notes.taskLoop.maxTasks;
      defaultsJson = serializeTaskLoopStage agentCfg.notes.taskLoop.defaults;
      ingestJson = serializeTaskLoopStage agentCfg.notes.taskLoop.ingest;
      prioritizeJson = serializeTaskLoopStage agentCfg.notes.taskLoop.prioritize;
      executeJson = serializeTaskLoopStage agentCfg.notes.taskLoop.execute;
      profilesJson = builtins.toJSON (
        lib.recursiveUpdate builtInTaskLoopProfiles agentCfg.notes.taskLoop.profiles
      );
      githubUsername = agentCfg.github.username;
      forgejoUsername = agentCfg.forgejo.username;
    in
    pkgs.replaceVars ./scripts/task-loop.sh {
      inherit
        defaultsJson
        executeJson
        forgejoUsername
        githubUsername
        ingestJson
        maxTasks
        notesDir
        prioritizeJson
        profilesJson
        projectIndexHelper
        ;
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
    # Agent task loop and scheduler as systemd user services.
    # Notes sync is handled by the home-manager notes module (keystone-notes-sync).
    systemd.user.services = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        {
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
              PROMETHEUS_TEXTFILE_DIR = config.keystone.os.observability.nodeExporter.textfileDirectory;
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
            environment.PROMETHEUS_TEXTFILE_DIR =
              config.keystone.os.observability.nodeExporter.textfileDirectory;
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
