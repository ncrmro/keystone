{
  lib,
  config,
  pkgs,
  omarchy,
  ...
}:
with lib; {
  options.keystone.client.home = {
    enable =
      mkEnableOption "Keystone client home-manager configuration"
      // {
        default = true;
      };

    omarchy = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable omarchy bin directory installation for all users";
      };
    };
  };

  config = mkIf config.keystone.client.home.enable {
    # Configure home-manager
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;

      # Pass omarchy to home-manager modules
      extraSpecialArgs = {
        inherit omarchy;
      };

      # Import home-manager modules for all users
      sharedModules = [
        ../../../home-manager/modules/terminal-dev-environment
        ../../../home-manager/modules/desktop/hyprland
        ../../../home-manager/modules/omarchy.nix
      ];
    };
  };
}
