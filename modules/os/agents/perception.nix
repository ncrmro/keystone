# Agent perception layer: screenshot sync and activity processor as systemd user services.
#
# Implements REQ-024 (Perception Layer) — configuration scaffolding only.
# Actual scripts are added in subsequent PRs; services use placeholder ExecStart
# that logs "not yet implemented" and exits 0.
#
# Services created per agent (when perception.enable = true):
# - agent-{name}-screenshot-sync: uploads screenshots to Immich on a timer
# - agent-{name}-perception-processor: collects PDFs, transcripts, photos → notes
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

  # Filter to agents with perception enabled
  perceptionAgents = filterAttrs (_: agentCfg: agentCfg.perception.enable) localAgents;

  # Filter to agents with perception + desktop (needed for screenshot sync)
  screenshotAgents = filterAttrs (_: agentCfg: agentCfg.desktop.enable) perceptionAgents;
in
{
  config = mkIf (osCfg.enable && perceptionAgents != { }) {
    systemd.user.services = mkMerge (
      # Screenshot sync services (only for agents with desktop enabled)
      (mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        mkIf agentCfg.perception.screenshots.enable {
          "agent-${name}-screenshot-sync" = {
            description = "Sync screenshots to Immich for ${username}";
            unitConfig.ConditionUser = username;
            serviceConfig = {
              Type = "oneshot";
              SyslogIdentifier = "agent-${name}-screenshot-sync";
            };
            # Placeholder — actual script added in Phase 3 (feat/perception-screenshot-sync)
            script = ''
              echo "screenshot-sync: not yet implemented for ${username}"
            '';
          };
        }
      ) screenshotAgents)
      ++
        # Perception processor services (for all perception agents)
        (mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
          in
          mkIf agentCfg.perception.processor.enable {
            "agent-${name}-perception-processor" = {
              description = "Perception processor for ${username}";
              unitConfig.ConditionUser = username;
              environment = {
                PATH = lib.mkForce "/etc/profiles/per-user/${username}/bin:/run/wrappers/bin:/run/current-system/sw/bin:${lib.makeBinPath [ pkgs.nix ]}";
              };
              serviceConfig = {
                Type = "oneshot";
                TimeoutStartSec = "30m";
                SyslogIdentifier = "agent-${name}-perception-processor";
              };
              # Placeholder — actual script added in Phase 3 (feat/perception-processor)
              script = ''
                echo "perception-processor: not yet implemented for ${username}"
              '';
            };
          }
        ) perceptionAgents)
    );

    systemd.user.timers = mkMerge (
      # Screenshot sync timers
      (mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        mkIf (agentCfg.perception.screenshots.enable && agentCfg.desktop.enable) {
          "agent-${name}-screenshot-sync" = {
            wantedBy = [ "default.target" ];
            unitConfig.ConditionUser = username;
            timerConfig = {
              OnCalendar = agentCfg.perception.screenshots.syncOnCalendar;
              Persistent = true;
            };
          };
        }
      ) screenshotAgents)
      ++
        # Perception processor timers
        (mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
          in
          mkIf agentCfg.perception.processor.enable {
            "agent-${name}-perception-processor" = {
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = username;
              timerConfig = {
                OnCalendar = agentCfg.perception.processor.onCalendar;
                Persistent = true;
              };
            };
          }
        ) perceptionAgents)
    );
  };
}
