# Test configuration for the Desktop Hyprland module
# This file shows how to use the module in a typical setup

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }: {
    homeConfigurations."user" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        # Import the keystone desktop module
        ./modules/home-manager
        
        # User configuration
        {
          home.username = "user";
          home.homeDirectory = "/home/user";
          
          # Enable keystone desktop
          keystone = {
            full_name = "Keystone User";
            desktop = {
              enable = true;
              monitors = [ "DP-1,1920x1080@60,0x0,1" ];
              wallpaper = "~/Pictures/wallpaper.jpg";
            };
          };
        }
      ];
    };
  };
}