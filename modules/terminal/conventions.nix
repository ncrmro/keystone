# Tool-native instruction file generation from keystone conventions.
#
# See conventions/tool.cli-coding-agents.md
# Implements REQ-017 (Conventions and Grafana MCP)
# Implements REQ-024 (Archetype Role Sub-Agents and Skills)
#
# Reads archetypes.yaml from the keystone-conventions Nix store derivation and
# writes conventions to each CLI coding tool's native instruction file path:
#   - ~/.claude/CLAUDE.md           (Claude Code — global archetype instructions)
#   - ~/.gemini/GEMINI.md           (Gemini CLI)
#   - ~/.codex/AGENTS.md            (Codex)
#   - OpenCode reads ~/.claude/CLAUDE.md via legacy compat — no separate file needed
#
# Role sub-agents (REQ-024):
#   - ~/.claude/agents/<role>.md    (one per role defined in the archetype)
#
# Content separation:
#   - Keystone repo (conventions/): tool manuals, process docs, archetypes — shared
#   - nixos-config repo: SOUL.md, TEAM.md, SERVICES.md — per-deployment/per-agent
#   - This module generates ONLY the conventions layer
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.conventions;
  terminalCfg = config.keystone.terminal;
  conventionsPath = pkgs.keystone.keystone-conventions;

  # Read archetypes.yaml from the conventions derivation.
  # Guard: if the file doesn't exist, produce empty config (graceful degradation).
  archetypesFile = "${conventionsPath}/archetypes.yaml";
  hasArchetypes = builtins.pathExists archetypesFile;

  # Parse archetypes.yaml to determine which conventions to inline
  archetypesYaml =
    if hasArchetypes then
      builtins.fromJSON (
        builtins.readFile (
          pkgs.runCommand "archetypes-json" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
            yq -o=json '.' ${archetypesFile} > $out
          ''
        )
      )
    else
      { archetypes = { }; };

  # Get the archetype config
  archetypeConfig = archetypesYaml.archetypes.${cfg.archetype} or { };

  # Build inlined conventions content
  inlinedConventions = map (
    name:
    let
      # Convention names use dots (e.g., "process.version-control") but files
      # use the full name as filename (e.g., "process.version-control.md")
      filename = "${name}.md";
      filepath = "${conventionsPath}/${filename}";
    in
    if builtins.pathExists filepath then
      builtins.readFile filepath
    else
      "<!-- Convention ${name} not found -->"
  ) (archetypeConfig.inlined_conventions or [ ]);

  # Build referenced conventions as markdown links
  referencedConventions = map (
    name:
    let
      filename = "${name}.md";
    in
    "- [${name}](${conventionsPath}/${filename})"
  ) (archetypeConfig.referenced_conventions or [ ]);

  # ---------------------------------------------------------------------------
  # REQ-024: Role sub-agent generation
  # ---------------------------------------------------------------------------

  # Get roles map for the archetype (empty attrset if none defined)
  archetypeRoles = archetypeConfig.roles or { };

  # Helper: convert kebab-case to Title Case (e.g., "code-reviewer" → "Code Reviewer")
  toTitleCase =
    str:
    concatMapStringsSep " " (
      word: (toUpper (substring 0 1 word)) + (substring 1 (stringLength word - 1) word)
    ) (splitString "-" str);

  # Build content for a single role sub-agent file.
  # Format: YAML frontmatter + compiled convention content per role.
  buildRoleContent =
    roleName: roleCfg:
    let
      roleDescription = roleCfg.description or roleName;
      roleDisplayName = toTitleCase roleName;
      conventionContents = map (
        name:
        let
          filepath = "${conventionsPath}/${name}.md";
        in
        if builtins.pathExists filepath then
          "## ${name}\n\n" + builtins.readFile filepath
        else
          "<!-- Convention ${name} not found -->"
      ) (roleCfg.conventions or [ ]);
      body = concatStringsSep "\n\n---\n\n" conventionContents;
    in
    ''
      ---
      name: ${roleDisplayName}
      description: ${roleDescription}
      ---

    ''
    + body;

  # Build the attrset of home.file entries for role sub-agent files.
  # Each role in the archetype becomes ~/.claude/agents/<role-name>.md.
  roleSubAgentFiles =
    if cfg.roleSubAgents.enable && archetypeRoles != { } then
      mapAttrs' (
        roleName: roleCfg:
        nameValuePair ".claude/agents/${roleName}.md" { text = buildRoleContent roleName roleCfg; }
      ) archetypeRoles
    else
      { };

  # Compose the AGENTS.md content
  agentsMdContent = concatStringsSep "\n\n---\n\n" (
    [
      ''
        # Keystone Conventions

        Archetype: **${cfg.archetype}**
        ${archetypeConfig.description or ""}
      ''
    ]
    ++ inlinedConventions
    ++ optional (referencedConventions != [ ]) ''
      ## Reference Conventions

      The following conventions are available for on-demand context:

      ${concatStringsSep "\n" referencedConventions}
    ''
  );
