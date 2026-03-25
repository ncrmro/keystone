# AI CLI slash commands and skills generalized for all supported tools.
#
# Generates slash commands for tools that support them and registers DeepWork
# skills across Claude Code, Gemini CLI, OpenCode, and Codex.
#
# Each tool has its own directory structure and configuration requirements:
# - Claude: ~/.claude/commands/*.md with YAML frontmatter, ~/.claude/skills/deepwork/SKILL.md
# - Gemini: ~/.gemini/commands/*.toml
# - OpenCode: ~/.config/opencode/commands/*.md, ~/.config/opencode/skills/deepwork/SKILL.md
# - Codex: ~/.codex/skills/*.md-based skills
#
# TODO: As other AI coding CLIs gain support for custom workflow commands or
# skill plugins, add their respective configuration directories to the
# generation logic below.
#
# Development mode (REQ-018): When keystone.development is true and
# a keystone repo is registered, templates are out-of-store symlinks to the
# checkout — editable in place.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  terminalCfg = config.keystone.terminal;
  cfg = terminalCfg.aiExtensions;
  isDev = config.keystone.development;
  repos = config.keystone.repos;
  homeDir = config.home.homeDirectory;

  # Look up the keystone repo's local checkout path.
  keystoneEntry = findFirst (name: (repos.${name}.flakeInput or null) == "keystone") null (
    attrNames repos
  );
  devPath =
    if isDev && keystoneEntry != null then "${homeDir}/.keystone/repos/${keystoneEntry}" else null;

  # DeepWork Workflow slash commands (templates in ./ai-commands/)
  commandFiles = [
    "agent.bootstrap.md"
    "agent.doctor.md"
    "agent.issue.md"
    "agent.onboard.md"
    "daily_status.send.md"
    "deepwork.review.md"
    "ks.convention.md"
    "ks.develop.md"
    "ks.doctor.md"
    "ks.issue.md"
    "ks.update.md"
    "marketing.social_media_setup.md"
    "milestone.eng_handoff.md"
    "milestone.setup.md"
    "notes.process_inbox.md"
    "notes.doctor.md"
    "notes.project.md"
    "notes.report.md"
    "portfolio.review.md"
    "project.onboard.md"
    "project.press_release.md"
    "project.success.md"
    "repo.doctor.md"
    "repo.setup.md"
    "research.deep.md"
    "research.quick.md"
    "sweng.audit.md"
    "sweng.design.md"
    "sweng.fix.md"
    "sweng.implement.md"
    "sweng.refactor.md"
    "task.ingest.md"
    "task.run.md"
  ];

  # Helper to resolve source path (symlink in dev mode, Nix store otherwise)
  mkSource =
    subpath:
    if devPath != null then
      {
        source = config.lib.file.mkOutOfStoreSymlink "${devPath}/modules/terminal/${subpath}";
      }
    else
      {
        source = ./. + "/${subpath}";
      };

  stripMatchingQuotes =
    value:
    if hasPrefix "\"" value && hasSuffix "\"" value then
      removeSuffix "\"" (removePrefix "\"" value)
    else if hasPrefix "'" value && hasSuffix "'" value then
      removeSuffix "'" (removePrefix "'" value)
    else
      value;

  parseFrontmatterLine =
    line:
    let
      match = builtins.match "([A-Za-z0-9_-]+):[[:space:]]*(.*)" line;
    in
    if match == null then
      null
    else
      {
        name = elemAt match 0;
        value = stripMatchingQuotes (elemAt match 1);
      };

  findFrontmatterEnd =
    lines: idx:
    if idx >= length lines then
      null
    else if elemAt lines idx == "---" then
      idx
    else
      findFrontmatterEnd lines (idx + 1);

  parseCommandTemplate =
    name:
    let
      content = builtins.readFile (./ai-commands + "/${name}");
      lines = splitString "\n" content;
      hasFrontmatter = length lines > 0 && head lines == "---";
      frontmatterEnd = if hasFrontmatter then findFrontmatterEnd lines 1 else null;
      frontmatterLines =
        if hasFrontmatter && frontmatterEnd != null then sublist 1 (frontmatterEnd - 1) lines else [ ];
      bodyLines =
        if hasFrontmatter && frontmatterEnd != null then
          sublist (frontmatterEnd + 1) (length lines - frontmatterEnd - 1) lines
        else
          lines;
      frontmatterEntries = filter (entry: entry != null) (map parseFrontmatterLine frontmatterLines);
      frontmatter = listToAttrs frontmatterEntries;
      body = concatStringsSep "\n" bodyLines;
    in
    {
      inherit body;
      frontmatter = frontmatter // {
        inherit (frontmatter) description;
      };
      description =
        frontmatter.description or (throw "ai-command ${name} is missing required frontmatter.description");
      argumentHint = frontmatter.argument-hint or null;
      displayName = frontmatter.display-name or frontmatter.description or null;
    };

  renderYamlScalar =
    value:
    if builtins.isBool value then
      if value then "true" else "false"
    else if builtins.isInt value || builtins.isFloat value then
      toString value
    else
      builtins.toJSON value;

  renderFrontmatter =
    frontmatter:
    let
      preferredOrder = [
        "name"
        "description"
        "argument-hint"
        "display-name"
        "disable-model-invocation"
        "user-invocable"
        "allowed-tools"
        "model"
        "effort"
        "context"
        "agent"
      ];
      orderedKeys = filter (key: builtins.hasAttr key frontmatter) preferredOrder;
      extraKeys = filter (key: !(elem key preferredOrder)) (attrNames frontmatter);
      keys = orderedKeys ++ extraKeys;
      lines = map (key: "${key}: ${renderYamlScalar frontmatter.${key}}") keys;
    in
    ''
      ---
      ${concatStringsSep "\n" lines}
      ---
    '';

  renderClaudeCommand =
    name:
    let
      template = parseCommandTemplate name;
    in
    ''
      ${renderFrontmatter template.frontmatter}

      ${template.body}
    '';

  # Helper to generate Gemini-compatible TOML from a Markdown template.
  # Gemini commands require .toml files with `prompt` and optionally `description`.
  #
  # CRITICAL: builtins.readFile requires a path type (e.g. ./path) or a path
  # relative to the flake root to work in pure evaluation mode. Absolute
  # path strings (like devPath) are forbidden.
  mkGeminiToml = name: {
    text =
      let
        template = parseCommandTemplate name;
        # Replace $ARGUMENTS with Gemini's native {{args}}
        prompt = replaceStrings [ "$ARGUMENTS" ] [ "{{args}}" ] template.body;
      in
      ''
        description = ${builtins.toJSON template.description}
        prompt = ${builtins.toJSON prompt}
      '';
  };

  mkGeminiDeepworkToml = {
    text =
      let
        prompt = replaceStrings [ "$ARGUMENTS" ] [ "{{args}}" ] deepworkSkillBody;
      in
      ''
        description = ${builtins.toJSON skillMetadata.description}
        prompt = ${builtins.toJSON prompt}
      '';
  };

  commandBaseName = name: lib.removeSuffix ".md" name;

  commandDescription = name: (parseCommandTemplate name).description;
  commandDisplayName = name: (parseCommandTemplate name).displayName;

  codexSkillName = name: replaceStrings [ "." ] [ "-" ] (commandBaseName name);

  codexSkillBody =
    name:
    let
      template = parseCommandTemplate name;
      skillName = codexSkillName name;
      skillToken = "$" + skillName;
    in
    ''
      ${template.body}

      ## Codex skill invocation

      Use this skill when the user invokes `${skillToken}` or asks for this workflow implicitly.
      Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
      provide extra text, continue without additional arguments.
    '';

  mkCodexSkillMd =
    name:
    mkSkillMd {
      name = codexSkillName name;
      description = commandDescription name;
    } (codexSkillBody name);

  mkCodexSkillOpenAiYaml = name: {
    text = ''
      interface:
        display_name: ${builtins.toJSON (commandDisplayName name)}
        short_description: ${builtins.toJSON (commandDescription name)}

      dependencies:
        tools:
          - type: "mcp"
            value: "deepwork"
            description: "DeepWork MCP server"
    '';
  };

  # Shared metadata for skills
  skillMetadata = {
    name = "deepwork";
    description = "Start or continue DeepWork workflows using MCP tools";
  };

  # Shared Markdown body for the DeepWork skill (no frontmatter)
  deepworkSkillBody = ''
    # DeepWork Workflow Manager

    Execute multi-step workflows with quality gate checkpoints.

    ## Terminology

    A **job** is a collection of related **workflows**. For example, a "code_review" job
    might contain workflows like "review_pr" and "review_diff". Users may use the terms
    "job" and "workflow" somewhat interchangeably when describing the work they want done —
    use context and the available workflows from `get_workflows` to determine the best match.

    > **IMPORTANT**: Use the DeepWork MCP server tools. All workflow operations
    > are performed through MCP tool calls and following the instructions they return,
    > not by reading instructions from files.

    ## How to Use

    1. Call `get_workflows` to discover available workflows
    2. Call `start_workflow` with goal, job_name, and workflow_name
    3. Follow the step instructions returned
    4. Call `finished_step` with your outputs when done
    5. Handle the response: `needs_work`, `next_step`, or `workflow_complete`

    ## Intent Parsing

    When the user invokes `/deepwork`, parse their intent:
    1. **ALWAYS**: Call `get_workflows` to discover available workflows
    2. Based on the available flows and what the user said in their request, proceed:
        - **Explicit workflow**: `/deepwork <a workflow name>` → start the `<a workflow name>` workflow
        - **General request**: `/deepwork <a request>` → infer best match from available workflows
        - **No context**: `/deepwork` alone → ask user to choose from available workflows
  '';

  # Generate standard SKILL.md with YAML frontmatter
  mkSkillMd = meta: body: ''
    ---
    name: ${meta.name}
    description: "${meta.description}"
    ---

    ${body}
  '';

  codexManagedFiles = [
    {
      relativePath = ".codex/skills/deepwork/SKILL.md";
      source = pkgs.writeText "codex-skill-deepwork-SKILL.md" (mkSkillMd skillMetadata deepworkSkillBody);
    }
    {
      relativePath = ".codex/skills/deepwork/agents/openai.yaml";
      source = pkgs.writeText "codex-skill-deepwork-openai.yaml" ''
        interface:
          display_name: "DeepWork"
          short_description: "Start or continue DeepWork workflows using MCP tools"

        dependencies:
          tools:
            - type: "mcp"
              value: "deepwork"
              description: "DeepWork MCP server"
      '';
    }
  ]
  ++ flatten (
    map (
      name:
      let
        skillName = codexSkillName name;
        skillDir = ".codex/skills/${skillName}";
      in
      [
        {
          relativePath = "${skillDir}/SKILL.md";
          source = pkgs.writeText "codex-skill-${skillName}-SKILL.md" (mkCodexSkillMd name);
        }
        {
          relativePath = "${skillDir}/agents/openai.yaml";
          source = pkgs.writeText "codex-skill-${skillName}-openai.yaml" (mkCodexSkillOpenAiYaml name).text;
        }
      ]
    ) commandFiles
  );
