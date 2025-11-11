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
    };

    # Export home-manager modules
    homeManagerModules = {
      terminalDevEnvironment = ./home-manager/modules/terminal-dev-environment;
      desktopHyprland = ./home-manager/modules/desktop/hyprland;
    };

    packages.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      iso = self.nixosConfigurations.keystoneIso.config.system.build.isoImage;
      zesh = pkgs.callPackage ./packages/zesh {};
    };

    # Development shell with terminal dev environment tools
    devShells.x86_64-linux.default = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      zesh = pkgs.callPackage ./packages/zesh {};
    in
      pkgs.mkShell {
        name = "keystone-dev";

        packages = with pkgs; [
          # Version control
          git
          git-lfs
          lazygit

          # Editor
          helix

          # Shell utilities
          zsh
          starship
          zoxide
          direnv
          nix-direnv

          # Terminal multiplexer
          zellij

          # Terminal emulator
          ghostty

          # File utilities
          eza
          ripgrep
          tree
          fd
          bat

          # Data processing
          jq
          yq
          csview

          # System utilities
          htop
          bottom

          # Nix tools
          nixfmt-rfc-style
          nil # Nix LSP
          nixos-anywhere

          # Custom packages
          zesh
        ];

        shellHook = ''
          echo "🔑 Keystone Development Environment"
          echo ""
          echo "Available tools:"
          echo "  - Git (with lazygit UI)"
          echo "  - Helix editor"
          echo "  - Zsh with starship prompt"
          echo "  - Zellij terminal multiplexer"
          echo "  - Ghostty terminal emulator"
          echo "  - Modern CLI tools (eza, ripgrep, bat, fd)"
          echo "  - Nix development tools (nixfmt, nil)"
          echo ""
          echo "Quick commands:"
          echo "  - 'hx' - Open Helix editor"
          echo "  - 'lg' - Open lazygit"
          echo "  - 'zesh' - Zellij session manager"
          echo ""
        '';
      };
  };
}
