# System-wide AGENTS.md generation from keystone conventions.
#
# Reads archetypes.yaml from the keystone-conventions Nix store derivation and
# generates ~/.config/keystone/AGENTS.md at build time. This provides a base
# layer of conventions, tool manuals, and process docs to all AI tool sessions
# (Claude, Gemini, Codex, OpenCode) without requiring the keystone repo at runtime.
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
        Enable system-wide AGENTS.md generation from keystone conventions.

        When enabled, generates ~/.config/keystone/AGENTS.md at build time
        from the keystone-conventions Nix derivation. This provides a base
        layer of conventions to all AI tool sessions.
      '';
    };

    archetype = mkOption {
      type = types.str;
      default = "engineer";
      description = ''
        The archetype to use for AGENTS.md generation. Determines which
        conventions are inlined vs referenced. See conventions/archetypes.yaml
        for available archetypes (engineer, product).
      '';
    };
  };

  config = mkIf (terminalCfg.enable && cfg.enable) {
    # Generate the system-wide AGENTS.md from conventions
    home.file.".config/keystone/AGENTS.md".text = agentsMdContent;

    # Also expose the full conventions directory for on-demand reading
    home.file.".config/keystone/conventions".source = conventionsPath;
  };
}
