# Tool-native instruction file generation from keystone conventions.
#
# See conventions/tool.cli-coding-agents.md
# Implements REQ-017 (Conventions and Grafana MCP)
#
# Reads archetypes.yaml from the keystone-conventions Nix store derivation and
# writes conventions to each CLI coding tool's native instruction file path:
#   - ~/.claude/CLAUDE.md   (Claude Code)
#   - ~/.gemini/GEMINI.md   (Gemini CLI)
#   - ~/.codex/AGENTS.md    (Codex)
#   - OpenCode reads ~/.claude/CLAUDE.md via legacy compat — no separate file needed
#
# Content separation:
#   - Keystone repo (conventions/): tool manuals, process docs, archetypes — shared
#   - nixos-config repo: SOUL.md, TEAM.md, SERVICES.md — per-deployment/per-agent
#   - This module generates ONLY the conventions layer
#
# Development mode (REQ-018): When keystone.terminal.development is true and
# a keystone repo is registered, the exposed conventions directory and referenced
# convention links resolve to local checkout paths — editable in place.
# Eval-time reads (archetypes.yaml, inlined conventions) always use the Nix store
# copy since builtins.readFile requires store paths in pure evaluation mode.
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
  isDev = terminalCfg.development;
  repos = terminalCfg.repos;
  homeDir = config.home.homeDirectory;

  # Look up the keystone repo's local checkout path.
  keystoneEntry = findFirst (name: (repos.${name}.flakeInput or null) == "keystone") null (
    attrNames repos
  );
  devConventionsPath =
    if isDev && keystoneEntry != null then
      "${homeDir}/.keystone/repos/${keystoneEntry}/conventions"
    else
      null;

  # Store path — always needed for eval-time reads (archetypes.yaml, inlined conventions).
  storeConventionsPath = pkgs.keystone.keystone-conventions;

  # Runtime path: local checkout in dev mode, Nix store otherwise.
  # Used for referenced convention links and the exposed conventions directory.
  conventionsPath = if devConventionsPath != null then devConventionsPath else storeConventionsPath;

  # Read archetypes.yaml from the conventions derivation.
  # Guard: if the file doesn't exist, produce empty config (graceful degradation).
  archetypesFile = "${storeConventionsPath}/archetypes.yaml";
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

  # Build inlined conventions content.
  # Always reads from store path — builtins.readFile requires store paths in
  # pure evaluation mode. Inlined content updates on next rebuild.
  inlinedConventions = map (
    name:
    let
      # Convention names use dots (e.g., "process.version-control") but files
      # use the full name as filename (e.g., "process.version-control.md")
      filename = "${name}.md";
      filepath = "${storeConventionsPath}/${filename}";
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

    # Expose the full conventions directory for on-demand reading.
    # In dev mode, symlinks to local checkout (editable in place).
    # In locked mode, points to Nix store copy.
    home.file.".config/keystone/conventions" =
      if devConventionsPath != null then
        { source = config.lib.file.mkOutOfStoreSymlink devConventionsPath; }
      else
        { source = storeConventionsPath; };
  };
}
