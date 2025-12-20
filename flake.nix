{
  description = "Keystone NixOS installation media";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    omarchy = {
      url = "github:basecamp/omarchy/v3.0.2";
      flake = false;
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    disko,
    home-manager,
    omarchy,
    lanzaboote,
    ...
  }: {
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;

    # ISO configuration without SSH keys (use bin/build-iso for SSH keys)
    nixosConfigurations = {
      keystoneIso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./modules/iso-installer.nix
          {
            _module.args.sshKeys = [];
            # Force kernel 6.12 - must be set here to override minimal CD
            boot.kernelPackages = nixpkgs.lib.mkForce nixpkgs.legacyPackages.x86_64-linux.linuxPackages_6_12;
          }
        ];
      };

      # Test server configuration for nixos-anywhere deployment
      test-server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          ./modules/server
          ./modules/disko-single-disk-root
          ./modules/initrd-ssh-unlock
          ./modules/secure-boot
          ./modules/tpm-enrollment
          ./modules/users
          ./vms/test-server/configuration.nix
        ];
      };

      # Test Hyprland desktop configuration
      test-hyprland = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          home-manager.nixosModules.home-manager
          ./modules/client
          ./modules/disko-single-disk-root
          ./modules/initrd-ssh-unlock
          ./modules/secure-boot
          ./modules/tpm-enrollment
          ./modules/users
          ./vms/test-hyprland/configuration.nix
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
          ./vms/build-vm-terminal/configuration.nix
        ];
      };

      # Hyprland desktop testing
      build-vm-desktop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          home-manager.nixosModules.home-manager
          ./vms/build-vm-desktop/configuration.nix
          {
            _module.args.omarchy = omarchy;
          }
        ];
      };
    };

    # Home-manager configurations for testing
    homeConfigurations = {
      testuser = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        modules = [
          ./home-manager/modules/terminal-dev-environment
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

    # Export Keystone modules for use in other flakes
    nixosModules = {
      server = ./modules/server;
      client = ./modules/client;
      clientHome = ./modules/client/home;
      diskoSingleDiskRoot = ./modules/disko-single-disk-root;
      initrdSshUnlock = ./modules/initrd-ssh-unlock;
      isoInstaller = ./modules/iso-installer.nix;
      secureBoot = ./modules/secure-boot;
      ssh = ./modules/ssh;
      tpmEnrollment = ./modules/tpm-enrollment;
      users = ./modules/users;
      # Standalone desktop module (no disko/encryption dependencies)
      desktop = ./modules/keystone/desktop/nixos.nix;
    };

    # Export home-manager modules (homeModules is the standard flake output name)
    homeModules = {
      terminalDevEnvironment = ./home-manager/modules/terminal-dev-environment;
      desktopHyprland = ./home-manager/modules/desktop/hyprland;
      # Keystone-specific home-manager modules
      terminal = ./modules/keystone/terminal/default.nix;
      desktop = ./modules/keystone/desktop/home/default.nix;
    };

    packages.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      iso = self.nixosConfigurations.keystoneIso.config.system.build.isoImage;
      zesh = pkgs.callPackage ./packages/zesh {};
      keystone-installer-ui = pkgs.callPackage ./packages/keystone-installer-ui {};
      keystone-ha-tui-client = pkgs.callPackage ./packages/keystone-ha/tui {};

      # Internal VM test - run with: nix build .#installer-test
      # Not in checks to avoid IFD evaluation issues with nix flake check
      # (NixOS VM tests use kernel modules that cause IFD failures in CI)
      installer-test = import ./tests/installer-test.nix {
        inherit pkgs;
        lib = pkgs.lib;
      };
    };

    # Development shell
    devShells.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      default = pkgs.mkShell {
        name = "keystone-dev";

        # Rust development
        nativeBuildInputs = with pkgs; [
          cargo
          rustc
          rust-analyzer
          clippy
          rustfmt
          pkg-config
        ];

        buildInputs = with pkgs; [
          openssl
        ];

        # Node.js development
        packages = with pkgs; [
          nodejs
          nodePackages.npm
          nodePackages.typescript
          nodePackages.typescript-language-server

          # Nix tools
          nixfmt-rfc-style
          nil # Nix LSP
          nix-tree
          nvd # Nix version diff

          # VM and deployment tools
          qemu
          libvirt
          virt-viewer

          # General utilities
          jq
          yq-go
          gh # GitHub CLI
        ];

        shellHook = ''
          echo "🔑 Keystone development shell"
          echo ""
          echo "Available commands:"
          echo "  ./bin/build-iso        - Build installer ISO"
          echo "  ./bin/build-vm         - Fast VM testing (terminal/desktop)"
          echo "  ./bin/virtual-machine  - Full stack VM with libvirt"
          echo "  nix flake check        - Validate flake"
          echo ""
          echo "Rust packages:  packages/keystone-ha/"
          echo "Node packages:  packages/keystone-installer-ui/"
        '';

        # Rust environment variables
        RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";
      };
    };
  };
}
