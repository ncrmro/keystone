# Darwin entry point for the `keystone.os.*` module surface.
#
# Shared options (`enable`, `adminUsername`) are declared once in
# ./shared.nix and imported here so the NixOS and Darwin schemas stay
# in lockstep. Darwin-specific config bodies live in this file.
#
# See conventions/os.cross-platform-modules.md for the broader pattern.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.keystone.os;
in
{
  imports = [
    ./shared.nix
    ./github-token-nix.nix
  ];

  config = lib.mkIf cfg.enable {
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    environment.systemPackages = [
      pkgs.keystone.agenix
    ];
  };
}
