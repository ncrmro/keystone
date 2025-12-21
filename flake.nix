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
    # Note: Test/dev configurations are in ./tests/flake.nix
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
    };

    # Export Keystone modules for use in other flakes
    nixosModules = {
      # Consolidated OS module - includes storage, secure boot, TPM, remote unlock, users
      operating-system = {
        imports = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          ./modules/os
        ];
      };

      # High-level role modules (auto-include operating-system)
      server = ./modules/server;
      client = ./modules/client;

      # Other modules
      isoInstaller = ./modules/iso-installer.nix;
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

    # Packages exported for consumption
    # Note: Tests are in ./tests/flake.nix (separate flake to avoid IFD issues)
    packages.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      iso = self.nixosConfigurations.keystoneIso.config.system.build.isoImage;
      zesh = pkgs.callPackage ./packages/zesh {};
      keystone-installer-ui = pkgs.callPackage ./packages/keystone-installer-ui {};
      keystone-ha-tui-client = pkgs.callPackage ./packages/keystone-ha/tui {};
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
