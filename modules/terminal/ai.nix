# AI coding assistants (Claude Code, Gemini CLI, Codex, OpenCode)
#
# Gated by keystone.terminal.ai.enable (default: true) so environments
# like the installer ISO can opt out of heavy AI tooling while still
# using the rest of keystone.terminal.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
in
{
  options.keystone.terminal.ai = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI coding assistants (Claude Code, Gemini CLI, Codex, OpenCode)";
    };
  };

  config = mkIf (cfg.enable && cfg.ai.enable) {
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
    ];
  };
}
