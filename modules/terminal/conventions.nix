# Tool-native instruction file generation from keystone conventions.  [EXPERIMENTAL]
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
  conventionsEvalPath = ../../conventions;
  conventionsPath = pkgs.keystone.keystone-conventions;
  aiCapabilities = config.keystone.terminal.aiExtensions.resolvedCapabilities or [ ];
  aiCommandIds = config.keystone.terminal.aiExtensions.publishedCommands or [ ];

  # Read archetypes.yaml from the conventions derivation.
  # Guard: if the file doesn't exist, produce empty config (graceful degradation).
  archetypesFile = "${conventionsEvalPath}/archetypes.yaml";
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
      filepath = "${conventionsEvalPath}/${filename}";
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
        - Use `ks.notes` proactively when a task produces durable decisions, meaningful findings, or reusable operational context.
        - On Keystone systems, use `NOTES_DIR` as the canonical notebook root. It resolves to `keystone.notes.path` (`~/notes` for human users, per-agent notes paths for OS agents).
        - When note structure, tags, frontmatter, shared-surface refs, or zk workflow details matter, read `~/.config/keystone/conventions/process.notes.md` and `~/.config/keystone/conventions/tool.zk-notes.md`.
        - When a task is tied to an issue, pull request, or milestone, capture normalized refs in notes when known and keep the shared surface as the public system of record.
      '')
      ''
        ## Shared-surface tracking

        - For issue-backed work, follow `process.issue-journal` and post `Work Started` and `Work Update` comments on the source issue.
        - For milestone and board-backed work, follow `process.project-board` so issue and PR state stays visible on the shared board.
        - Treat issues, pull requests, milestones, and boards as the canonical public record for status, review state, and decisions that affect collaborators.
        - Use notes to preserve durable rationale and memory, not to replace shared-surface tracking.
      ''
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
      filepath = "${conventionsEvalPath}/${name}.md";
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
    mapAttrsToList (name: _: "### \`${name}\` → [\`${name}/AGENTS.md\`](${name}/AGENTS.md)") (
      filterAttrs (name: _: !(hasSuffix "/notes" name)) config.keystone.repos
    )
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
        - Use `ks.notes` proactively when a task produces durable decisions, meaningful findings, or reusable operational context.
        - On Keystone systems, the human notebook lives at `NOTES_DIR` (`~/notes` by default), not in the `~/.keystone/repos/` inventory.
        - When note structure, tags, frontmatter, shared-surface refs, or zk workflow details matter, read `~/.config/keystone/conventions/process.notes.md` and `~/.config/keystone/conventions/tool.zk-notes.md`.
        - When a task is tied to an issue, pull request, or milestone, capture normalized refs in notes when known and keep the shared surface as the public system of record.
      '')
      ''
        ## Shared-surface tracking

        - For issue-backed work, follow `process.issue-journal` and post `Work Started` and `Work Update` comments on the source issue.
        - For milestone and board-backed work, follow `process.project-board` so issue and PR state stays visible on the shared board.
        - Treat issues, pull requests, milestones, and boards as the canonical public record for status, review state, and decisions that affect collaborators.
        - Use notes to preserve durable rationale and memory, not to replace shared-surface tracking.
      ''
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
  imports = [ ../shared/experimental.nix ];

  options.keystone.terminal.conventions = {
    enable = mkOption {
      type = types.bool;
      default = config.keystone.experimental;
      description = ''
        Enable convention generation at each CLI coding tool's native
        instruction file path (~/.claude/CLAUDE.md, ~/.gemini/GEMINI.md,
        ~/.codex/AGENTS.md) (EXPERIMENTAL). See conventions/tool.cli-coding-agents.md.
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

  config =
    mkIf (terminalCfg.enable && cfg.enable) {
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

      # Expose the full conventions directory for on-demand reading
      # (referenced conventions link to Nix store paths in this directory)
      home.file.".config/keystone/conventions".source = conventionsPath;
    }
    // mkIf (!isDev) {
      # Generate the canonical Keystone instruction file and derive tool-native
      # instruction files from the same content. In development mode these are
      # refreshed from the live checkout by keystone-sync-agent-assets instead of
      # being immutable Home Manager text outputs.
      home.file.".keystone/AGENTS.md".text = agentsMdContent;
      home.file.".claude/CLAUDE.md".text = agentsMdContent;
      home.file.".gemini/GEMINI.md".text = agentsMdContent;
      home.file.".codex/AGENTS.md".text = agentsMdContent;
      home.file.".config/opencode/AGENTS.md".text = agentsMdContent;
      home.file.".keystone/repos/AGENTS.md".text = reposAgentsMdContent;
    };
}
