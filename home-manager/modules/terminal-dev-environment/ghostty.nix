{ config, lib, pkgs, ... }:

let
  cfg = config.programs.terminal-dev-environment;
in
{
  config = lib.mkIf (cfg.enable && cfg.tools.terminal) {
    programs.ghostty = {
      enable = true;
      enableZshIntegration = lib.mkDefault true;
      settings = lib.mkDefault { };
    };
  };
}
