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
in
{
  imports = [ ../shared/experimental.nix ];

  options.keystone.terminal.agents = {
    enable = mkOption {
      type = types.bool;
      default = config.keystone.experimental;
      defaultText = literalExpression "config.keystone.experimental";
      description = ''
        Install user agent definitions to every CLI coding tool with a native
        subagent directory (EXPERIMENTAL). Auto-enables when
        keystone.experimental is true; can be enabled per-host without flipping
        the global experimental flag.
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

  config = mkIf (terminalCfg.enable && cfg.enable && cfg.definitions != { }) {
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
      ) cfg.definitions
    );
  };
}
