# AI CLI slash commands and skills generalized for all supported tools.
#
# Generates slash commands (/project.*, /milestone.*) and registers the
# DeepWork skill across Claude Code, Gemini CLI, OpenCode, and Codex.
#
# Each tool has its own directory structure and configuration requirements:
# - Claude: ~/.claude/commands/*.md, ~/.claude/skills/deepwork/SKILL.md
# - Gemini: ~/.gemini/commands/*.toml, ~/.gemini/skills/deepwork/SKILL.md
# - OpenCode: ~/.config/opencode/commands/*.md, ~/.config/opencode/skills/deepwork/SKILL.md
# - Codex: ~/.codex/skills/deepwork/SKILL.md (uses AGENTS.md for commands)
#
# TODO: As other AI coding CLIs gain support for custom workflow commands or
# "skill" plugins via markdown templates, add their respective configuration
# directories to the generation logic below.
#
# Development mode (REQ-018): When keystone.terminal.development is true and
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
  isDev = terminalCfg.development;
  repos = terminalCfg.repos;
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
    "ks.convention.md"
    "ks.develop.md"
    "ks.doctor.md"
    "ks.issue.md"
    "ks.update.md"
    "marketing.social_media_setup.md"
    "milestone.eng_handoff.md"
    "milestone.setup.md"
    "notes.process_inbox.md"
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

  # Helper to generate Gemini-compatible TOML from a Markdown template.
  # Gemini commands require .toml files with `prompt` and optionally `description`.
  #
  # CRITICAL: builtins.readFile requires a path type (e.g. ./path) or a path
  # relative to the flake root to work in pure evaluation mode. Absolute
  # path strings (like devPath) are forbidden.
  mkGeminiToml = name: {
    text =
      let
        # We must use a relative path here so Nix can read the file in pure
        # evaluation mode (Flakes). devPath (absolute) is only for symlinks.
        mdFile = ./ai-commands + "/${name}";

        content = builtins.readFile mdFile;
        # Extract first line as description, strip Markdown formatting if present
        firstLine = head (splitString "\n" content);
        description = removeSuffix "." (removePrefix "# " firstLine);

        # Replace $ARGUMENTS with Gemini's native {{args}}
        prompt = replaceStrings [ "$ARGUMENTS" ] [ "{{args}}" ] content;
      in
      ''
        description = ${builtins.toJSON description}
        prompt = ${builtins.toJSON prompt}
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
      foldl'
        (
          acc: toolDir:
          # 1. Provision Slash Commands (Claude, Gemini, OpenCode)
          # TODO: Expand this list as other tools add support for standalone command templates.
          (
            if (toolDir != ".codex") then
              acc
              // (listToAttrs (
                map (name: {
                  # Gemini uses .toml for commands and subdirectories for namespacing (ks.develop -> ks/develop -> /ks:develop)
                  # Others use .md and maintain dots in filenames for now.
                  name =
                    if (toolDir == ".gemini") then
                      let
                        relPath = replaceStrings [ "." ] [ "/" ] (lib.removeSuffix ".md" name);
                      in
                      "${toolDir}/commands/${relPath}.toml"
                    else
                      "${toolDir}/commands/${name}";

                  value = if (toolDir == ".gemini") then mkGeminiToml name else mkSource "ai-commands/${name}";
                }) commandFiles
              ))
            else
              acc
          )
          //
            # 2. Provision DeepWork Skill (Claude, Gemini, OpenCode, Codex)
            # TODO: Expand this list as other tools add support for "Agent Skill" directory structures.
            (
              let
                skillDir = "${toolDir}/skills/deepwork";
              in
              {
                "${skillDir}/SKILL.md".text = mkSkillMd skillMetadata deepworkSkillBody;
              }
            )
        )
        { }
        [
          ".claude"
          ".gemini"
          ".config/opencode"
          ".codex"
        ];
  };
}
