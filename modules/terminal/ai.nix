# AI coding assistants (Claude Code, Gemini CLI, Codex, OpenCode)
#
# Gated by keystone.terminal.ai.enable (default: true) so environments
# like the installer ISO can opt out of heavy AI tooling while still
# using the rest of keystone.terminal.
#
# Optional Ollama integration (keystone.terminal.ai.ollama) adds:
# - ollama CLI for model management
# - claude-local / opencode-local shell wrappers pointing at local Ollama
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
  ollamaCfg = cfg.ai.ollama;
in
{
  options.keystone.terminal.ai = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI coding assistants (Claude Code, Gemini CLI, Codex, OpenCode)";
    };

    ollama = {
      enable = mkEnableOption "local Ollama integration for AI tools";

      host = mkOption {
        type = types.str;
        default = "http://localhost:11434";
        description = "Ollama API URL. Set to Tailscale hostname for cross-machine access.";
        example = "http://ncrmro-workstation:11434";
      };

      defaultModel = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default model name for local AI wrappers.";
        example = "qwen3:32b";
      };
    };
  };

  config = mkIf (cfg.enable && cfg.ai.enable) {
    keystone.terminal.cliCodingAgents.enable = mkDefault true;

    home.file = {
      ".gemini/skills/deepwork/index.toml".text = ''
        +++
        name = "deepwork"
        description = "Start or continue DeepWork workflows using MCP tools"
        +++
      '';
      ".gemini/skills/deepwork/SKILL.md".text = ''
        # DeepWork Workflow Manager
        # NOTE: This content should match:
        # https://github.com/Unsupervisedcom/deepwork/blob/main/plugins/gemini/skills/deepwork/SKILL.md

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
    };

    home.packages = [
      # Claude Code - AI-powered CLI assistant from Anthropic
      # https://claude.com/claude-code
      pkgs.keystone.claude-code

      # Gemini CLI - Google's AI assistant
      pkgs.keystone.gemini-cli

      # Codex - OpenAI's lightweight coding agent
      pkgs.keystone.codex

      # OpenCode - Open-source AI coding agent
      pkgs.keystone.opencode

      # DeepWork - workflow orchestration MCP server
      pkgs.keystone.deepwork
    ]
    ++ optionals ollamaCfg.enable [
      # Ollama CLI for model management (ollama pull, list, run)
      pkgs.ollama
    ];

    programs.zsh.initContent = mkIf ollamaCfg.enable (
      let
        modelFlag = if ollamaCfg.defaultModel != null then " --model ${ollamaCfg.defaultModel}" else "";
      in
      ''
        # Local Ollama wrappers — cloud commands (claude, opencode) remain unchanged
        claude-local() {
          ANTHROPIC_BASE_URL="${ollamaCfg.host}" \
          ANTHROPIC_AUTH_TOKEN="ollama" \
            claude${modelFlag} "$@"
        }

        opencode-local() {
          OPENCODE_PROVIDER="ollama" \
          OPENCODE_MODEL="${
            if ollamaCfg.defaultModel != null then ollamaCfg.defaultModel else "llama3.1:8b"
          }" \
          OLLAMA_HOST="${ollamaCfg.host}" \
            opencode "$@"
        }
      ''
    );
  };
}
