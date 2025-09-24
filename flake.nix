{
  description = "Keystone NixOS installation media";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = {
    self,
    nixpkgs,
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
    };

    packages.x86_64-linux = {
      iso = self.nixosConfigurations.keystoneIso.config.system.build.isoImage;
    };
  };
}
