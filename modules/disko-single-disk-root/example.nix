# Example usage of the Keystone disko-single-disk-root module
#
# This file demonstrates how to use the reusable single disk root disko module
# in your own NixOS configuration.
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    keystone.url = "github:ncrmro/keystone";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      keystone,
      disko,
      ...
    }:
    {
      nixosConfigurations = {
        # Example server configuration
        myServer = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            keystone.nixosModules.diskoSingleDiskRoot
            keystone.nixosModules.server
            {
              # Configure the disko module
              keystone.disko = {
                enable = true;
                device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0W127373V";
                enableEncryptedSwap = true;
                swapSize = "64G";
                espSize = "1G";
              };

              # Your additional configuration
              networking.hostName = "my-server";
              users.users.admin = {
                isNormalUser = true;
                extraGroups = [ "wheel" ];
                openssh.authorizedKeys.keys = [
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your-key-here"
                ];
              };
            }
          ];
        };

        # Example client configuration
        myClient = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            keystone.nixosModules.diskoSingleDiskRoot
            keystone.nixosModules.client
            {
              # Configure the disko module for client
              keystone.disko = {
                enable = true;
                device = "/dev/disk/by-id/nvme-WD_BLACK_SN850X_2TB_23182L463847";
                enableEncryptedSwap = true;
                swapSize = "32G"; # Smaller swap for client
                espSize = "1G";
              };

              # Client-specific configuration
              networking.hostName = "my-laptop";
              users.users.user = {
                isNormalUser = true;
                extraGroups = [
                  "wheel"
                  "networkmanager"
                  "audio"
                ];
              };
            }
          ];
        };

        # Example configuration without encrypted swap
        minimalServer = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            keystone.nixosModules.diskoSingleDiskRoot
            keystone.nixosModules.server
            {
              keystone.disko = {
                enable = true;
                device = "/dev/disk/by-id/ata-Samsung_SSD_850_EVO_1TB_S21NNSAG123456";
                enableEncryptedSwap = false; # No swap partition
                espSize = "512M"; # Smaller ESP
              };

              networking.hostName = "minimal-server";
            }
          ];
        };
      };
    };
}
# Usage with nixos-anywhere:
#
# 1. Generate SSH keys and build ISO:
#    bin/build-iso path/to/your/ssh/key.pub
#
# 2. Boot target machine from ISO and get IP address
#
# 3. Deploy using nixos-anywhere:
#    nixos-anywhere --flake .#myServer root@<target-ip>
#
# The disko-single-disk-root module will:
# - Partition the specified disk
# - Create encrypted ZFS pool with credstore
# - Set up proper dataset layout
# - Configure systemd services for credstore management
# - Enable ZFS features like snapshots and scrubbing
