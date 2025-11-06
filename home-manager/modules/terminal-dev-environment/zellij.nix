{ config, lib, pkgs, ... }:

let
  cfg = config.programs.terminal-dev-environment;
in
{
  config = lib.mkIf (cfg.enable && cfg.tools.multiplexer) {
    programs.zellij = {
      enable = true;
      enableZshIntegration = false;  # Prevent auto-nesting
      settings = lib.mkDefault {
        theme = "tokyo-night-dark";
        startup_tips = false;
      };
    };
  };
}
