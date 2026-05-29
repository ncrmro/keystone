# Simplified Pi task runner systemd integration.
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

  runnerAgents = filterAttrs (_: agentCfg: agentCfg.piTaskRunner.enable) localAgents;

  profilePath =
    username:
    "/etc/profiles/per-user/${username}/bin:/run/wrappers/bin:/run/current-system/sw/bin:${lib.makeBinPath [ pkgs.nix ]}";
in
{
  config = mkIf (osCfg.enable && runnerAgents != { }) {
    systemd.user.services = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
          runner = agentCfg.piTaskRunner;
        in
        {
          "agent-${name}-pi-task-runner" = {
            description = "Pi assignment runner for ${username}";
            unitConfig.ConditionUser = username;
            environment = {
              PATH = lib.mkForce (profilePath username);
              KS_AGENT_NAME = name;
              SSH_AUTH_SOCK = "/run/agent-${name}-ssh-agent/agent.sock";
              GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=accept-new";
            };
            serviceConfig = {
              Type = "oneshot";
              WorkingDirectory = "/home/${username}";
              TimeoutStartSec = runner.timeout;
              SyslogIdentifier = "agent-${name}-pi-task-runner";
              LogRateLimitIntervalSec = 0;
            };
            script = ''
              exec ${pkgs.keystone.pi-task-runner}/bin/pi-task-runner \
                --agent ${escapeShellArg name} \
                --model ${escapeShellArg runner.model} \
                --sources ${escapeShellArg runner.sources} \
                --home /home/${username}
            '';
          };
        }
      ) runnerAgents
    );

    systemd.user.timers = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        {
          "agent-${name}-pi-task-runner" = {
            wantedBy = [ "default.target" ];
            unitConfig.ConditionUser = username;
            timerConfig = {
              OnCalendar = agentCfg.piTaskRunner.onCalendar;
              Persistent = true;
              Unit = "agent-${name}-pi-task-runner.service";
            };
          };
        }
      ) runnerAgents
    );
  };
}
