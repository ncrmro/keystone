# Per-agent task-loop: one systemd user timer + service per agent.
#
# Each tick invokes a CLI coding agent (claude/codex/gemini) with a named
# skill. The skill content lives in the consumer flake under
# ~/.agents/skills/<skill>/ (symlinked by the consumer's home-manager).
#
# This module owns the timer + service only. No state files, no notes,
# no pre-fetch logic, no retry/backoff — the skill itself drives the work
# and exits quickly when there is nothing to do.
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib) osCfg cfg localAgents;

  taskLoopAgents = filterAttrs (_: agentCfg: agentCfg.taskLoop.enable) localAgents;

  # Per-tool invocation. The CLI is resolved through the agent's
  # home-manager profile PATH; no Nix store paths here so the agent can
  # iterate on its own toolchain version without a system rebuild.
  invocation =
    tool: skill:
    let
      prompt = "Run the ${skill} skill.";
    in
    {
      claude = "unset CLAUDECODE; claude --print -p ${escapeShellArg prompt}";
      codex = "codex exec ${escapeShellArg prompt}";
      gemini = "gemini --prompt ${escapeShellArg prompt}";
    }
    .${tool};
in
{
  config = mkIf (osCfg.enable && taskLoopAgents != { }) {
    systemd.user.services = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        {
          "agent-${name}-task-loop" = {
            description = "Task loop for ${username} (${agentCfg.taskLoop.tool} / ${agentCfg.taskLoop.skill})";
            unitConfig.ConditionUser = username;
            environment = {
              HOME = "/home/${username}";
              XDG_DATA_HOME = "/home/${username}/.local/share";
              XDG_CONFIG_HOME = "/home/${username}/.config";
              XDG_STATE_HOME = "/home/${username}/.local/state";
              XDG_CACHE_HOME = "/home/${username}/.cache";
              # CRITICAL: bare CLI names must resolve via the agent's
              # home-manager profile so version/tooling tracks the agent,
              # not the system rebuild cadence. mkForce because NixOS
              # supplies a default PATH for user services that we need
              # to override rather than merge with.
              PATH = mkForce "/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin";
            };
            serviceConfig = {
              Type = "oneshot";
              # LLM invocations can run long; cap at 1h so a hung tick
              # doesn't block the next one indefinitely.
              TimeoutStartSec = "1h";
              SyslogIdentifier = "agent-${name}-task-loop";
            };
            script = invocation agentCfg.taskLoop.tool agentCfg.taskLoop.skill;
          };
        }
      ) taskLoopAgents
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
              OnCalendar = agentCfg.taskLoop.interval;
              Persistent = true;
            };
          };
        }
      ) taskLoopAgents
    );
  };
}
