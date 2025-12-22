{
  description = "Keystone test suite and development configurations";

  inputs = {
    # Reference the parent Keystone flake
    keystone.url = "path:..";
    # Follow inputs from parent to ensure consistency
    nixpkgs.follows = "keystone/nixpkgs";
    home-manager.follows = "keystone/home-manager";
    disko.follows = "keystone/disko";
    lanzaboote.follows = "keystone/lanzaboote";
    omarchy.follows = "keystone/omarchy";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    keystone,
    nixpkgs,
    home-manager,
    disko,
    lanzaboote,
    omarchy,
    microvm,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    lib = pkgs.lib;
  in {
    # ============================================================
    # NixOS Configurations for Testing and Development
    # ============================================================

    nixosConfigurations = {
      # Test server configuration for nixos-anywhere deployment
      test-server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          keystone.nixosModules.server
          ../vms/test-server/configuration.nix
        ];
      };

      # Test Hyprland desktop configuration
      test-hyprland = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          home-manager.nixosModules.home-manager
          keystone.nixosModules.client
          ../vms/test-hyprland/configuration.nix
          {
            _module.args.omarchy = omarchy;
          }
        ];
      };

      # Fast VM testing configurations using nixos-rebuild build-vm
      # These skip disko/encryption/secure boot for rapid iteration

      # Terminal development environment testing
      build-vm-terminal = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          home-manager.nixosModules.home-manager
          ../vms/build-vm-terminal/configuration.nix
        ];
      };

      # Hyprland desktop testing
      build-vm-desktop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          home-manager.nixosModules.home-manager
          ../vms/build-vm-desktop/configuration.nix
          {
            _module.args.omarchy = omarchy;
          }
        ];
      };

      # MicroVM testing configurations
      tpm-microvm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          microvm.nixosModules.microvm
          disko.nixosModules.disko
          keystone.nixosModules.operating-system # This enables keystone.os.* options
          ./microvm/tpm-test.nix
        ];
      };
    };

    # ============================================================
    # Home Manager Configurations for Testing
    # ============================================================

    homeConfigurations = {
      testuser = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        modules = [
          ../home-manager/modules/terminal-dev-environment
          {
            home.username = "testuser";
            home.homeDirectory = "/home/testuser";
            home.stateVersion = "25.05";

            programs.terminal-dev-environment.enable = true;

            programs.git = {
              userName = "Test User";
              userEmail = "testuser@keystone-test-vm";
            };
          }
        ];
      };
    };

    # ============================================================
    # VM Tests (in checks)
    # ============================================================

    checks.${system} = {
      # Integration Tests
      test-installer = import ./integration/installer.nix {
        inherit pkgs;
        lib = pkgs.lib;
      };

      test-remote-unlock = import ./integration/remote-unlock.nix {
        inherit pkgs lib;
        self = keystone;
      };

      # Module Isolation Tests
      test-desktop-isolation = import ./module/desktop-isolation.nix {
        inherit pkgs lib;
        self = keystone;
      };

      test-server-isolation = import ./module/server-isolation.nix {
        inherit pkgs lib;
        self = keystone;
      };

      # Evaluation Tests
      test-os-evaluation = import ./module/os-evaluation.nix {
        inherit pkgs lib;
        self = keystone;
      };
    };

    # Also expose tests as packages for convenience
    packages.${system} =
      self.checks.${system}
      // {
        test-microvm-tpm = pkgs.writeShellApplication {
          name = "test-microvm-tpm";
          runtimeInputs = [pkgs.swtpm];
          text = builtins.readFile ../bin/test-microvm-tpm;
        };
      };
  };
}
