{
  description = "Keystone NixOS installation media";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
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
            }
          ];
        };
      };

      # Export Keystone modules for use in other flakes
      nixosModules = {
        server = ./modules/server;
        client = ./modules/client;
        diskoSingleDiskRoot = ./modules/disko-single-disk-root;
        isoInstaller = ./modules/iso-installer.nix;
      };

      packages.x86_64-linux = {
        iso = self.nixosConfigurations.keystoneIso.config.system.build.isoImage;
      };
    };
}
