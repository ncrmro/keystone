{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
  cfg = config.keystone.terminal;
  claude-code = pkgs.callPackage ./claude-code {};
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.system;
  };
in {
  config = mkIf cfg.enable {
    home.packages = [
      # Claude Code - AI-powered CLI assistant from Anthropic
      # https://claude.com/claude-code
      claude-code

      # Gemini CLI - Google's AI assistant
      pkgs-unstable.gemini-cli

      # Codex - OpenAI's lightweight coding agent
      # https://github.com/openai/codex
      pkgs-unstable.codex
    ];
  };
}
