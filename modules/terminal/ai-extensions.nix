# AI CLI commands and skills for the curated Keystone workflow surface.
#
# Generates only the user-facing Keystone entrypoints:
# - /ks      for Keystone guidance, issue filing, notes, and capability-aware routing
# - /ks.dev  for development-mode Keystone implementation flows
# - /deepwork remains available as the low-level escape hatch
#
# See conventions/tool.cli-coding-agents.md
# See specs/002-repo-backed-terminal-assets.md
#
# When aiArtifacts is enabled, skills are loaded from the committed artifact
# tree and are archetype-scoped (REQ-10, REQ-22).  Commands are still
# generated uniformly (all archetypes get all commands for tools that support
# them).
#
# Each tool has its own directory structure and configuration requirements:
# - Claude: ~/.claude/commands/*.md, ~/.claude/skills/<name>/SKILL.md
# - Gemini: ~/.gemini/commands/*.toml, ~/.gemini/skills/<name>/SKILL.md
# - OpenCode: ~/.config/opencode/commands/*.md, ~/.config/opencode/skills/<name>/SKILL.md
# - Codex: ~/.codex/skills/<name>/SKILL.md + agents/openai.yaml
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
  aiArtifactsCfg = config.keystone.terminal.aiArtifacts;
  isDev = config.keystone.development;
  archetype = terminalCfg.conventions.archetype;

  capabilityType = types.enum [
    "ks"
    "ks-dev"
    "assistant"
    "notes"
    "project"
    "engineer"
    "product"
    "project-manager"
    "executive-assistant"
  ];

  # Whether to use archetype-scoped skills from the artifact tree
  useArtifactTree = aiArtifactsCfg.enable;

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

  baseCapabilities = [
    "ks"
    "assistant"
    "project"
  ];

  explicitCapabilities = filter (capability: capability != "ks-dev" || isDev) cfg.capabilities;

  archetypeCapabilities =
    optionals (archetype == "engineer") [ "engineer" ]
    ++ optionals (archetype == "product") [ "product" ];

  resolvedCapabilities = unique (
    baseCapabilities ++ archetypeCapabilities ++ explicitCapabilities ++ optionals isDev [ "ks-dev" ]
  );

  publishedCommandIds = [
    "ks.system"
  ]
  ++ optionals (elem "assistant" resolvedCapabilities) [ "ks.assistant" ]
  ++ optionals (elem "notes" resolvedCapabilities) [ "ks.notes" ]
  ++ optionals (elem "project" resolvedCapabilities) [ "ks.projects" ]
  ++ optionals (elem "ks-dev" resolvedCapabilities) [ "ks.dev" ]
  ++ optionals (elem "engineer" resolvedCapabilities) [ "ks.engineer" ]
  ++ optionals (elem "product" resolvedCapabilities) [ "ks.product" ]
  ++ optionals (elem "project-manager" resolvedCapabilities) [ "ks.project-manager" ]
  ++ optionals (elem "executive-assistant" resolvedCapabilities) [ "ks.ea" ];

  formatCapabilities =
    capabilities: if capabilities == [ ] then "_none_" else concatStringsSep ", " capabilities;

  renderTemplate =
    template:
    replaceStrings
      [
        "__CAPABILITIES__"
        "__DEVELOPMENT_MODE__"
        "__PUBLISHED_COMMANDS__"
        "__ALLOWED_ROUTES__"
      ]
      [
        (formatCapabilities resolvedCapabilities)
        (if isDev then "enabled" else "disabled")
        (concatStringsSep ", " publishedCommandIds)
        (concatStringsSep "\n" ksAllowedRoutes)
      ]
      (builtins.readFile template);

  ksAllowedRoutes = [
    "- Explicit `$ks doctor`: start `keystone_system/doctor`."
    "- Explicit `$ks issue`: start `keystone_system/issue`."
    "- Keystone usage help, module discovery, configuration guidance, and workflow recommendations: answer directly when no workflow is needed."
    "- Feature requests, bug reports, paper cuts, and missing Keystone capabilities: start `keystone_system/issue`."
    "- Keystone health checks and troubleshooting: start `keystone_system/doctor` when the user wants diagnosis rather than documentation."
  ]
  ++ optionals (elem "assistant" resolvedCapabilities) [
    "- Personal assistant requests (reservations, birthdays, calendar, photo memories): direct the user to `/ks.assistant` instead of handling directly."
  ]
  ++ optionals (elem "notes" resolvedCapabilities) [
    "- Notes workflows (repair, inbox, init, setup): direct the user to `/ks.notes` instead of starting a notes workflow directly."
  ]
  ++ optionals (elem "project" resolvedCapabilities) [
    "- Project workflows (onboard, press release, milestone, engineering handoff, success): direct the user to `/ks.projects` instead of starting a project workflow directly."
  ]
  ++ optionals (elem "executive-assistant" resolvedCapabilities) [
    "- Executive assistant workflows (calendar, inbox, events, portfolio reviews, task coordination): direct the user to `/ks.ea` instead of starting executive_assistant workflows directly."
  ]
  ++ optionals (elem "engineer" resolvedCapabilities) [
    "- Engineering workflows (implementation, code review, architecture, CI): direct the user to `/ks.engineer` instead of starting engineer workflows directly."
  ]
  ++ optionals (elem "product" resolvedCapabilities) [
    "- Product workflows (press releases, milestones, stakeholder communication): direct the user to `/ks.product` instead of starting project workflows directly."
  ]
  ++ optionals (elem "project-manager" resolvedCapabilities) [
    "- Project management workflows (task decomposition, tracking, boards): direct the user to `/ks.pm` instead of managing tasks directly."
  ];

  ksCommandBody = renderTemplate ./agent-assets/ks.template.md;
  ksAssistantCommandBody = builtins.readFile ./agent-assets/ks-assistant.template.md;
  ksDevCommandBody = renderTemplate ./agent-assets/ks-dev.template.md;
  ksNotesCommandBody = builtins.readFile ./agent-assets/ks-notes.template.md;
  ksProjectsCommandBody = builtins.readFile ./agent-assets/ks-projects.template.md;
  ksEngineerCommandBody = builtins.readFile ./agent-assets/engineer-skill.template.md;
  ksProductCommandBody = builtins.readFile ./agent-assets/product-skill.template.md;
  ksPmCommandBody = builtins.readFile ./agent-assets/pm-skill.template.md;
  ksEaCommandBody = builtins.readFile ./agent-assets/ks-executive-assistant.template.md;

  ksDescription =
    "Keystone system — may start keystone_system/issue or keystone_system/doctor"
    + optionalString (elem "executive-assistant" resolvedCapabilities) ", or executive_assistant workflows";

  publishedCommands = [
    {
      id = "ks.system";
      description = ksDescription;
      argumentHint = "<request>";
      displayName = "KS System";
      body = ksCommandBody;
    }
  ]
  ++ optionals (elem "assistant" resolvedCapabilities) [
    {
      id = "ks.assistant";
      description = "Personal assistant — may start personal_assistant/reservation, personal_assistant/birthday, personal_assistant/calendar_prioritize, or personal_assistant/memory_search";
      argumentHint = "<request>";
      displayName = "KS Assistant";
      body = ksAssistantCommandBody;
    }
  ]
  ++ optionals (elem "notes" resolvedCapabilities) [
    {
      id = "ks.notes";
      description = "Notes workflows — may start notes/process_inbox, notes/doctor, notes/init, or notes/setup";
      argumentHint = "<request>";
      displayName = "KS Notes";
      body = ksNotesCommandBody;
    }
  ]
  ++ optionals (elem "project" resolvedCapabilities) [
    {
      id = "ks.projects";
      description = "Project workflows — may start project/onboard, project/press_release, project/milestone, project/milestone_engineering_handoff, or project/success";
      argumentHint = "<request>";
      displayName = "KS Projects";
      body = ksProjectsCommandBody;
    }
  ]
  ++ optionals (elem "ks-dev" resolvedCapabilities) [
    {
      id = "ks.dev";
      description = "Keystone development — may start keystone_system/develop, keystone_system/issue, keystone_system/convention, or keystone_system/doctor";
      argumentHint = "<goal>";
      displayName = "KS Development";
      body = ksDevCommandBody;
    }
  ]
  ++ optionals (elem "engineer" resolvedCapabilities) [
    {
      id = "ks.engineer";
      description = "Engineering — implementation, code review, architecture, and CI";
      argumentHint = "<goal>";
      displayName = "KS Engineer";
      body = ksEngineerCommandBody;
    }
  ]
  ++ optionals (elem "product" resolvedCapabilities) [
    {
      id = "ks.product";
      description = "Product — planning, milestones, stakeholder communication";
      argumentHint = "<request>";
      displayName = "KS Product";
      body = ksProductCommandBody;
    }
  ]
  ++ optionals (elem "project-manager" resolvedCapabilities) [
    {
      id = "ks.project-manager";
      description = "Project management — task decomposition, tracking, and boards";
      argumentHint = "<request>";
      displayName = "KS Project Manager";
      body = ksPmCommandBody;
    }
  ]
  ++ optionals (elem "executive-assistant" resolvedCapabilities) [
    {
      id = "ks.ea";
      description = "Executive assistant — calendar, inbox, events, portfolio reviews, and task coordination";
      argumentHint = "<request>";
      displayName = "KS Executive Assistant";
      body = ksEaCommandBody;
    }
  ];

  commandBaseName = command: command.id;

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
    command:
    let
      frontmatter = {
        name = command.id;
        description = command.description;
        "argument-hint" = command.argumentHint;
        "display-name" = command.displayName;
      };
    in
    ''
      ${renderFrontmatter frontmatter}

      ${command.body}
    '';

  mkGeminiToml = command: {
    text = ''
      description = ${builtins.toJSON command.description}
      prompt = ${builtins.toJSON command.body}
    '';
  };

  codexSkillName = name: replaceStrings [ "." ] [ "-" ] name;

  codexSkillBody =
    command:
    let
      skillName = codexSkillName command.id;
      skillToken = "$" + skillName;
    in
    ''
      ${command.body}

      ## Codex skill invocation

      Use this skill when the user invokes `${skillToken}` or asks for this workflow implicitly.
      Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
      provide extra text, continue without additional arguments.
    '';

  mkSkillMd = meta: body: ''
    ---
    name: ${meta.name}
    description: "${meta.description}"
    ---

    ${body}
  '';

  mkCodexSkillMd =
    command:
    mkSkillMd {
      name = codexSkillName command.id;
      description = command.description;
    } (codexSkillBody command);

  mkCodexSkillOpenAiYaml = command: {
    text = ''
      interface:
        display_name: ${builtins.toJSON command.displayName}
        short_description: ${builtins.toJSON command.description}

      dependencies:
        tools:
          - type: "mcp"
            value: "deepwork"
            description: "DeepWork MCP server"
    '';
  };

  skillMetadata = {
    name = "deepwork";
    description = "Start or continue DeepWork workflows using MCP tools";
  };

  deepworkSkillBody = ''
    # DeepWork workflow manager

    Execute multi-step workflows with quality gate checkpoints.

    ## Terminology

    A **job** is a collection of related **workflows**. Users may use the terms
    "job" and "workflow" interchangeably. Use `get_workflows` to discover the
    currently available jobs and workflows before deciding.

    ## How to use

    1. Call `get_workflows` to discover available workflows.
    2. Call `start_workflow` with the chosen `goal`, `job_name`, and `workflow_name`.
    3. Follow the step instructions returned by the MCP server.
    4. Call `finished_step` with the outputs when a step is complete.
    5. Handle the response: `needs_work`, `next_step`, or `workflow_complete`.

    ## Intent parsing

    - Explicit workflow: `/deepwork <workflow>` means start that workflow.
    - General request: `/deepwork <goal>` means infer the best workflow from `get_workflows`.
    - No context: `/deepwork` alone means ask the user to choose from available workflows.
  '';

  deepplanSkillMetadata = {
    name = "deepplan";
    description = "Start structured planning — explores, designs, and produces an executable plan";
  };

  deepplanSkillBody = ''
    # DeepPlan

    Structured planning workflow that explores the codebase, generates competing
    designs, and produces an executable DeepWork job definition.

    ## How to Use

    1. Call `EnterPlanMode` if not already in plan mode
    2. Call `start_workflow` with:
       - `job_name`: `"deepplan"`
       - `workflow_name`: `"create_deep_plan"`
       - `goal`: the user's planning request
    3. Follow the step instructions returned by the MCP tools — they supersede
       the default planning phases

    ## Intent Parsing

    When the user invokes `/deepplan`, parse their intent:
    - **With goal**: `/deepplan <goal>` → enter plan mode and start the workflow
      with `<goal>`
    - **No context**: `/deepplan` alone → enter plan mode and start the workflow
      using conversation context as the goal; if no context, ask the user what
      they want to plan
  '';

  wrapUpSkillMetadata = {
    name = "wrap-up";
    description = "Checkpoint the session: create a configured notes-dir report, comment on issues/PRs, and leave a handoff for the next agent or human";
  };

  wrapUpSkillBody = builtins.readFile ./agent-assets/wrap-up-skill.template.md;

  # Helper: resolve skill source from artifact tree.
  # In dev mode: out-of-store symlink. In non-dev mode: Nix store path.
  mkArtifactSkillSource =
    relPath:
    if devPath != null then
      {
        source = config.lib.file.mkOutOfStoreSymlink "${devPath}/ai-artifacts/archetypes/${archetype}/skills/${relPath}";
      }
    else
      {
        source = ./. + "/../../ai-artifacts/archetypes/${archetype}/skills/${relPath}";
      };

  # Read the archetype's skill list from archetypes.yaml for artifact-tree mode.
  conventionsPath = pkgs.keystone.keystone-conventions;
  archetypesFile = "${conventionsPath}/archetypes.yaml";
  hasArchetypes = builtins.pathExists archetypesFile;
  archetypesYaml =
    if hasArchetypes then
      builtins.fromJSON (
        builtins.readFile (
          pkgs.runCommand "archetypes-skills-json" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
            yq -o=json '.' ${archetypesFile} > $out
          ''
        )
      )
    else
      { archetypes = { }; };
  archetypeConfig = archetypesYaml.archetypes.${archetype} or { };
  archetypeSkills = archetypeConfig.skills or [ ];

  # Convert skill name from archetypes.yaml (e.g., "sweng.audit") to directory
  # name in the artifact tree (e.g., "sweng-audit")
  skillDirName = name: replaceStrings [ "." ] [ "-" ] name;

  # Build artifact-tree skill files for all tool directories.
  # Each archetype skill gets installed at the tool's native skill path.
  artifactSkillsByTool =
    let
      # Standard tool directories (Claude, Gemini, OpenCode)
      standardToolDirs = [
        ".claude"
        ".gemini"
        ".config/opencode"
      ];

      # DeepWork skill for all tools (always included, REQ-10)
      deepworkSkills = foldl' (
        acc: toolDir:
        acc
        // {
          "${toolDir}/skills/deepwork/SKILL.md" = mkArtifactSkillSource "deepwork/SKILL.md";
        }
      ) { } (standardToolDirs ++ [ ".codex" ]);

      # Codex-specific DeepWork agent metadata
      codexDeepworkAgent = {
        ".codex/skills/deepwork/agents/openai.yaml" = mkArtifactSkillSource "deepwork/agents/openai.yaml";
      };

      # Archetype-scoped skills for standard tools (Claude, Gemini, OpenCode)
      standardSkills = foldl' (
        acc: toolDir:
        acc
        // (listToAttrs (
          map (
            name:
            let
              sdir = skillDirName name;
            in
            {
              name = "${toolDir}/skills/${sdir}/SKILL.md";
              value = mkArtifactSkillSource "${sdir}/SKILL.md";
            }
          ) archetypeSkills
        ))
      ) { } standardToolDirs;

      # Codex-specific archetype skills (SKILL.md + agents/openai.yaml)
      codexSkills = listToAttrs (
        flatten (
          map (
            name:
            let
              sdir = skillDirName name;
            in
            [
              {
                name = ".codex/skills/${sdir}/SKILL.md";
                value = mkArtifactSkillSource "${sdir}/codex/SKILL.md";
              }
              {
                name = ".codex/skills/${sdir}/agents/openai.yaml";
                value = mkArtifactSkillSource "${sdir}/codex/agents/openai.yaml";
              }
            ]
          ) archetypeSkills
        )
      );
    in
    deepworkSkills // codexDeepworkAgent // standardSkills // codexSkills;

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
    {
      relativePath = ".codex/skills/deepplan/SKILL.md";
      source = pkgs.writeText "codex-skill-deepplan-SKILL.md" (
        mkSkillMd deepplanSkillMetadata deepplanSkillBody
      );
    }
    {
      relativePath = ".codex/skills/deepplan/agents/openai.yaml";
      source = pkgs.writeText "codex-skill-deepplan-openai.yaml" ''
        interface:
          display_name: "DeepPlan"
          short_description: "Start structured planning — explores, designs, and produces an executable plan"

        dependencies:
          tools:
            - type: "mcp"
              value: "deepwork"
              description: "DeepWork MCP server"
      '';
    }
    {
      relativePath = ".codex/skills/wrap-up/SKILL.md";
      source = pkgs.writeText "codex-skill-wrap-up-SKILL.md" (
        mkSkillMd wrapUpSkillMetadata wrapUpSkillBody
      );
    }
    {
      relativePath = ".codex/skills/wrap-up/agents/openai.yaml";
      source = pkgs.writeText "codex-skill-wrap-up-openai.yaml" ''
        interface:
          display_name: "Wrap-up"
          short_description: "Checkpoint the session: create a configured notes-dir report, comment on issues/PRs, and leave a handoff for the next agent or human"
      '';
    }
  ]
  ++ flatten (
    map (
      command:
      let
        skillName = codexSkillName command.id;
        skillDir = ".codex/skills/${skillName}";
      in
      [
        {
          relativePath = "${skillDir}/SKILL.md";
          source = pkgs.writeText "codex-skill-${skillName}-SKILL.md" (mkCodexSkillMd command);
        }
        {
          relativePath = "${skillDir}/agents/openai.yaml";
          source = pkgs.writeText "codex-skill-${skillName}-openai.yaml" (mkCodexSkillOpenAiYaml command)
          .text;
        }
      ]
    ) publishedCommands
  );

  legacyCodexSkillNames = [
    "agent-bootstrap"
    "agent-doctor"
    "agent-issue"
    "agent-onboard"
    "daily_status-send"
    "deepwork-review"
    "engineer"
    "ks-convention"
    "ks-develop"
    "ks-doctor"
    "ks-issue"
    "ks-update"
    "marketing-social_media_setup"
    "milestone-eng_handoff"
    "milestone-setup"
    "notes-doctor"
    "notes-process_inbox"
    "notes-project"
    "notes-report"
    "portfolio-review"
    "project-onboard"
    "project-press_release"
    "project-success"
    "repo-doctor"
    "repo-setup"
    "research-deep"
    "research-quick"
    "task-ingest"
    "task-run"
    "ks"
    "ks-pm"
    "ks-assistant"
  ];

  activeCodexSkillNames = [
    "deepwork"
    "deepplan"
    "wrap-up"
  ]
  ++ map (command: codexSkillName command.id) publishedCommands;

  staleCodexSkillNames = filter (name: !(elem name activeCodexSkillNames)) legacyCodexSkillNames;
