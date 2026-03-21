# Claude Code slash commands generated from DeepWork workflows.
#
# Ships /project.* and /milestone.* commands to all machines via home.file.
# Each command is a thin wrapper that tells the agent to call DeepWork MCP
# tools with the correct job_name and workflow_name.
#
# Dev mode (REQ-018): When keystone.terminal.devMode.keystonePath is set,
# commands are out-of-store symlinks to the checkout — editable in place.
# When null (locked mode), commands are copied into the Nix store (immutable).
{
  config,
  lib,
  ...
}:
with lib;
let
  terminalCfg = config.keystone.terminal;
  cfg = config.keystone.terminal.claudeCodeCommands;
  devPath = terminalCfg.devMode.keystonePath;
  isDev = devPath != null;

  # All command files live in ./claude-code-commands/ relative to this module.
  commandFiles = [
    "project.onboard.md"
    "project.press_release.md"
    "project.success.md"
    "milestone.setup.md"
    "milestone.eng_handoff.md"
  ];

  # In dev mode: out-of-store symlink to the editable checkout.
  # In locked mode: Nix store copy (immutable).
  mkCommandFile = name:
    if isDev then {
      source = config.lib.file.mkOutOfStoreSymlink
        "${devPath}/modules/terminal/claude-code-commands/${name}";
    } else {
      source = ./claude-code-commands/${name};
    };
in
{
  options.keystone.terminal.claudeCodeCommands = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Generate Claude Code slash commands for DeepWork workflows";
    };
  };

  config = mkIf (terminalCfg.enable && terminalCfg.ai.enable && cfg.enable) {
    home.file = listToAttrs (map (name: {
      name = ".claude/commands/${name}";
      value = mkCommandFile name;
    }) commandFiles);
  };
}
