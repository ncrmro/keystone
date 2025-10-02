{
  description = "Keystone NixOS installation media";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    disko,
  }: {
    # ISO configuration without SSH keys (use bin/build-iso for SSH keys)
    nixosConfigurations = {
      keystoneIso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./modules/iso-installer.nix
          {
            _module.args.sshKeys = [];
          }
        ];
      };

      # VM Infrastructure Configurations
      router = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./vm-infrastructure/configs/router.nix
        ];
      };

      storage = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./vm-infrastructure/configs/storage.nix
        ];
      };

      client = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./vm-infrastructure/configs/client.nix
        ];
      };

      backup = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./vm-infrastructure/configs/backup.nix
        ];
      };

      dev = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./vm-infrastructure/configs/dev.nix
        ];
      };

      off-site = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./vm-infrastructure/configs/off-site.nix
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