in
{
  options.keystone.terminal.aiExtensions = {
    experimental = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Opt in to experimental AI extensions. When true, enables the curated
        Keystone skill composition surface (commands, skills, colocated conventions).
        Set to false until the skill composition API stabilises.
      '';
    };

    enable = mkOption {
      type = types.bool;
      default = cfg.experimental;
      description = "Generate curated Keystone commands and skills for supported AI CLIs.";
    };

    capabilities = mkOption {
      type = types.listOf capabilityType;
      default = [ ];
      description = ''
        Extra Keystone AI workflow capabilities for this profile. The final
        capability set is merged with terminal defaults, archetype defaults,
        and dev-mode gating.
      '';
    };

    resolvedCapabilities = mkOption {
      type = types.listOf capabilityType;
      default = [ ];
      internal = true;
      description = "Resolved capability set used to generate `/ks` and `/ks.dev`.";
    };

    publishedCommands = mkOption {
      type = types.listOf types.str;
      default = [ ];
      internal = true;
      description = "Curated Keystone command ids published for this profile.";
    };
  };

  imports = [
    (mkAliasOptionModule
      [ "keystone" "terminal" "claudeCodeCommands" "enable" ]
      [ "keystone" "terminal" "aiExtensions" "enable" ]
    )
  ];

  config = mkIf (terminalCfg.enable && terminalCfg.ai.enable && cfg.enable) {
    keystone.terminal.aiExtensions.resolvedCapabilities = resolvedCapabilities;
    keystone.terminal.aiExtensions.publishedCommands = publishedCommandIds;

    home.file = mkIf (!isDev) (
      let
        # Slash commands — generated uniformly for all archetypes (not skill-scoped)
        commandFilesByTool =
          foldl'
            (
              acc: toolDir:
              if toolDir == ".codex" then
                acc
              else
                acc
                // (listToAttrs (
                  map (
                    command:
                    let
                      name =
                        if toolDir == ".gemini" then
                          let
                            relPath = replaceStrings [ "." ] [ "/" ] (commandBaseName command);
                          in
                          "${toolDir}/commands/${relPath}.toml"
                        else
                          "${toolDir}/commands/${command.id}.md";
                    in
                    {
                      inherit name;
                      value =
                        if toolDir == ".gemini" then
                          mkGeminiToml command
                        else if toolDir == ".claude" then
                          {
                            text = renderClaudeCommand command;
                          }
                        else
                          {
                            text = command.body;
                          };
                    }
                  ) publishedCommands
                ))
            )
            { }
            [
              ".claude"
              ".gemini"
              ".config/opencode"
            ];

        # Skills — archetype-aware when artifact tree is enabled (REQ-10)
        skillFiles =
          if useArtifactTree then
            artifactSkillsByTool
          else
            # Fallback: uniform DeepWork + per-tool skills (backward compat, REQ-35)
            let
              deepworkSkillsByTool =
                foldl'
                  (
                    acc: toolDir:
                    let
                      skillDir = "${toolDir}/skills/deepwork";
                    in
                    if toolDir == ".gemini" then
                      acc
                      // {
                        "${toolDir}/commands/deepwork.toml".text = ''
                          description = ${builtins.toJSON skillMetadata.description}
                          prompt = ${builtins.toJSON deepworkSkillBody}
                        '';
                      }
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

              deepplanSkillsByTool =
                foldl'
                  (
                    acc: toolDir:
                    let
                      skillDir = "${toolDir}/skills/deepplan";
                    in
                    if toolDir == ".gemini" then
                      acc
                      // {
                        "${toolDir}/commands/deepplan.toml".text = ''
                          description = ${builtins.toJSON deepplanSkillMetadata.description}
                          prompt = ${builtins.toJSON deepplanSkillBody}
                        '';
                      }
                    else
                      acc
                      // {
                        "${skillDir}/SKILL.md".text = mkSkillMd deepplanSkillMetadata deepplanSkillBody;
                      }
                  )
                  { }
                  [
                    ".claude"
                    ".gemini"
                    ".config/opencode"
                  ];

              wrapUpSkillsByTool =
                foldl'
                  (
                    acc: toolDir:
                    let
                      skillDir = "${toolDir}/skills/wrap-up";
                    in
                    if toolDir == ".gemini" then
                      acc
                      // {
                        "${toolDir}/commands/wrap-up.toml".text = ''
                          description = ${builtins.toJSON wrapUpSkillMetadata.description}
                          prompt = ${builtins.toJSON wrapUpSkillBody}
                        '';
                      }
                    else
                      acc
                      // {
                        "${skillDir}/SKILL.md".text = mkSkillMd wrapUpSkillMetadata wrapUpSkillBody;
                      }
                  )
                  { }
                  [
                    ".claude"
                    ".gemini"
                    ".config/opencode"
                  ];

              ksSkillsByTool =
                foldl'
                  (
                    acc: toolDir:
                    acc
                    // (listToAttrs (
                      map (
                        command:
                        let
                          skillName = command.id;
                          skillDir = "${toolDir}/skills/${skillName}";
                        in
                        if toolDir == ".gemini" then
                          {
                            name = "${toolDir}/commands/${replaceStrings [ "." ] [ "/" ] command.id}.toml";
                            value = mkGeminiToml command;
                          }
                        else
                          {
                            name = "${skillDir}/SKILL.md";
                            value = {
                              text = mkSkillMd {
                                name = skillName;
                                description = command.description;
                              } command.body;
                            };
                          }
                      ) publishedCommands
                    ))
                  )
                  { }
                  [
                    ".claude"
                    ".gemini"
                    ".config/opencode"
                  ];
            in
            deepworkSkillsByTool // deepplanSkillsByTool // wrapUpSkillsByTool // ksSkillsByTool;
      in
      commandFilesByTool // skillFiles
    );

    home.activation = mkIf (!isDev) {
      codexSkillsPreflight = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        cleanup_codex_skill_state() {
          relativePath="$1"
          targetPath="$HOME/$relativePath"
          rm -f "$targetPath.backup"
        }

        cleanup_stale_codex_skill() {
          skillName="$1"
          rm -rf "$HOME/.codex/skills/$skillName"
        }

        ${concatMapStringsSep "\n" (skillName: ''
          cleanup_stale_codex_skill ${escapeShellArg skillName}
        '') staleCodexSkillNames}

        ${concatMapStringsSep "\n" (file: ''
          cleanup_codex_skill_state ${escapeShellArg file.relativePath}
        '') codexManagedFiles}
      '';

      codexSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        write_codex_skill_file() {
          relativePath="$1"
          sourcePath="$2"
          targetPath="$HOME/$relativePath"
          targetDir="$(dirname "$targetPath")"

          mkdir -p "$targetDir"

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
  };
}
