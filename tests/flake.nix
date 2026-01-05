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
    hyprland.follows = "keystone/hyprland";
    # MicroVM for fast cluster testing with network access
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Agenix for secret management testing
    agenix = {
      url = "github:ryantm/agenix";
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
    hyprland,
    microvm,
    agenix,
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
          keystone.nixosModules.operating-system
          ../vms/test-server/configuration.nix
        ];
      };

      # Test Hyprland desktop configuration
      test-hyprland = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          home-manager.nixosModules.home-manager
          keystone.nixosModules.operating-system
          keystone.nixosModules.desktop
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
        specialArgs = {
          inputs = {
            inherit nixpkgs hyprland;
          };
        };
        modules = [
          home-manager.nixosModules.home-manager
          ../vms/build-vm-desktop/configuration.nix
          {
            _module.args.omarchy = omarchy;
          }
        ];
      };

      # ============================================================
      # MicroVM Cluster Configurations
      # ============================================================
      # These use microvm.nix for fast cluster testing with network access

      # Cluster primer with k3s + Headscale
      cluster-primer = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          microvm.nixosModules.microvm
          agenix.nixosModules.default
          keystone.nixosModules.cluster-primer
          ./microvm/cluster-primer.nix
        ];
      };

      # Cluster worker nodes
      cluster-worker1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          microvm.nixosModules.microvm
          keystone.nixosModules.cluster-worker
          ./microvm/cluster-worker.nix
          {
            networking.hostName = "worker1";
            microvm.interfaces = [ { type = "user"; id = "net0"; mac = "02:00:00:00:00:11"; } ];
            microvm.forwardPorts = [ { from = "host"; host.port = 22231; guest.port = 22; } ];
          }
        ];
      };

      cluster-worker2 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          microvm.nixosModules.microvm
          keystone.nixosModules.cluster-worker
          ./microvm/cluster-worker.nix
          {
            networking.hostName = "worker2";
            microvm.interfaces = [ { type = "user"; id = "net0"; mac = "02:00:00:00:00:12"; } ];
            microvm.forwardPorts = [ { from = "host"; host.port = 22232; guest.port = 22; } ];
          }
        ];
      };

      cluster-worker3 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          microvm.nixosModules.microvm
          keystone.nixosModules.cluster-worker
          ./microvm/cluster-worker.nix
          {
            networking.hostName = "worker3";
            microvm.interfaces = [ { type = "user"; id = "net0"; mac = "02:00:00:00:00:13"; } ];
            microvm.forwardPorts = [ { from = "host"; host.port = 22233; guest.port = 22; } ];
          }
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

      # Cluster Tests
      cluster-headscale = import ./integration/cluster-headscale.nix {
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
    packages.${system} = self.checks.${system};
  };
}
