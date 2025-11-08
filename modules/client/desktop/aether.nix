{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.client.desktop.aether;
  
  aether = pkgs.callPackage ../../../pkgs/aether { };
in
{
  options.keystone.client.desktop.aether = {
    enable = mkEnableOption "Aether theming application";
    
    package = mkOption {
      type = types.package;
      default = aether;
      description = "The Aether package to use";
    };
  };

  config = mkIf cfg.enable {
    # Install Aether package
    environment.systemPackages = [ cfg.package ];

    # Ensure required dependencies are available
    # GJS, GTK4, and Libadwaita are included in the package
    # ImageMagick is also included for color extraction
    
    # Optional: Install hyprshade for shader effects support
    # Uncomment if users want shader functionality
    # environment.systemPackages = with pkgs; [ hyprshade ];
  };
}
