{
  description = "Keystone Apple Silicon Configuration";

  inputs = {
    # Nixpkgs - using unstable for latest Asahi support
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Keystone - secure infrastructure platform
    keystone = {
      url = "github:ncrmro/keystone";
      # Note: Do NOT use `inputs.nixpkgs.follows = "nixpkgs"` here!
      # This would force recompilation of the Asahi kernel.
      # Keystone pins nixpkgs for binary cache compatibility.
    };

    # nixos-apple-silicon - Apple Silicon hardware support
    nixos-apple-silicon = {
      url = "github:tpwrules/nixos-apple-silicon";
      # Also do NOT follow nixpkgs - uses same pinned version as Keystone
    };

    # Home Manager - user environment management
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    keystone,
    nixos-apple-silicon,
    home-manager,
    ...
  }: {
    # ==========================================================================
    # NIXOS CONFIGURATIONS
    # ==========================================================================

    nixosConfigurations = {
      # TODO: Rename "keystone-mac" to your preferred hostname
      keystone-mac = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          # Apple Silicon hardware support (Asahi kernel, GPU drivers, etc.)
          nixos-apple-silicon.nixosModules.apple-silicon-support

          # Home Manager for user environments
          home-manager.nixosModules.home-manager

          # Keystone desktop module (Hyprland, greetd, PipeWire)
          keystone.nixosModules.desktop

          # Home-manager integration with Keystone modules
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              sharedModules = [
                keystone.homeModules.terminal
                keystone.homeModules.desktop
              ];
            };
          }

          # Your configuration
          ./configuration.nix
        ];
      };
    };

    # ==========================================================================
    # DEVELOPMENT SHELL
    # ==========================================================================

    devShells.aarch64-linux.default = nixpkgs.legacyPackages.aarch64-linux.mkShell {
      packages = with nixpkgs.legacyPackages.aarch64-linux; [
        nixfmt-rfc-style
        nil
      ];
    };
  };
}
