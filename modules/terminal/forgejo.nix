# Keystone Terminal — Forgejo CLI
#
# Installs `fj` (forgejo-cli) when enabled, providing CLI access to Forgejo
# for repository management, issue tracking, and pull requests.
#
# Auto-enabled via keystone.services.git.host in users.nix and agents.nix
# home-manager bridges.
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.keystone.terminal;
in {
  options.keystone.terminal.git.forgejo = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Install forgejo-cli (fj) for Forgejo server interaction";
    };
  };

  config = mkIf (cfg.enable && cfg.git.forgejo.enable) {
    home.packages = [
      pkgs.forgejo-cli
      pkgs.keystone.fetch-forgejo-sources
    ];
  };
}
