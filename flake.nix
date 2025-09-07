{
  description = "Keystone - Self Sovereign Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      lib = nixpkgs.lib;
    in
    {
      # Import the configuration library
      lib = import ./config.nix { inherit lib; };

      # ISO installer configuration
      nixosConfigurations = {
        # ISO installer with SSH key support for nixos-anywhere
        iso-installer = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ./modules/iso-installer.nix
          ];
          specialArgs = {
            # Allow SSH keys to be passed from consuming flakes
            sshKeys = [ ];
          };
        };
      };

      # Package outputs
      packages = flake-utils.lib.eachDefaultSystemMap (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Build the ISO
          iso = self.nixosConfigurations.iso-installer.config.system.build.isoImage;
        }
      );

      # Development shell
      devShells = flake-utils.lib.eachDefaultSystemMap (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nixos-rebuild
              nixos-generators
            ];
          };
        }
      );
    };
}