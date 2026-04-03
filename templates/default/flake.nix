{
  description = "My Keystone Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Keystone - secure infrastructure platform
    keystone = {
      url = "github:ncrmro/keystone";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      keystone,
      ...
    }:
    {
      # ==========================================================================
      # NIXOS CONFIGURATIONS
      # ==========================================================================
      #
      # Define your machines here. Rename "my-machine" to your hostname.
      # Add additional machines by duplicating the block below.
      #
      nixosConfigurations = {
        # TODO: Rename "my-machine" to your actual hostname
        my-machine = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # Keystone operating system module
            keystone.nixosModules.operating-system
            # keystone.nixosModules.desktop  # Uncomment for Hyprland desktop

            # Your configuration
            ./configuration.nix
            ./hardware.nix
          ];
        };

        # ────────────────────────────────────────────────────────────────────────
        # EXAMPLE: Adding a desktop machine
        # ────────────────────────────────────────────────────────────────────────
        #
        # my-laptop = nixpkgs.lib.nixosSystem {
        #   system = "x86_64-linux";
        #   modules = [
        #     keystone.nixosModules.operating-system
        #     keystone.nixosModules.desktop  # Adds Hyprland desktop environment
        #     ./machines/laptop/configuration.nix
        #     ./machines/laptop/hardware.nix
        #   ];
        # };
      };

      # Development shell (optional - for managing this flake)
      devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
        packages = with nixpkgs.legacyPackages.x86_64-linux; [
          nixfmt
          nil
        ];
      };
    };
}
