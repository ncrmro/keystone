# AI CLI commands and skills for the curated Keystone workflow surface.
#
# Generates only the user-facing Keystone entrypoints:
# - /ks      for Keystone guidance, issue filing, notes, and capability-aware routing
# - /ks.dev  for development-mode Keystone implementation flows
# - /deepwork remains available as the low-level escape hatch
#
# See conventions/tool.cli-coding-agents.md
# See specs/002-repo-backed-terminal-assets.md
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
  archetype = terminalCfg.conventions.archetype;

  capabilityType = types.enum [
    "ks"
    "ks-dev"
    "notes"
    "project"
    "engineer"
    "executive-assistant"
  ];

  baseCapabilities = [
    "ks"
    "notes"
    "project"
  ];

  explicitCapabilities = filter (capability: capability != "ks-dev" || isDev) cfg.capabilities;

  archetypeCapabilities = if archetype == "engineer" then [ "engineer" ] else [ ];

  resolvedCapabilities = unique (
    baseCapabilities ++ archetypeCapabilities ++ explicitCapabilities ++ optionals isDev [ "ks-dev" ]
  );

  publishedCommandIds = [
    "ks"
  ]
  ++ optionals (elem "notes" resolvedCapabilities) [ "ks.notes" ]
  ++ optionals (elem "project" resolvedCapabilities) [ "ks.projects" ]
  ++ optionals (elem "ks-dev" resolvedCapabilities) [ "ks.dev" ];

  formatCapabilities =
    capabilities: if capabilities == [ ] then "_none_" else concatStringsSep ", " capabilities;

  ksAllowedRoutes = [
    "- Explicit `$ks doctor`: start `keystone_system/doctor`."
    "- Explicit `$ks issue`: start `keystone_system/issue`."
    "- Keystone usage help, module discovery, configuration guidance, and workflow recommendations: answer directly when no workflow is needed."
    "- Feature requests, bug reports, paper cuts, and missing Keystone capabilities: start `keystone_system/issue`."
    "- Keystone health checks and troubleshooting: start `keystone_system/doctor` when the user wants diagnosis rather than documentation."
  ]
  ++ optionals (elem "notes" resolvedCapabilities) [
    "- Notes workflows (repair, inbox, init, setup): direct the user to `/ks.notes` instead of starting a notes workflow directly."
  ]
  ++ optionals (elem "project" resolvedCapabilities) [
    "- Project workflows (onboard, press release, milestone, engineering handoff, success): direct the user to `/ks.projects` instead of starting a project workflow directly."
  ]
  ++ optionals (elem "executive-assistant" resolvedCapabilities) [
    "- Calendar triage and scheduling: start `executive_assistant/manage_calendar`."
    "- Inbox cleanup and reply drafting: start `executive_assistant/clean_inbox`."
    "- Event planning and recommendations: start `executive_assistant/plan_event` or `executive_assistant/discover_events`."
    "- Daily priority and owner-note coordination: start `executive_assistant/task_loop`."
  ];

  ksCommandBody = ''
    Help the user get the most out of Keystone.

    When invoked as `$ks <route>`, this skill routes to the corresponding DeepWork
    workflow and MUST NOT execute the similarly named `ks` CLI command.

    ## Session context

    - Capabilities: ${formatCapabilities resolvedCapabilities}
    - Development mode: ${if isDev then "enabled" else "disabled"}
    - Published commands: ${concatStringsSep ", " publishedCommandIds}

    ## Operating rules

    - Prefer a direct answer for usage questions about `ks`, keystone modules, repo layout, conventions, or how to configure the system.
    - Use DeepWork MCP tools only when the request benefits from a workflow or should create durable artifacts.
    - Do not start workflows outside the allowed routes below.
    - Treat explicit `$ks ...` invocation as skill routing, not shell command execution.
    - Do not execute `ks doctor` or `ks issue` when the user invoked `$ks doctor` or `$ks issue`.
    - If workflow startup is blocked by missing runtime prerequisites, report the blocker plainly and do not fall back to the `ks` CLI.
    - If the user asks to implement Keystone code changes and `/ks.dev` is available, direct the request through the development route instead of improvising a separate workflow.
    - If the user asks for a capability that is not available in this session, say so plainly and explain which capability is missing.

    ## Allowed routes

    ${concatStringsSep "\n" ksAllowedRoutes}

    ## Invocation rules

    - `$ks` with no arguments: explain the available Keystone workflow routes and direct-help paths.
    - `$ks doctor`: start the `keystone_system/doctor` workflow.
    - `$ks issue`: start the `keystone_system/issue` workflow.
    - Other `$ks ...` invocations: treat them as Keystone help or routing requests, not as permission to execute the `ks` shell command.
  '';

  ksDevCommandBody = ''
    Handle Keystone development requests in development mode.

    ## Session context

    - Capabilities: ${formatCapabilities resolvedCapabilities}
    - Development mode: enabled
    - Primary workflow: `keystone_system/develop`

    ## Routing rules

    - Default to `keystone_system/develop` for feature work, bug fixes, refactors, and implementation requests in Keystone-managed repos.
    - Use `keystone_system/issue` when the user clearly wants issue creation rather than implementation.
    - Use `keystone_system/convention` when the request is specifically to create or update a Keystone convention.
    - Use `keystone_system/doctor` when the request is diagnostic rather than implementation.
    - Reuse the standard engineering lifecycle under `keystone_system/develop`; do not invent a second implementation workflow.
    - If the request is only a simple explanation or repo navigation question, answer directly instead of forcing a workflow.
  '';

  ksNotesCommandBody = ''
    Route note-related requests to the appropriate notes DeepWork workflow.

    ## Canonical note conventions

    - Use `ks.notes` when the task is primarily about durable note capture, note cleanup, inbox promotion, notebook repair, or notebook setup.
    - When note structure, tags, frontmatter, shared-surface refs, or zk workflow details matter, read:
      - `~/.config/keystone/conventions/process.notes.md`
      - `~/.config/keystone/conventions/tool.zk-notes.md`
    - If the user wants a fast durable brain dump before deeper organization, capture the note first, then continue with the appropriate notes workflow.

    ## Available workflows

    - **notes/process_inbox** — review and promote fleeting notes from inbox/ to permanent notes
    - **notes/doctor** — audit, repair, and normalize a zk notebook
    - **notes/init** — bootstrap a new zk notes repo from scratch
    - **notes/setup** — configure an existing zk notebook

    ## Routing rules

    - Mentions of processing, reviewing, or promoting inbox notes → `notes/process_inbox`
    - Mentions of repair, health check, audit, or normalize → `notes/doctor`
    - Mentions of new notebook, bootstrap, or initializing → `notes/init`
    - Mentions of setup or configure → `notes/setup`
    - If unclear, ask the user which workflow to run before starting

    ## How to start a workflow

    1. Call `get_workflows` to confirm available notes workflows.
    2. Call `start_workflow` with `job_name: "notes"`, `workflow_name: <chosen>`, and `goal: "$ARGUMENTS"`.
    3. Follow the step instructions returned by the MCP server.
  '';

  ksProjectsCommandBody = ''
    Route project-related requests to the appropriate project DeepWork workflow.
    Be proactive — suggest the next pipeline step without waiting for the user to ask.

    ## Available workflows

    - **project/onboard** — onboard a new project: create hub note, scaffold structure, link repos
    - **project/press_release** — draft a working-backwards press release or announcement for a project
    - **project/milestone** — create milestone and user stories from a press release or scope notes
    - **project/milestone_engineering_handoff** — internal FAQ, document review, optional spikes, specs, and plan issue; hands off to `engineer/implement`
    - **project/success** — run a project success review or retrospective

    ## Routing rules

    - Mentions of onboarding, starting, or registering a new project → `project/onboard`
    - Mentions of press release, announcement, or launch copy → `project/press_release`
    - Mentions of milestone, user stories, or scope planning → `project/milestone`
      (ask for `press_release_issue_url` if a press release was recently created)
    - Mentions of engineering handoff, internal FAQ, specs, plan issue, or implementation planning → `project/milestone_engineering_handoff`
    - Mentions of success, retro, retrospective, or wrapping up → `project/success`
    - If unclear, ask the user which workflow to run before starting

    ## Proactive pipeline suggestions

    Do not wait for the user to ask — proactively suggest the next step:

    - After `project/press_release` completes: immediately suggest `project/milestone`
      with the press release issue URL as input.
    - After `project/milestone` completes: immediately suggest `project/milestone_engineering_handoff`
      with the milestone issue number.
    - After `project/milestone_engineering_handoff` completes: suggest `engineer/implement`
      for each task in the plan checklist, and suggest `ks.notes` / `notes/process_inbox`
      to capture design decisions and scope into personal notes.
    - After `project/success` completes: suggest `ks.notes` to record the verdict and
      recommendations in personal notes and update shared owner notes.

    ## Notes integration

    After every major project event, prompt the user to capture learnings:
    - Use `/ks.notes` (routes to `notes/process_inbox`) to promote decisions, risks, and
      insights from this session into the personal Zettelkasten.
    - After milestones are set up or engineering handoffs complete, update the shared
      owner notes (`luce/notes`, `drago/notes`) to reflect current project state.

    ## Engineering integration

    - `project/milestone_engineering_handoff` produces the plan issue but does NOT implement.
    - All implementation MUST flow through `engineer/implement`, not ad-hoc coding.
    - Always name `engineer/implement` explicitly when suggesting implementation next steps.

    ## How to start a workflow

    1. Call `get_workflows` to confirm available project workflows.
    2. Call `start_workflow` with `job_name: "project"`, `workflow_name: <chosen>`, and `goal: "$ARGUMENTS"`.
    3. Follow the step instructions returned by the MCP server.
  '';

  ksDescription =
    "Keystone assistant — may start keystone_system/issue or keystone_system/doctor"
    + optionalString (elem "executive-assistant" resolvedCapabilities) ", or executive_assistant workflows";

  publishedCommands = [
    {
      id = "ks";
      description = ksDescription;
      argumentHint = "<request>";
      displayName = "KS Agent";
      body = ksCommandBody;
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

  wrapUpSkillMetadata = {
    name = "wrap-up";
    description = "Checkpoint the session: create a configured notes-dir report, comment on issues/PRs, and leave a handoff for the next agent or human";
  };

  wrapUpSkillBody = builtins.readFile ./agent-assets/wrap-up-skill.template.md;

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
  ];

  activeCodexSkillNames = [
    "deepwork"
    "wrap-up"
  ]
  ++ map (command: codexSkillName command.id) publishedCommands;

  staleCodexSkillNames = filter (name: !(elem name activeCodexSkillNames)) legacyCodexSkillNames;
in
{
  options.keystone.terminal.aiExtensions = {
    enable = mkOption {
      type = types.bool;
      default = true;
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
                    skillName = codexSkillName command.id;
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
      commandFilesByTool // deepworkSkillsByTool // wrapUpSkillsByTool // ksSkillsByTool
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
