# User-defined agent (subagent) definitions for CLI coding tools.
#
# Each entry in `definitions` is installed as <name>.md under every supported
# tool's native subagent directory so the same agent persona is discoverable
# from every CLI:
#
#   ~/.claude/agents/<name>.md  — Claude Code
#   ~/.copilot/agents/<name>.md — GitHub Copilot CLI
#
# Gemini CLI, Codex, and OpenCode don't currently expose a native subagent
# discovery directory (they ship "skills" instead, which are a distinct
# concept). When upstream support lands, extend the install list below.
#
# Gated behind keystone.experimental per process.enable-by-default rule 17 —
# the install layout, frontmatter schema, and tool coverage are still in flux.
{
  config,
  lib,
  osConfig ? null,
  ...
}:

with lib;

let
  cfg = config.keystone.terminal.agents;
  terminalCfg = config.keystone.terminal;

  installPaths = name: [
    ".claude/agents/${name}.md"
    ".copilot/agents/${name}.md"
  ];

  # Bridge to NixOS-level keystone.os.agents via the standard osConfig pattern
  # (see modules/terminal/generated-agent-assets.nix:30-34). Auto-derive
  # subagent definitions from each agent's `persona` so a single declaration on
  # the OS module surfaces in every home-manager profile that enables this
  # module — both the human user and each agent user.
  osAgents =
    if osConfig != null && osConfig.keystone ? os && osConfig.keystone.os ? agents then
      osConfig.keystone.os.agents
    else
      { };
  osDerivedDefinitions = mapAttrs (_: a: a.persona) (filterAttrs (_: a: a.persona != null) osAgents);
  effectiveDefinitions = osDerivedDefinitions // cfg.definitions;
in
{
  imports = [ ../shared/experimental.nix ];

  options.keystone.terminal.agents = {
    enable = mkOption {
      type = types.bool;
      default = config.keystone.experimental || osDerivedDefinitions != { };
      defaultText = literalExpression "config.keystone.experimental || osDerivedDefinitions != { }";
      description = ''
        Install user agent definitions to every CLI coding tool with a native
        subagent directory (EXPERIMENTAL). Auto-enables when
        keystone.experimental is true OR any keystone.os.agents.<name>.persona
        is declared — the latter is a stronger explicit opt-in. Can also be
        set per-host without flipping the global experimental flag.
      '';
    };

    definitions = mkOption {
      type = types.attrsOf types.path;
      default = { };
      example = literalExpression ''
        {
          drago = ./agents/drago.md;
          luce  = ./agents/luce.md;
          vega  = ./agents/vega.md;
        }
      '';
      description = ''
        Map of agent name → path to a markdown file with Claude-compatible
        agent frontmatter (`name`, `description`, `skills`, `memory`). Each
        file is installed as `<name>.md` under every supported tool's
        subagent directory.

        See conventions/tool.cli-coding-agents.md for the per-tool discovery
        paths and which tools currently support native subagent files.
      '';
    };
  };

  config = mkIf (terminalCfg.enable && cfg.enable && effectiveDefinitions != { }) {
    # Legacy hand-symlinked layouts may have ~/.claude/agents (or .copilot/)
    # pointing at a now-defunct dotfiles checkout. Home-manager refuses to
    # write under a symlink it didn't create, so strip dangling ones first.
    home.activation.cleanupAgentDirSymlinks = hm.dag.entryBefore [ "checkLinkTargets" ] ''
      for d in "$HOME/.claude/agents" "$HOME/.copilot/agents"; do
        if [ -L "$d" ]; then
          rm -f "$d"
        fi
      done
    '';

    home.file = mkMerge (
      mapAttrsToList (
        name: source:
        listToAttrs (
          map (path: {
            name = path;
            value = { inherit source; };
          }) (installPaths name)
        )
      ) effectiveDefinitions
    );
  };
}
