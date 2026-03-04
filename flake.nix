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
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland.url = "github:hyprwm/Hyprland";
    himalaya = {
      url = "github:pimalaya/himalaya";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    browser-previews = {
      url = "github:nix-community/browser-previews";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Desktop tools
    ghostty.url = "github:ghostty-org/ghostty";
    yazi.url = "github:sxyazi/yazi";
    walker = {
      url = "github:abenz1267/walker";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secret management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # NixOS tools
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Helix editor themes
    kinda-nvim-hx = {
      url = "github:strash/kinda_nvim.hx";
      flake = false;
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
    himalaya,
    llm-agents,
    browser-previews,
    ghostty,
    yazi,
    walker,
    agenix,
    nix-index-database,
    nix-flatpak,
    nixos-hardware,
    kinda-nvim-hx,
    ...
  }: let
    # Create inputs attrset for keystone modules (named keystoneInputs to avoid
    # shadowing when consumed by other flakes that pass their own `inputs`)
    keystoneInputs = {
      inherit
        nixpkgs
        hyprland
        himalaya
        llm-agents
        browser-previews
        agenix
        walker
        nix-index-database
        nix-flatpak
        nixos-hardware
        kinda-nvim-hx
        omarchy
        ;
    };
  in {
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;

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

    # Overlay that provides keystone packages
    # NOTE: Paths must be captured in `let` BEFORE the function, otherwise they
    # get evaluated in the wrong context when the overlay is applied by a consumer flake
    overlays.default = let
      zesh-src = ./packages/zesh;
      himalaya-flake = himalaya;
      llm-agents-flake = llm-agents;
      browser-previews-flake = browser-previews;
      ghostty-flake = ghostty;
      yazi-flake = yazi;
    in final: prev: {
      keystone = {
        zesh = final.callPackage zesh-src {};
        himalaya = himalaya-flake.packages.${final.system}.default;
        # AI coding agents from llm-agents.nix
        claude-code = llm-agents-flake.packages.${final.system}.claude-code;
        gemini-cli = llm-agents-flake.packages.${final.system}.gemini-cli;
        codex = llm-agents-flake.packages.${final.system}.codex;
        # Browsers from browser-previews
        google-chrome = browser-previews-flake.packages.${final.system}.google-chrome;
        # Desktop tools from flake inputs
        ghostty = ghostty-flake.packages.${final.system}.default;
        yazi = yazi-flake.packages.${final.system}.default;
      };
      # Top-level overrides so programs.ghostty/yazi use flake versions
      ghostty = ghostty-flake.packages.${final.system}.default;
      yazi = yazi-flake.packages.${final.system}.default;
    };

    # Export Keystone modules for use in other flakes
    nixosModules = {
      # Shared domain option (keystone.domain) — used by OS agents and server services
      domain = ./modules/domain.nix;

      # Core OS module - storage, secure boot, TPM, remote unlock, users, services
      operating-system = {
        imports = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          ./modules/domain.nix
          ./modules/os
        ];
      };

      # Desktop module - Hyprland, audio, greetd (no disko/encryption dependencies)
      desktop = {
        imports = [
          keystoneInputs.nix-flatpak.nixosModules.nix-flatpak
          ./modules/desktop/nixos.nix
        ];
        _module.args.keystoneInputs = keystoneInputs;
      };

      # Server module - VPN, monitoring, mail, binary cache (optional services)
      server = {
        imports = [
          ./modules/domain.nix
          ./modules/server
        ];
      };

      # Binary cache client - configures nix substituters for Attic cache
      binaryCacheClient = ./modules/binary-cache-client.nix;

      # ISO installer module
      isoInstaller = ./modules/iso-installer.nix;

      # Hardware key module - FIDO2/YubiKey for GPG/SSH agent
      hardwareKey = ./modules/os/hardware-key.nix;
    };

    # Export home-manager modules (homeModules is the standard flake output name)
    homeModules = {
      desktopHyprland = ./home-manager/modules/desktop/hyprland;
      # Keystone-specific home-manager modules
      terminal = {
        imports = [./modules/terminal/default.nix];
        _module.args.keystoneInputs = keystoneInputs;
      };
      desktop = {
        imports = [
          keystoneInputs.walker.homeManagerModules.default
          ./modules/desktop/home/default.nix
        ];
        _module.args.keystoneInputs = keystoneInputs;
      };
    };

    # Flake checks — run via `nix flake check` and CI
    checks.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      lib = pkgs.lib;
    in {
      # Module evaluation tests (fast, no VM boot required)
      os-evaluation = import ./tests/module/os-evaluation.nix {
        inherit pkgs lib;
        self = self;
      };
      agent-evaluation = import ./tests/module/agent-evaluation.nix {
        inherit pkgs lib nixpkgs;
        self = self;
      };
    };

    # Packages exported for consumption
    # Note: Integration/VM tests are in ./tests/flake.nix (separate flake to avoid IFD issues)
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
          nixfmt
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
