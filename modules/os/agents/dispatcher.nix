# Agent dispatcher systemd integration [EXPERIMENTAL].
#
# Declares opt-in user service/path/timer units for a future dispatcher binary.
# The dispatcher implementation is intentionally external to this module.
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

  dispatcherAgents = filterAttrs (_: agentCfg: agentCfg.dispatcher.enable) localAgents;

  profilePath =
    username:
    "/etc/profiles/per-user/${username}/bin:/run/wrappers/bin:/run/current-system/sw/bin:${lib.makeBinPath [ pkgs.nix ]}";
in
{
  config = mkIf (osCfg.enable && dispatcherAgents != { }) {
    assertions = mapAttrsToList (name: agentCfg: {
      assertion = agentCfg.dispatcher.command != null;
      message = "keystone.os.agents.${name}.dispatcher.command must be set when dispatcher.enable = true";
    }) dispatcherAgents;

    systemd.user.services = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
          dispatcher = agentCfg.dispatcher;
          command = if dispatcher.command == null then "${pkgs.coreutils}/bin/false" else dispatcher.command;
        in
        {
          "agent-${name}-dispatcher" = {
            description = "Experimental task dispatcher for ${username}";
            unitConfig.ConditionUser = username;
            environment = {
              PATH = lib.mkForce (profilePath username);
              KS_AGENT_NAME = name;
              KS_TASKS_FILE = dispatcher.tasksFile;
              KS_PROJECTS_FILE = "/home/${username}/PROJECTS.yaml";
              SSH_AUTH_SOCK = "/run/agent-${name}-ssh-agent/agent.sock";
              GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=accept-new";
            };
            serviceConfig = {
              Type = "oneshot";
              WorkingDirectory = "/home/${username}";
              TimeoutStartSec = dispatcher.timeout;
              SyslogIdentifier = "agent-${name}-dispatcher";
              LogRateLimitIntervalSec = 0;
            };
            script = ''
              exec ${escapeShellArg command} ${escapeShellArgs dispatcher.args}
            '';
          };
        }
      ) dispatcherAgents
    );

    systemd.user.paths = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        {
          "agent-${name}-dispatcher" = {
            wantedBy = [ "default.target" ];
            unitConfig.ConditionUser = username;
            pathConfig = {
              PathChanged = agentCfg.dispatcher.tasksFile;
              Unit = "agent-${name}-dispatcher.service";
            };
          };
        }
      ) dispatcherAgents
    );

    systemd.user.timers = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        {
          "agent-${name}-dispatcher" = {
            wantedBy = [ "default.target" ];
            unitConfig.ConditionUser = username;
            timerConfig = {
              OnCalendar = agentCfg.dispatcher.onCalendar;
              Persistent = true;
              Unit = "agent-${name}-dispatcher.service";
            };
          };
        }
      ) dispatcherAgents
    );
  };
}
