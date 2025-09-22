{
  description = "Keystone NixOS installation media with SSH support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }: {
    # Function to create ISO with SSH keys
    lib.mkKeystoneIso = {
      system ? "x86_64-linux",
      sshKeys ? [],
    }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./modules/iso-installer.nix
          {
            _module.args.sshKeys = sshKeys;
          }
        ];
      };

    # Default ISO configuration
    nixosConfigurations = {
      keystoneIso = self.lib.mkKeystoneIso {
        sshKeys = [];
      };
    };

    packages = flake-utils.lib.eachDefaultSystemMap (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        # Build the ISO
        iso = self.nixosConfigurations.keystoneIso.config.system.build.isoImage;

        # Build ISO command wrapper
        build-iso = pkgs.writeShellScriptBin "build-iso" (builtins.readFile ./bin/build-iso);

        # Convenience script to write ISO to USB
        write-usb = pkgs.writeShellScriptBin "write-usb" ''
          if [ -z "$1" ]; then
            echo "Usage: write-usb /dev/sdX"
            echo "This will write the ISO to the specified device"
            echo "WARNING: This will destroy all data on the target device!"
            exit 1
          fi

          echo "Building ISO..."
          nix build .#iso

          echo "Writing to $1..."
          sudo dd if=result/iso/keystone-installer.iso of=$1 bs=4M status=progress
          sync
          echo "Done! You can now boot from $1"
        '';

        # Validate installer script
        validate-installer = pkgs.writeShellScriptBin "validate-installer" ''
          ${pkgs.bash}/bin/bash ${./scripts/validate-installer.sh}
        '';
      }
    );

    devShells = flake-utils.lib.eachDefaultSystemMap (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixos-rebuild
            nixos-generators
            self.packages.${system}.build-iso
          ];

          shellHook = ''
            echo "Keystone ISO Installer"
            echo "====================="
            echo ""
            echo "Available commands:"
            echo "  build-iso                    - Build ISO with optional SSH keys"
            echo "  build-iso --help             - Show build-iso help"
            echo "  build-iso -k ~/.ssh/id_*.pub - Build with SSH keys"
            echo "  nix build .#iso              - Build ISO directly"
            echo "  nix run .#write-usb          - Write ISO to USB device"
            echo "  nix run .#validate-installer - Validate installer"
          '';
        };
      }
    );
  };
}
