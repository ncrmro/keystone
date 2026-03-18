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
    calendula = {
      url = "github:pimalaya/calendula";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cardamum = {
      url = "github:pimalaya/cardamum";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    comodoro = {
      url = "github:pimalaya/comodoro";
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

    deepwork.url = "github:Unsupervisedcom/deepwork";
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
    calendula,
    cardamum,
    comodoro,
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
    deepwork,
    ...
  }: let
    # Create inputs attrset for keystone modules (named keystoneInputs to avoid
    # shadowing when consumed by other flakes that pass their own `inputs`)
    keystoneInputs = {
      inherit
        nixpkgs
        disko
        lanzaboote
        home-manager
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
      keystoneOverlay = self.overlays.default;
    };
  in {
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;

    # Build an installer ISO with the given SSH keys baked in.
    # Consumer flakes call this instead of duplicating the module wiring.
    lib.mkInstallerIso = {
      nixpkgs,
      sshKeys ? [],
      system ? "x86_64-linux",
    }:
      (nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./modules/iso-installer.nix
          {
            keystone.installer.sshKeys = sshKeys;
            # Force kernel 6.12 — must be set here to override minimal CD default
            boot.kernelPackages = nixpkgs.lib.mkForce
              nixpkgs.legacyPackages.${system}.linuxPackages_6_12;
          }
        ];
      }).config.system.build.isoImage;

    # ISO configuration without SSH keys (use lib.mkInstallerIso for keys)
    # Note: Test/dev configurations are in ./tests/flake.nix
    nixosConfigurations = {
      keystoneIso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./modules/iso-installer.nix
          {
            # Force kernel 6.12 — must be set here to override minimal CD default
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
      agent-coding-agent-src = ./packages/agent-coding-agent;
      agent-mail-src = ./packages/agent-mail;
      fetch-email-source-src = ./packages/fetch-email-source;
      fetch-forgejo-sources-src = ./packages/fetch-forgejo-sources;
      fetch-github-sources-src = ./packages/fetch-github-sources;
      repo-sync-src = ./packages/repo-sync;
      podman-agent-src = ./packages/podman-agent;
      ks-src = ./packages/ks;
      himalaya-flake = himalaya;
      calendula-flake = calendula;
      cardamum-flake = cardamum;
      comodoro-flake = comodoro;
      llm-agents-flake = llm-agents;
      browser-previews-flake = browser-previews;
      ghostty-flake = ghostty;
      yazi-flake = yazi;
      agenix-flake = agenix;
      deepwork-flake = deepwork;
      chrome-devtools-mcp-src = ./packages/chrome-devtools-mcp;
    in final: prev: {
      keystone = {
        zesh = final.callPackage zesh-src {};
        agent-coding-agent = final.callPackage agent-coding-agent-src {};
        agent-mail = final.callPackage agent-mail-src { himalaya = final.keystone.himalaya; };
        fetch-email-source = final.callPackage fetch-email-source-src { himalaya = final.keystone.himalaya; };
        fetch-forgejo-sources = final.callPackage fetch-forgejo-sources-src {};
        fetch-github-sources = final.callPackage fetch-github-sources-src {};
        repo-sync = final.callPackage repo-sync-src {};
        podman-agent = final.callPackage podman-agent-src {};
        ks = final.callPackage ks-src {};
        himalaya = himalaya-flake.packages.${final.system}.default;
        calendula = calendula-flake.packages.${final.system}.default;
        cardamum = cardamum-flake.packages.${final.system}.default;
        # Comodoro upstream flake is missing dbus from buildInputs/nativeBuildInputs.
        # The postInstall phase runs the binary (to generate completions) before
        # fixup patches RPATH, so we also set LD_LIBRARY_PATH during install.
        comodoro = comodoro-flake.packages.${final.system}.default.overrideAttrs (old: let
          libPath = final.lib.makeLibraryPath [ final.dbus ];
        in {
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.pkg-config final.makeWrapper ];
          buildInputs = (old.buildInputs or []) ++ [ final.dbus ];
          postInstall = ''
            export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          '' + (old.postInstall or "") + ''
            wrapProgram $out/bin/comodoro --prefix LD_LIBRARY_PATH : "${libPath}"
          '';
        });
        # AI coding agents from llm-agents.nix
        claude-code = llm-agents-flake.packages.${final.system}.claude-code;
        gemini-cli = llm-agents-flake.packages.${final.system}.gemini-cli;
        codex = llm-agents-flake.packages.${final.system}.codex;
        opencode = llm-agents-flake.packages.${final.system}.opencode;
        # Browsers from browser-previews
        google-chrome = browser-previews-flake.packages.${final.system}.google-chrome;
        # Desktop tools from flake inputs
        ghostty = ghostty-flake.packages.${final.system}.default;
        yazi = yazi-flake.packages.${final.system}.default;
        agenix = agenix-flake.packages.${final.stdenv.hostPlatform.system}.default;
        deepwork = deepwork-flake.packages.${final.system}.default;
        # DeepWork library jobs — exposed as a standalone store path so modules
        # can set DEEPWORK_ADDITIONAL_JOBS_FOLDERS without needing keystoneInputs.
        deepwork-library-jobs = final.runCommand "deepwork-library-jobs" {} ''
          cp -r ${deepwork-flake}/library/jobs $out
        '';
        chrome-devtools-mcp = final.callPackage chrome-devtools-mcp-src {};
      };
      # Top-level overrides so programs.ghostty/yazi use flake versions
      ghostty = ghostty-flake.packages.${final.system}.default;
      yazi = yazi-flake.packages.${final.system}.default;
    };

    # Export Keystone modules for use in other flakes
    nixosModules = {
      # Shared domain option (keystone.domain) — used by OS agents and server services
      domain = ./modules/domain.nix;

      # Shared service registry (keystone.services.*) — declares which host runs each service
      services = ./modules/services.nix;

      # Shared host registry (keystone.hosts) — host identity and connection metadata
      hosts = ./modules/hosts.nix;

      # Core OS module - storage, secure boot, TPM, remote unlock, users, services
      # Pass flake inputs to installer via dedicated option — NOT _module.args,
      # which would conflict with the desktop module's identical definition.
      # Only installer.nix needs keystoneInputs at the NixOS level; all other
      # consumers are in the desktop tree or inside the installer's nested eval.
      operating-system = {
        imports = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          agenix.nixosModules.default
          ./modules/domain.nix
          ./modules/services.nix
          ./modules/hosts.nix
          ./modules/os
          ./modules/installer.nix
        ];
        keystone.os.installer._keystoneInputs = keystoneInputs;
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
          ./modules/services.nix
          ./modules/server
        ];
      };

      # Binary cache client - configures nix substituters for Attic cache
      binaryCacheClient = {
        imports = [
          ./modules/domain.nix
          ./modules/binary-cache-client.nix
        ];
      };

      # ISO installer module
      isoInstaller = ./modules/iso-installer.nix;

      # SSH public key registry — single source of truth for all keys
      keys = ./modules/keys.nix;

      # Hardware key module - FIDO2/YubiKey for GPG/SSH agent
      # Imports keys.nix since rootKeys references keystone.keys
      hardwareKey = {
        imports = [
          ./modules/keys.nix
          ./modules/os/hardware-key.nix
        ];
      };

      # Headscale DNS import — consume server DNS records on headscale host
      headscale-dns = ./modules/server/headscale/dns-import.nix;
    };

    # Export home-manager modules (homeModules is the standard flake output name)
    homeModules = {
      desktopHyprland = ./home-manager/modules/desktop/hyprland;
      # Keystone-specific home-manager modules
      terminal = {
        imports = [
          keystoneInputs.nix-index-database.homeModules.nix-index
          ./modules/terminal/default.nix
        ];
        _module.args.keystoneInputs = keystoneInputs;
      };
      desktop = {
        imports = [
          keystoneInputs.walker.homeManagerModules.default
          ./modules/desktop/home/default.nix
        ];
        _module.args.keystoneInputs = keystoneInputs;
      };
      notes = ./modules/notes/default.nix;
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
        inherit pkgs lib nixpkgs agenix;
        self = self;
      };
      template-evaluation = import ./tests/module/template-evaluation.nix {
        inherit pkgs lib nixpkgs;
        self = self;
      };
    };

    # Packages exported for consumption
    # Note: Integration/VM tests are in ./tests/flake.nix (separate flake to avoid IFD issues)
    packages.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      iso = self.lib.mkInstallerIso { inherit nixpkgs; };
      zesh = pkgs.callPackage ./packages/zesh {};
      agent-coding-agent = pkgs.callPackage ./packages/agent-coding-agent {};
      agent-mail = pkgs.callPackage ./packages/agent-mail {
        himalaya = himalaya.packages.x86_64-linux.default;
      };
      fetch-email-source = pkgs.callPackage ./packages/fetch-email-source {
        himalaya = himalaya.packages.x86_64-linux.default;
      };
      fetch-forgejo-sources = pkgs.callPackage ./packages/fetch-forgejo-sources {};
      fetch-github-sources = pkgs.callPackage ./packages/fetch-github-sources {};
      repo-sync = pkgs.callPackage ./packages/repo-sync {};
      podman-agent = pkgs.callPackage ./packages/podman-agent {};
      ks = pkgs.callPackage ./packages/ks {};
      keystone-tui = pkgs.callPackage ./packages/keystone-tui {};
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

        packages = with pkgs; [
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
          gettext
          bash
          deepwork.packages.${pkgs.system}.default
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
          echo "Rust packages:  packages/keystone-ha/, packages/keystone-tui/"
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
