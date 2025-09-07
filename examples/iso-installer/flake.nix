{
  description = "Keystone ISO Installer Example - Testing with Custom SSH Keys";

  inputs = {
    keystone.url = "path:../..";
    nixpkgs.follows = "keystone/nixpkgs";
    flake-utils.follows = "keystone/flake-utils";
  };

  outputs = { self, keystone, nixpkgs, flake-utils }:
    let
      # Example SSH public keys - replace these with your actual keys
      exampleSshKeys = [
        # Example RSA key (replace with your actual public key)
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7... user@example.com"
        # Example Ed25519 key (replace with your actual public key) 
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@example.com"
      ];
    in
    {
      # Override the ISO configuration with custom SSH keys
      nixosConfigurations = {
        iso-installer = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ../../modules/iso-installer.nix
            {
              # Pass the SSH keys to the configuration
              _module.args.sshKeys = exampleSshKeys;
            }
          ];
        };
      };

      # Package outputs
      packages = flake-utils.lib.eachDefaultSystemMap (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Build the ISO with custom SSH keys
          iso = self.nixosConfigurations.iso-installer.config.system.build.isoImage;
          
          # Convenience script to build and write to USB
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
        }
      );

      # Development shell with helpful commands
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
            
            shellHook = ''
              echo "Keystone ISO Installer Example"
              echo "=============================="
              echo ""
              echo "Available commands:"
              echo "  nix build .#iso          - Build the ISO with your SSH keys"
              echo "  nix run .#write-usb      - Write ISO to USB device"
              echo ""
              echo "Before using, edit flake.nix to add your SSH public keys!"
            '';
          };
        }
      );
    };
}