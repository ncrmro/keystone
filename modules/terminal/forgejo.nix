# Keystone Terminal — Forgejo CLI
#
# Installs `fj` (forgejo-cli) and `tea` (Gitea/Forgejo CLI) when enabled.
# forgejo-cli handles admin and auth operations; tea covers daily workflow
# (PRs, issues, releases) that forgejo-cli doesn't support.
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
      # tea provides repo/issue/PR operations that forgejo-cli lacks (e.g. tea pr create,
      # tea issue list). forgejo-cli focuses on admin/auth; tea covers the daily workflow.
      pkgs.tea
      pkgs.keystone.fetch-forgejo-sources
    ];
  };
}
