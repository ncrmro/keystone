{
  description = "My Keystone Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Keystone - secure infrastructure platform
    keystone = {
      url = "github:ncrmro/keystone";
      inputs.nixpkgs.follows = "nixpkgs";
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
    home-manager,
    ...
  }: let
    # Default system architecture
    defaultSystem = "x86_64-linux";

    # ==========================================================================
    # INSTALLER OPTIONS
    # ==========================================================================

    # SSH keys for installer access (required for remote deployment)
    # TODO: Add your SSH public key(s)
    installerSshKeys = [
      # "ssh-ed25519 AAAAC3... admin@laptop"
      # "ssh-ed25519 AAAAC3... admin@workstation"
    ];

    # TUI Installer: Set to false for SSH-only headless mode
    # When disabled, boots to normal login prompt + SSH access
    enableTuiInstaller = true;

    # aarch64-linux ISO: Enable for Apple Silicon / ARM64 servers
    # Requires binfmt emulation or aarch64 remote builder to build
    buildAarch64Iso = false;

    # Helper to create installer for any architecture
    mkInstaller = system:
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          keystone.nixosModules.isoInstaller
          {
            _module.args.sshKeys = installerSshKeys;
            _module.args.enableTui = enableTuiInstaller;
            boot.kernelPackages =
              nixpkgs.lib.mkForce
              nixpkgs.legacyPackages.${system}.linuxPackages_6_12;
          }
        ];
      };
  in {
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
        system = defaultSystem;
        modules = [
          # Home Manager for user environments
          home-manager.nixosModules.home-manager

          # Keystone operating system module
          keystone.nixosModules.operating-system
          # keystone.nixosModules.desktop  # Uncomment for Hyprland desktop

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
          ./hardware.nix
        ];
      };

      # ────────────────────────────────────────────────────────────────────────
      # EXAMPLE: Adding a desktop machine
      # ────────────────────────────────────────────────────────────────────────
      #
      # my-laptop = nixpkgs.lib.nixosSystem {
      #   system = defaultSystem;
      #   modules = [
      #     home-manager.nixosModules.home-manager
      #     keystone.nixosModules.operating-system
      #     keystone.nixosModules.desktop  # Adds Hyprland desktop environment
      #     {
      #       home-manager = {
      #         useGlobalPkgs = true;
      #         useUserPackages = true;
      #         sharedModules = [
      #           keystone.homeModules.terminal
      #           keystone.homeModules.desktop
      #         ];
      #       };
      #     }
      #     ./machines/laptop/configuration.nix
      #     ./machines/laptop/hardware.nix
      #   ];
      # };

      # ────────────────────────────────────────────────────────────────────────
      # INSTALLER ISO
      # ────────────────────────────────────────────────────────────────────────
      #
      # Custom Keystone installer with your SSH keys pre-configured.
      # Build with: nix build .#installer-iso
      #
      installer = mkInstaller defaultSystem;

      # aarch64-linux installer (for Apple Silicon / ARM64 servers)
      # Build with: nix build .#installer-iso-aarch64
      installer-aarch64 = mkInstaller "aarch64-linux";
    };

    # ==========================================================================
    # PACKAGES
    # ==========================================================================

    packages.${defaultSystem} =
      {
        # Build installer ISO: nix build .#installer-iso
        installer-iso = self.nixosConfigurations.installer.config.system.build.isoImage;

        # Shorthand alias
        default = self.packages.${defaultSystem}.installer-iso;
      }
      // (
        if buildAarch64Iso
        then {
          # Build ARM64 ISO: nix build .#installer-iso-aarch64
          installer-iso-aarch64 = self.nixosConfigurations.installer-aarch64.config.system.build.isoImage;
        }
        else {}
      );

    # Development shell (optional - for managing this flake)
    devShells.${defaultSystem}.default = nixpkgs.legacyPackages.${defaultSystem}.mkShell {
      packages = with nixpkgs.legacyPackages.${defaultSystem}; [
        nixfmt-rfc-style
        nil
      ];
    };
  };
}
