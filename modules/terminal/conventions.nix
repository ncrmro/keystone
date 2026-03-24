# Tool-native instruction file generation from keystone conventions.
#
# See conventions/tool.cli-coding-agents.md
# Implements REQ-017 (Conventions and Grafana MCP)
#
# When aiArtifacts is enabled, instruction files are installed from the
# committed ai-artifacts/ tree (or local checkout in dev mode) so content
# varies by archetype (REQ-9).  Falls back to in-memory generation when
# aiArtifacts is disabled for backward compatibility (REQ-35).
#
# Writes conventions to each CLI coding tool's native instruction file path:
#   - ~/.claude/CLAUDE.md   (Claude Code)
#   - ~/.gemini/GEMINI.md   (Gemini CLI)
#   - ~/.codex/AGENTS.md    (Codex)
#   - ~/.config/opencode/AGENTS.md  (OpenCode — REQ-21)
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
  aiArtifactsCfg = config.keystone.terminal.aiArtifacts;
  conventionsPath = pkgs.keystone.keystone-conventions;
  isDev = config.keystone.development;
  repos = config.keystone.repos;
  homeDir = config.home.homeDirectory;

  # Look up the keystone repo's local checkout path.
  keystoneEntry = findFirst (name: (repos.${name}.flakeInput or null) == "keystone") null (
    attrNames repos
  );
  devPath =
    if isDev && keystoneEntry != null then "${homeDir}/.keystone/repos/${keystoneEntry}" else null;

  # Use artifact tree when aiArtifacts is enabled
  useArtifactTree = aiArtifactsCfg.enable;

  # Artifact tree paths (REQ-15, REQ-16)
  artifactArchetypeDir =
    if devPath != null then
      "${devPath}/ai-artifacts/archetypes/${cfg.archetype}"
    else
      ./. + "/../../ai-artifacts/archetypes/${cfg.archetype}";

  # Read archetypes.yaml from the conventions derivation (fallback path).
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

  # Build inlined conventions content (fallback when artifact tree is not used)
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

  # Compose the AGENTS.md content (fallback)
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

  # Helper: resolve instruction file source from artifact tree.
  # In dev mode: out-of-store symlink to local checkout.
  # In non-dev mode: Nix store path from committed tree.
  mkArtifactSource =
    relPath:
    if devPath != null then
      {
        source = config.lib.file.mkOutOfStoreSymlink "${devPath}/ai-artifacts/archetypes/${cfg.archetype}/${relPath}";
      }
    else
      {
        source = ./. + "/../../ai-artifacts/archetypes/${cfg.archetype}/${relPath}";
      };
in
{
  options.keystone.terminal.conventions = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable convention generation at each CLI coding tool's native
        instruction file path (~/.claude/CLAUDE.md, ~/.gemini/GEMINI.md,
        ~/.codex/AGENTS.md, ~/.config/opencode/AGENTS.md).
        See conventions/tool.cli-coding-agents.md.
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
    # Only applies to the in-memory fallback path.
    warnings =
      let
        contentSize = builtins.stringLength agentsMdContent;
      in
      optional (!useArtifactTree && contentSize > cfg.maxGlobalBytes)
        "keystone.terminal.conventions: generated CLAUDE.md is ${toString contentSize} bytes (budget: ${toString cfg.maxGlobalBytes} bytes, ~${
          toString (cfg.maxGlobalBytes / 4)
        } tokens). Move conventions from inlined_conventions to referenced_conventions in archetypes.yaml.";

    # Write conventions to each tool's native instruction file path.
    # REQ-9:  Content varies by archetype when artifact tree is used.
    # REQ-20: Install from artifact tree instead of single in-memory blob.
    # REQ-21: Write OpenCode's global instruction file at its native location.
    home.file =
      (
        if useArtifactTree then
          (optionalAttrs (aiArtifactsCfg.tools.claude.enable) {
            ".claude/CLAUDE.md" = mkArtifactSource "claude/CLAUDE.md";
          })
          // (optionalAttrs (aiArtifactsCfg.tools.gemini.enable) {
            ".gemini/GEMINI.md" = mkArtifactSource "gemini/GEMINI.md";
          })
          // (optionalAttrs (aiArtifactsCfg.tools.codex.enable) {
            ".codex/AGENTS.md" = mkArtifactSource "codex/AGENTS.md";
          })
          // (optionalAttrs (aiArtifactsCfg.tools.opencode.enable) {
            ".config/opencode/AGENTS.md" = mkArtifactSource "opencode/AGENTS.md";
          })
        else
          # Fallback: in-memory generation for backward compatibility (REQ-35)
          {
            ".claude/CLAUDE.md".text = agentsMdContent;
            ".gemini/GEMINI.md".text = agentsMdContent;
            ".codex/AGENTS.md".text = agentsMdContent;
            ".config/opencode/AGENTS.md".text = agentsMdContent;
          }
      )
      // {
        # Expose the full conventions directory for on-demand reading
        # (referenced conventions link to Nix store paths in this directory)
        ".config/keystone/conventions".source = conventionsPath;
      };
  };
}
