{
  description = "Keystone NixOS installation media";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
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
    hyprland.url = "github:hyprwm/Hyprland";

    # Walker application launcher
    elephant.url = "github:abenz1267/elephant";
    walker = {
      url = "github:abenz1267/walker";
      inputs.elephant.follows = "elephant";
    };

    # Apple Silicon support (Asahi Linux kernel and hardware)
    nixos-apple-silicon = {
      url = "github:tpwrules/nixos-apple-silicon";
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
    hyprland,
    elephant,
    walker,
    nixos-apple-silicon,
    ...
  }: let
    # Create inputs attrset for desktop module
    inputs = {
      inherit nixpkgs hyprland walker;
    };
  in {
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;

    # ISO configuration without SSH keys (use bin/build-iso for SSH keys)
    # Note: Test/dev configurations are in ./tests/flake.nix
    nixosConfigurations = {
      # x86_64 ISO configuration
      keystoneIso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./modules/iso-installer.nix
          {
            _module.args.sshKeys = [];
            _module.args.enableTui = true;
            # Force kernel 6.12 - must be set here to override minimal CD
            boot.kernelPackages = nixpkgs.lib.mkForce nixpkgs.legacyPackages.x86_64-linux.linuxPackages_6_12;
          }
        ];
      };

      # Apple Silicon (aarch64) ISO configuration
      # Uses Asahi Linux kernel and hardware support from nixos-apple-silicon
      keystoneIsoAppleSilicon = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          nixos-apple-silicon.nixosModules.apple-silicon-support
          ./modules/iso-installer-apple-silicon.nix
          {
            _module.args.sshKeys = [];
            _module.args.enableTui = true;
          }
        ];
      };
    };

    # Overlay that provides keystone packages
    # NOTE: Paths must be captured in `let` BEFORE the function, otherwise they
    # get evaluated in the wrong context when the overlay is applied by a consumer flake
    overlays.default = let
      zesh-src = ./packages/zesh;
      claude-code-src = ./modules/terminal/claude-code;
    in final: prev: {
      keystone = {
        zesh = final.callPackage zesh-src {};
        claude-code = final.callPackage claude-code-src {};
      };
    };

    # Export Keystone modules for use in other flakes
    nixosModules = {
      # Core OS module - storage, secure boot, TPM, remote unlock, users, services
      operating-system = {
        imports = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          ./modules/os
        ];
      };

      # Desktop module - Hyprland, audio, greetd (no disko/encryption dependencies)
      desktop = {
        imports = [./modules/desktop/nixos.nix];
        _module.args.inputs = inputs;
      };

      # Server module - VPN, monitoring, mail (optional services)
      server = ./modules/server;

      # Agent Sandbox module - isolated AI coding agent environments
      agent = {
        imports = [./modules/keystone/agent];
      };

      # ISO installer module
      isoInstaller = ./modules/iso-installer.nix;
      isoInstallerAppleSilicon = {
        imports = [
          nixos-apple-silicon.nixosModules.apple-silicon-support
          ./modules/iso-installer-apple-silicon.nix
        ];
      };
    };

    # Export home-manager modules (homeModules is the standard flake output name)
    homeModules = {
      desktopHyprland = ./home-manager/modules/desktop/hyprland;
      # Keystone-specific home-manager modules
      terminal = ./modules/terminal/default.nix;
      desktop = ./modules/desktop/home/default.nix;
      agentTui = ./modules/keystone/agent/home/tui.nix;
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
      keystone-agent = pkgs.callPackage ./packages/keystone-agent {};
    };

    # Apple Silicon (aarch64) packages
    packages.aarch64-linux = {
      iso = self.nixosConfigurations.keystoneIsoAppleSilicon.config.system.build.isoImage;
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
          swtpm

          # General utilities
          jq
          yq-go
          gh # GitHub CLI
          python3
        ];

        shellHook = ''
          echo "🔑 Keystone development shell"
          echo ""
          echo "Available commands:"
          echo "  make build-iso-ssh          - Build x86_64 ISO with your SSH key"
          echo "  make build-iso-ssh-aarch64  - Build ARM64 ISO with your SSH key"
          echo "  ./bin/build-vm              - Fast VM testing (terminal/desktop)"
          echo "  ./bin/virtual-machine       - Full stack VM with libvirt"
          echo "  nix flake check             - Validate flake"
          echo ""

          # Check cross-compilation capability
          if [[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
            echo "✅ aarch64 cross-compilation: enabled (binfmt)"
          elif nix show-config 2>/dev/null | grep -q "extra-platforms.*aarch64"; then
            echo "✅ aarch64 cross-compilation: enabled (remote builder)"
          else
            echo "⚠️  aarch64 cross-compilation: not configured"
            echo "   Enable with: boot.binfmt.emulatedSystems = [ \"aarch64-linux\" ];"
          fi
          echo ""
        '';

        # Rust environment variables
        RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";
      };
    };

    # Flake templates for users to scaffold new projects
    templates = {
      default = {
        path = ./templates/default;
        description = "Keystone infrastructure starter with OS module and home-manager";
        welcomeText = ''
          # Keystone Infrastructure Configuration

          Your project has been initialized!

          ## Quick Start

          1. Edit configuration.nix - search for TODO: to find required changes
          2. Generate hostId: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
          3. Find your disk: ls -l /dev/disk/by-id/
          4. Deploy: nixos-anywhere --flake .#my-machine root@<installer-ip>

          See README.md for detailed instructions.
        '';
      };
    };
  };
}
