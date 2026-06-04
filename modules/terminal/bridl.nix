# bridl — profile-oriented wrapper for launching pi/claude agent CLIs.
#
# Installs the `bridl` binary and symlinks ~/.bridl/{settings.yml,profiles}
# to an external bridl config tree (typically a ks-config checkout's
# agents/bridl/ directory) so profile edits propagate live, without a
# nixos-rebuild. ~/.bridl/cache stays outside the symlinked tree and is
# writable by the user.
#
# Used in two places:
#   - The admin user's home (workstation) — configDir points at their own
#     ks-config checkout under $HOME/repos/.
#   - Each os-agent user's home (e.g. agent-luce, agent-drago) — configDir
#     points at the admin's ks-config checkout, reachable via the agent
#     traversal ACL on the admin's home directory (see modules/shared/
#     system-flake.nix).
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  cfg = config.keystone.terminal.bridl;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  # Resolve the consumer flake path from the NixOS-side option when HM is
  # integrated with NixOS (the normal case for keystone). Falls back to a
  # generic ~/repos guess for standalone HM use where osConfig is absent.
  systemFlakePath =
    if osConfig != null then
      osConfig.keystone.systemFlake.path
    else
      "${config.home.homeDirectory}/repos/ks-config";
in
{
  options.keystone.terminal.bridl = {
    enable = mkEnableOption "bridl ~/.bridl symlinks and CLI install.";

    configDir = mkOption {
      type = types.str;
      default = "${systemFlakePath}/agents/bridl";
      defaultText = lib.literalExpression ''
        "''${osConfig.keystone.systemFlake.path}/agents/bridl"
      '';
      description = ''
        Absolute path to the bridl config directory (containing
        settings.yml and profiles/). ~/.bridl/settings.yml and
        ~/.bridl/profiles are symlinked here as out-of-store links so
        live edits propagate without a rebuild.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.keystone.bridl ];

    home.file.".bridl/settings.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${cfg.configDir}/settings.yml";
    home.file.".bridl/profiles".source =
      config.lib.file.mkOutOfStoreSymlink "${cfg.configDir}/profiles";
  };
}
