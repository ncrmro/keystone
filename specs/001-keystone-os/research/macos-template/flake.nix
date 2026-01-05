{
  description = "MacBook Asahi Linux Configuration - Remote Build Template";

  inputs = {
    # Nixpkgs - using unstable for latest Asahi support
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Keystone - secure infrastructure platform
    keystone = {
      url = "github:ncrmro/keystone";
      # IMPORTANT: Do NOT use `inputs.nixpkgs.follows = "nixpkgs"` here!
      # This would force recompilation of the Asahi kernel (hours of compile time).
      # Keystone pins nixpkgs for binary cache compatibility.
    };

    # nixos-apple-silicon - Apple Silicon hardware support
    nixos-apple-silicon = {
      url = "github:tpwrules/nixos-apple-silicon";
      # Also do NOT follow nixpkgs - uses same pinned version for kernel cache
    };

    # Home Manager - user environment management
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland - tiling compositor (required by keystone desktop modules)
    hyprland.url = "github:hyprwm/Hyprland";

    # Walker - application launcher (required by keystone desktop modules)
    elephant.url = "github:abenz1267/elephant";
    walker = {
      url = "github:abenz1267/walker";
      inputs.elephant.follows = "elephant";
    };

    # Omarchy themes (required by keystone desktop theming)
    omarchy = {
      url = "github:basecamp/omarchy/v3.0.2";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    keystone,
    nixos-apple-silicon,
    home-manager,
    hyprland,
    elephant,
    walker,
    omarchy,
    ...
  } @ inputs: {
    # ==========================================================================
    # NIXOS CONFIGURATIONS
    # ==========================================================================

    nixosConfigurations = {
      # MacBook configuration - builds on OrbStack, deploys to MacBook
      macbook = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        # Pass inputs to NixOS modules
        specialArgs = {inherit inputs;};
        modules = [
          # Apple Silicon hardware support (Asahi kernel, GPU drivers, etc.)
          nixos-apple-silicon.nixosModules.apple-silicon-support

          # Home Manager for user environments
          home-manager.nixosModules.home-manager

          # Keystone desktop module (Hyprland, greetd, PipeWire)
          keystone.nixosModules.desktop

          # Apply Keystone overlay (provides pkgs.keystone.claude-code, etc.)
          {
            nixpkgs.overlays = [keystone.overlays.default];
          }

          # Home-manager integration with Keystone modules
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              # Pass inputs to home-manager modules
              extraSpecialArgs = {inherit inputs;};
              # Note: terminal module is already included by desktop module
              sharedModules = [
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
    # DEVELOPMENT SHELL (for macOS host)
    # ==========================================================================

    # Shell for development on macOS
    devShells.aarch64-darwin.default = nixpkgs.legacyPackages.aarch64-darwin.mkShell {
      packages = with nixpkgs.legacyPackages.aarch64-darwin; [
        nixfmt-rfc-style
        nil
      ];
    };

    # Shell for Linux (OrbStack VM)
    devShells.aarch64-linux.default = nixpkgs.legacyPackages.aarch64-linux.mkShell {
      packages = with nixpkgs.legacyPackages.aarch64-linux; [
        nixfmt-rfc-style
        nil
      ];
    };
  };
}
