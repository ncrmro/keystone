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
  config = mkIf cfg.enable {
    home.packages = [
      # Claude Code - AI-powered CLI assistant from Anthropic
      # https://claude.com/claude-code
      pkgs.claude-code

      # Gemini CLI - Google's AI assistant (when available in nixpkgs)
      pkgs.gemini-cli

      # Codex - OpenAI's lightweight coding agent (when available in nixpkgs)
      pkgs.codex
    ];
  };
}
