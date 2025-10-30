{
  description = "Keystone NixOS installation media";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    omarchy = {
      url = "github:basecamp/omarchy/v3.0.2";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      home-manager,
      omarchy,
      ...
    }:
    {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;

      # ISO configuration without SSH keys (use bin/build-iso for SSH keys)
      nixosConfigurations = {
        keystoneIso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ./modules/iso-installer.nix
            {
              _module.args.sshKeys = [ ];
              # Force kernel 6.12 - must be set here to override minimal CD
              boot.kernelPackages = nixpkgs.lib.mkForce nixpkgs.legacyPackages.x86_64-linux.linuxPackages_6_12;
            }
          ];
        };

        # Test server configuration for nixos-anywhere deployment
        test-server = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            ./modules/server
            ./modules/disko-single-disk-root
            ./vms/test-server/configuration.nix
          ];
        };
      };

      # Export Keystone modules for use in other flakes
      nixosModules = {
        server = ./modules/server;
        client = ./modules/client;
        clientHome = ./modules/client/home;
        diskoSingleDiskRoot = ./modules/disko-single-disk-root;
        isoInstaller = ./modules/iso-installer.nix;
      };

      packages.x86_64-linux = {
        iso = self.nixosConfigurations.keystoneIso.config.system.build.isoImage;
      };
    };
}
