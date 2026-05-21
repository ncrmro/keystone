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
    ./github-token-nix.nix
  ];

  options.keystone.os = {
    enable = lib.mkEnableOption "Keystone Darwin system integration";

    adminUsername = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Unix username for the primary macOS administrator account.";
    };
  };

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
