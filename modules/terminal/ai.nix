{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.terminal;
  # Check if keystone overlay is available
  hasKeystoneOverlay = pkgs ? keystone && pkgs.keystone ? claude-code;
in {
  config = mkIf cfg.enable {
    home.packages =
      # Claude Code - AI-powered CLI assistant from Anthropic
      # https://claude.com/claude-code
      # Provided via keystone overlay (optional - requires overlay to be applied)
      lib.optionals hasKeystoneOverlay [
        pkgs.keystone.claude-code
      ]
      # Gemini CLI and Codex are not yet in nixpkgs - commented out for now
      # ++ lib.optionals (pkgs ? gemini-cli) [ pkgs.gemini-cli ]
      # ++ lib.optionals (pkgs ? codex) [ pkgs.codex ]
      ;
  };
}
