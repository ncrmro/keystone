# Keystone Terminal Projects
#
# Module for `keystone.projects` — per-project working environments
# with terminal sessions, AI agent integration, and optional desktop launcher
# support. Portable across NixOS and macOS.
#
# Projects are declared in projects.yaml next to the consumer flake.
# This module wires up the `pz` CLI tool (REQ-010, REQ-011).
#
# ## Example Usage
#
# ```nix
# keystone.projects = {
#   enable = true;
# };
# ```
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.projects;
  devScripts = import ../shared/dev-script-link.nix { inherit lib; };
  inherit (devScripts) mkHomeScriptCommand;
  pzCommand = mkHomeScriptCommand {
    inherit config pkgs;
    commandName = "pz";
    relativePath = "packages/pz/pz.sh";
    package = pkgs.keystone.pz;
  };
in
{
  options.keystone.projects = {
    enable = mkEnableOption "Keystone project session management" // {
      default = true;
    };
  };

  config = mkIf cfg.enable pzCommand;
}
