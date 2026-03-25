# Keystone Terminal Projects
#
# Scaffold module for `keystone.projects` — per-project working environments
# with terminal sessions, AI agent integration, and optional desktop launcher
# support. Portable across NixOS and macOS.
#
# This module defines the foundational options consumed by the `pz`
# CLI tool (REQ-010, REQ-011).
#
# ## Example Usage
#
# ```nix
# keystone.notes = { enable = true; repo = "..."; };
# keystone.projects = {
#   enable = true;
# };
# ```
#
# ## Requirements Reference
#
# REQ-010.4  Discovers projects by scanning {notes_path}/projects/*/README.md
# REQ-010.5  keystone.notes.enable MUST be true when projects.enable is true
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
    inherit config;
    commandName = "pz";
    relativePath = "packages/pz/pz.sh";
    package = pkgs.keystone.pz;
  };
in
{
  # Import notes module so keystone.notes options are declared and accessible
  # for the assertion below. Nix deduplicates identical module imports, so
  # this is safe even if the caller also imports homeModules.notes separately.
  imports = [ ../notes/default.nix ];

  options.keystone.projects = {
    enable = mkEnableOption "Keystone project session management" // {
      default = true;
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # REQ-010.5: keystone.notes.enable MUST be true when projects.enable is true
      assertions = [
        {
          assertion = config.keystone.notes.enable;
          message = "keystone.notes.enable must be true when keystone.projects.enable is true (REQ-010.5)";
        }
      ];
    }
    pzCommand
  ]);
}
