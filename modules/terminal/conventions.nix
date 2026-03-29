# Tool-native instruction file generation from keystone conventions.
#
# See conventions/tool.cli-coding-agents.md
# See conventions/process.keystone-development-mode.md (dev-mode repos AGENTS.md)
# Implements REQ-017 (Conventions and Grafana MCP)
# Implements REQ-021 (Agent Context Budget)
#
# Reads archetypes.yaml from the keystone-conventions Nix store derivation and
# writes conventions to each CLI coding tool's native instruction file path:
#   - ~/.claude/CLAUDE.md   (Claude Code)
#   - ~/.gemini/GEMINI.md   (Gemini CLI)
#   - ~/.codex/AGENTS.md    (Codex)
#   - OpenCode reads ~/.claude/CLAUDE.md via legacy compat — no separate file needed
#
# When keystone.development = true, also generates:
#   - ~/.keystone/repos/AGENTS.md  using the keystone-developer archetype
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
  aiCapabilities = config.keystone.terminal.aiExtensions.resolvedCapabilities or [ ];
  aiCommandIds = config.keystone.terminal.aiExtensions.publishedCommands or [ ];

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

  # Compose the AGENTS.md content
  agentsMdContent = concatStringsSep "\n\n---\n\n" (
    [
      ''
        # Keystone Conventions

        Archetype: **${cfg.archetype}**
        ${archetypeConfig.description or ""}
      ''
      ''
        ## Keystone session

        - Canonical instruction path: `~/.keystone/AGENTS.md`
        - Development mode: ${if config.keystone.development then "enabled" else "disabled"}
        - Available Keystone capabilities: ${
          if aiCapabilities == [ ] then "_none_" else concatStringsSep ", " aiCapabilities
        }
        - Published Keystone commands: ${
          if aiCommandIds == [ ] then "_none_" else concatStringsSep ", " aiCommandIds
        }
      ''
      (optionalString (elem "notes" aiCapabilities) ''
        ## Notes command guidance

        - Route durable note capture, note cleanup, inbox promotion, and notebook repair requests through `ks.notes`.
        - Shared-surface note refs MUST use normalized VCS frontmatter values such as `repo_ref: gh:ncrmro/keystone`, `issue_ref: gh:ncrmro/keystone#123`, `milestone_ref: gh:ncrmro/keystone#12`, or `pr_ref: gh:ncrmro/keystone#456`.
        - Agents MUST NOT use placeholder note refs such as `gh:owner/repo-name#ID`.
      '')
    ]
    ++ inlinedConventions
    ++ optional (referencedConventions != [ ]) ''
      ## Reference Conventions

      The following conventions are available for on-demand context:

      ${concatStringsSep "\n" referencedConventions}
    ''
  );

  # --- Repos AGENTS.md (keystone.development = true only) ---

  isDev = config.keystone.development;
  reposArchetype = archetypesYaml.archetypes."keystone-developer" or { };

  reposInlinedConventions = map (
    name:
    let
      filepath = "${conventionsPath}/${name}.md";
    in
    if builtins.pathExists filepath then
      builtins.readFile filepath
    else
      "<!-- Convention ${name} not found -->"
  ) (reposArchetype.inlined_conventions or [ ]);

  # Convention links relative to ~/.keystone/repos/ — resolve to live checkout
  reposReferencedConventions = map (name: "- [${name}](ncrmro/keystone/conventions/${name}.md)") (
    reposArchetype.referenced_conventions or [ ]
  );

  # Repo inventory derived from keystone.repos (auto-populated from flake inputs)
  reposList = concatStringsSep "\n\n" (
    mapAttrsToList (
      name: _: "### \`${name}\` → [\`${name}/AGENTS.md\`](${name}/AGENTS.md)"
    ) config.keystone.repos
  );

  reposAgentsMdContent = concatStringsSep "\n\n---\n\n" (
    [
      ''
        # Keystone repos

        This directory (`~/.keystone/repos/`) is the agent-space root for the keystone
        system. It contains the core repositories that define and operate this machine's
        infrastructure. See `process.keystone-development` (inlined below) for the
        development workflow, tooling, and how changes flow through the system.

        ## Repositories

        ${reposList}
      ''
      (optionalString (elem "notes" aiCapabilities) ''
        ## Notes command guidance

        - Route durable note capture, note cleanup, inbox promotion, and notebook repair requests through `ks.notes`.
        - Shared-surface note refs MUST use normalized VCS frontmatter values such as `repo_ref: gh:ncrmro/keystone`, `issue_ref: gh:ncrmro/keystone#123`, `milestone_ref: gh:ncrmro/keystone#12`, or `pr_ref: gh:ncrmro/keystone#456`.
        - Agents MUST NOT use placeholder note refs such as `gh:owner/repo-name#ID`.
      '')
    ]
    ++ reposInlinedConventions
    ++ optional (reposReferencedConventions != [ ]) ''
      ## Reference Conventions

      The following conventions are available for on-demand context:

      ${concatStringsSep "\n" reposReferencedConventions}
    ''
  );

  # Conventions inlined in both the global CLAUDE.md and the repos AGENTS.md
  globalInlined = archetypeConfig.inlined_conventions or [ ];
  reposInlined = reposArchetype.inlined_conventions or [ ];
  overlappingConventions = filter (c: elem c globalInlined) reposInlined;
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
  };

  config = mkIf (terminalCfg.enable && cfg.enable) {
    # REQ-021: Warn when generated conventions exceed the context budget.
    # The global CLAUDE.md should be minimal — only host basics and essential
    # daily-use rules. Most conventions should be referenced, not inlined.
    warnings =
      let
        globalSize = builtins.stringLength agentsMdContent;
        reposSize = builtins.stringLength reposAgentsMdContent;
      in
      optional (globalSize > cfg.maxGlobalBytes)
        "keystone.terminal.conventions: generated CLAUDE.md is ${toString globalSize} bytes (budget: ${toString cfg.maxGlobalBytes} bytes, ~${
          toString (cfg.maxGlobalBytes / 4)
        } tokens). Move conventions from inlined_conventions to referenced_conventions in archetypes.yaml."
      ++
        optional (isDev && reposSize > cfg.maxGlobalBytes)
          "keystone.terminal.conventions: generated repos AGENTS.md is ${toString reposSize} bytes (budget: ${toString cfg.maxGlobalBytes} bytes, ~${
            toString (cfg.maxGlobalBytes / 4)
          } tokens). Move conventions from keystone-developer inlined_conventions to referenced_conventions in archetypes.yaml."
      ++
        optional (isDev && overlappingConventions != [ ])
          "keystone.terminal.conventions: ${toString (length overlappingConventions)} convention(s) are inlined in both CLAUDE.md (${cfg.archetype}) and repos AGENTS.md (keystone-developer), consuming duplicate context tokens: ${concatStringsSep ", " overlappingConventions}. Consider moving them to referenced_conventions in the keystone-developer archetype.";

    # Generate the canonical Keystone instruction file and derive tool-native
    # instruction files from the same content.
    home.file.".keystone/AGENTS.md".text = agentsMdContent;
    home.file.".claude/CLAUDE.md".text = agentsMdContent;
    home.file.".gemini/GEMINI.md".text = agentsMdContent;
    home.file.".codex/AGENTS.md".text = agentsMdContent;
    home.file.".config/opencode/AGENTS.md".text = agentsMdContent;

    # Expose the full conventions directory for on-demand reading
    # (referenced conventions link to Nix store paths in this directory)
    home.file.".config/keystone/conventions".source = conventionsPath;

    # Generate ~/.keystone/repos/AGENTS.md when in development mode.
    # Uses the keystone-developer archetype with the repo inventory derived
    # from keystone.repos. Convention links are relative to the repos root
    # so they resolve to the live ncrmro/keystone checkout.
    home.file.".keystone/repos/AGENTS.md" = mkIf isDev {
      text = reposAgentsMdContent;
    };
  };
}
