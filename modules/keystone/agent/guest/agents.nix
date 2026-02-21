{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.keystone.agent.guest.agents;
in {
  # AI Agent Packages Configuration
  # Packages sourced from numtide/llm-agents.nix via keystone overlay

  environment.systemPackages = lib.flatten [
    (lib.optional cfg.claudeCode.enable pkgs.keystone.claude-code)
    (lib.optional cfg.geminiCli.enable pkgs.keystone.gemini-cli)
    (lib.optional cfg.codex.enable pkgs.keystone.codex)
  ];
}
