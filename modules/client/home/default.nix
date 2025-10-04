{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
{
  # Home Manager configuration for Keystone client
  imports = [
    ./omarchy.nix
  ];

  options.keystone.client.home = {
    enable = mkEnableOption "Keystone client home-manager configuration" // {
      default = true;
    };

    omarchy = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable omarchy bin directory installation";
      };
    };
  };

  config = mkIf config.keystone.client.home.enable {
    # Configure home-manager
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
    };
  };
}