in
{
  options.keystone.terminal.conventions = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable convention generation at each CLI coding tool's native
        instruction file path (~/.claude/CLAUDE.md, ~/.gemini/GEMINI.md,
        ~/.codex/AGENTS.md). See conventions/tool.cli-coding-agents.md.
      '';
    };

    archetype = mkOption {
      type = types.str;
      default = "keystone-system-host";
      description = ''
        The archetype to use for AGENTS.md generation. Determines which
        conventions are inlined vs referenced. See conventions/archetypes.yaml
        for available archetypes (keystone-system-host, engineer, product).
      '';
    };

    maxGlobalBytes = mkOption {
      type = types.int;
      default = 16000;
      description = ''
        Maximum allowed size in bytes for the generated global CLAUDE.md.
        A build warning is emitted when the content exceeds this limit.
        Default: 16000 bytes (~4000 tokens). See REQ-021.
      '';
    };

    roleSubAgents = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Generate per-role Claude Code sub-agent files in ~/.claude/agents/<role>.md
          from the archetype's roles defined in archetypes.yaml. Each file contains
          YAML frontmatter (name, description) and compiled convention content for
          that role. Set to false to suppress sub-agent generation without affecting
          the global CLAUDE.md. See REQ-024.
        '';
      };
    };
  };

  config = mkIf (terminalCfg.enable && cfg.enable) {
    # REQ-021: Warn when generated conventions exceed the context budget.
    # The global CLAUDE.md should be minimal — only host basics and essential
    # daily-use rules. Most conventions should be referenced, not inlined.
    warnings =
      let
        contentSize = builtins.stringLength agentsMdContent;
      in
      optional (contentSize > cfg.maxGlobalBytes)
        "keystone.terminal.conventions: generated CLAUDE.md is ${toString contentSize} bytes (budget: ${toString cfg.maxGlobalBytes} bytes, ~${
          toString (cfg.maxGlobalBytes / 4)
        } tokens). Move conventions from inlined_conventions to referenced_conventions in archetypes.yaml.";

    # Write conventions to each tool's native instruction file path.
    # OpenCode reads ~/.claude/CLAUDE.md via legacy compat — no separate file.
    home.file.".claude/CLAUDE.md".text = agentsMdContent;
    home.file.".gemini/GEMINI.md".text = agentsMdContent;
    home.file.".codex/AGENTS.md".text = agentsMdContent;

    # REQ-024: Generate per-role Claude Code sub-agent files.
    # Each role in the archetype becomes ~/.claude/agents/<role>.md.
    # home.file is an attrset; this merge adds role files alongside the globals above.
    home.file = roleSubAgentFiles;

    # Expose the full conventions directory for on-demand reading
    # (referenced conventions link to Nix store paths in this directory)
    home.file.".config/keystone/conventions".source = conventionsPath;
  };
}