in
{
  options.keystone.terminal.aiExtensions = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Generate slash commands and register skills for DeepWork workflows.";
    };
  };

  # Backward compatibility for the old option name
  imports = [
    (mkAliasOptionModule
      [ "keystone" "terminal" "claudeCodeCommands" "enable" ]
      [ "keystone" "terminal" "aiExtensions" "enable" ]
    )
  ];

  config = mkIf (terminalCfg.enable && terminalCfg.ai.enable && cfg.enable) {
    home.file =
      let
        commandFilesByTool =
          foldl'
            (
              acc: toolDir:
              if (toolDir == ".codex") then
                acc
              else
                acc
                // (listToAttrs (
                  map (name: {
                    name =
                      if (toolDir == ".gemini") then
                        let
                          relPath = replaceStrings [ "." ] [ "/" ] (commandBaseName name);
                        in
                        "${toolDir}/commands/${relPath}.toml"
                      else
                        "${toolDir}/commands/${name}";

                    value =
                      if (toolDir == ".gemini") then
                        mkGeminiToml name
                      else if (toolDir == ".claude") then
                        {
                          text = renderClaudeCommand name;
                        }
                      else
                        {
                          text = (parseCommandTemplate name).body;
                        };
                  }) commandFiles
                ))
            )
            { }
            [
              ".claude"
              ".gemini"
              ".config/opencode"
            ];

        deepworkSkillsByTool =
          foldl'
            (
              acc: toolDir:
              let
                skillDir = "${toolDir}/skills/deepwork";
              in
              if toolDir == ".gemini" then
                acc // { "${toolDir}/commands/deepwork.toml" = mkGeminiDeepworkToml; }
              else
                acc
                // {
                  "${skillDir}/SKILL.md".text = mkSkillMd skillMetadata deepworkSkillBody;
                }
            )
            { }
            [
              ".claude"
              ".gemini"
              ".config/opencode"
            ];
      in
      commandFilesByTool // deepworkSkillsByTool;

    # Codex 0.114.0 skips skills whose payload files are symlinks.
    # Manage Keystone-owned Codex skill payloads as regular files directly in
    # activation so Home Manager does not repeatedly back them up on each run.
    home.activation.codexSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      write_codex_skill_file() {
        relativePath="$1"
        sourcePath="$2"
        targetPath="$HOME/$relativePath"
        targetDir="$(dirname "$targetPath")"

        mkdir -p "$targetDir"

        # Recover from previous failed activations that left Home Manager backup
        # files behind for these managed Codex skill payloads.
        rm -f "$targetPath.backup"

        if [ -L "$targetPath" ]; then
          rm -f "$targetPath"
        fi

        tmpPath="$(mktemp "$targetPath.tmp.XXXXXX")"
        cp "$sourcePath" "$tmpPath"
        chmod 644 "$tmpPath"
        mv "$tmpPath" "$targetPath"
      }

      ${concatMapStringsSep "\n" (file: ''
        write_codex_skill_file \
          ${escapeShellArg file.relativePath} \
          ${escapeShellArg (toString file.source)}
      '') codexManagedFiles}
    '';
  };
}
