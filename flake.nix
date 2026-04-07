{
  description = "Self-sovereign NixOS infrastructure platform";

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
    # AI coding agents (claude-code, gemini-cli, codex, opencode).
    # Keystone keeps this input at nightly-latest. Contributors should follow
    # keystone's pin (llm-agents.follows = "keystone/llm-agents") so that
    # relocking keystone automatically bumps agent versions.
    # Consumers who prefer a stable pin can declare their own llm-agents input
    # and override keystone's with: keystone.inputs.llm-agents.follows = "llm-agents".
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
    yazi = {
      url = "github:sxyazi/yazi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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

    deepwork = {
      url = "github:Unsupervisedcom/deepwork";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # MCP servers
    grafana-mcp-src = {
      url = "github:grafana/mcp-grafana";
      flake = false;
    };

    lfs-s3-src = {
      url = "github:nicolas-graves/lfs-s3/0.2.1";
      flake = false;
    };

    # Rust build tooling — splits dependency builds for fast incremental rebuilds
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
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
      grafana-mcp-src,
      lfs-s3-src,
      ...
    }:
    let
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
        self = self;
        deepwork = deepwork;
        keystoneOverlay = self.overlays.default;
      };

      # Shared ISO installer module list — used by both nixosConfigurations.keystoneIso
      # and lib.mkInstallerIso to avoid maintaining parallel module wiring.
      installerModules = system: [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        ./modules/iso-installer.nix
        {
          # Force kernel 6.12 — must be set here to override minimal CD default
          boot.kernelPackages = nixpkgs.lib.mkForce nixpkgs.legacyPackages.${system}.linuxPackages_6_12;
          # Apply keystone overlay so crane-built packages (e.g. keystone-tui) resolve
          nixpkgs.overlays = [ self.overlays.default ];
        }
      ];

      templateLib = import ./lib/templates.nix {
        inherit
          self
          nixpkgs
          home-manager
          ;
        lib = nixpkgs.lib;
      };
    in
    {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;

      lib = templateLib // {
        # Build an installer ISO with the given SSH keys baked in.
        # Consumer flakes call this instead of duplicating the module wiring.
        mkInstallerIso =
          {
            nixpkgs,
            sshKeys ? [ ],
            system ? "x86_64-linux",
          }:
          (nixpkgs.lib.nixosSystem {
            inherit system;
            modules = installerModules system ++ [
              {
                keystone.installer.sshKeys = sshKeys;
              }
            ];
          }).config.system.build.isoImage;
      };

      # ISO configuration without SSH keys (use lib.mkInstallerIso for keys)
      # Note: Test/dev configurations are in ./tests/flake.nix
      nixosConfigurations = {
        keystoneIso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = installerModules "x86_64-linux";
        };
      };

      # Overlay that provides keystone packages
      overlays.default = import ./overlays/default.nix {
        inherit
          self
          crane
          himalaya
          calendula
          cardamum
          comodoro
          llm-agents
          browser-previews
          ghostty
          yazi
          agenix
          deepwork
          grafana-mcp-src
          lfs-s3-src
          ;
      };

      # Export Keystone modules for use in other flakes
      nixosModules = {
        # Shared domain option (keystone.domain) — used by OS agents and server services
        domain = ./modules/domain.nix;

        # Shared service registry (keystone.services.*) — declares which host runs each service
        services = ./modules/services.nix;

        # Shared host registry (keystone.hosts) — host identity and connection metadata
        hosts = ./modules/hosts.nix;

        # Experimental feature flag (keystone.experimental)
        experimental = ./modules/shared/experimental.nix;

        # Managed repo registry + development mode toggle (keystone.repos, keystone.development)
        repos = ./modules/shared/repos.nix;

        # Core OS module - storage, secure boot, TPM, remote unlock, users, services
        # Pass flake inputs to installer via dedicated option — NOT _module.args,
        # which would conflict with the desktop module's identical definition.
        # Only installer.nix needs keystoneInputs at the NixOS level; all other
        # consumers are in the desktop tree or inside the installer's nested eval.
        operating-system = {
          imports = [
            home-manager.nixosModules.home-manager
            disko.nixosModules.disko
            lanzaboote.nixosModules.lanzaboote
            agenix.nixosModules.default
            ./modules/domain.nix
            ./modules/services.nix
            ./modules/hosts.nix
            ./modules/shared/experimental.nix
            ./modules/shared/repos.nix
            ./modules/os
            ./modules/installer.nix
          ];
          keystone.os.installer._keystoneInputs = keystoneInputs;
          # Auto-populate keystone.repos from flake inputs with discoverable URLs.
          # Only pass inputs that represent managed repos — not all upstream dependencies.
          keystone._repoInputs = {
            keystone = self;
            inherit deepwork;
          };
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            sharedModules = [
              self.homeModules.terminal
              self.homeModules.notes
            ];
          };
        };

        # Desktop module - Hyprland, audio, greetd (no disko/encryption dependencies)
        desktop = {
          imports = [
            keystoneInputs.nix-flatpak.nixosModules.nix-flatpak
            ./modules/desktop/nixos.nix
          ];
          _module.args.keystoneInputs = keystoneInputs;
          home-manager.sharedModules = [
            self.homeModules.desktop
          ];
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
        headscale-acl = ./modules/server/headscale/acl-import.nix;
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
          # keystoneInputs is provided by homeModules.terminal (loaded as a
          # sharedModule by nixosModules.operating-system). Do not redeclare
          # _module.args here to avoid "defined multiple times" when both
          # terminal and desktop are active.
        };
        notes = ./modules/notes/default.nix;
      };

      # Flake checks — run via `nix flake check` and CI
      checks.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          lib = pkgs.lib;
        in
        {
          # Module evaluation tests (fast, no VM boot required)
          os-evaluation = import ./tests/module/os-evaluation.nix {
            inherit pkgs lib;
            self = self;
          };
          agent-evaluation = import ./tests/module/agent-evaluation.nix {
            inherit
              pkgs
              lib
              nixpkgs
              agenix
              home-manager
              ;
            self = self;
          };
          template-evaluation = import ./tests/module/template-evaluation.nix {
            inherit
              pkgs
              lib
              nixpkgs
              home-manager
              ;
            self = self;
          };
          server-evaluation = import ./tests/module/server-evaluation.nix {
            inherit pkgs lib nixpkgs;
            self = self;
          };
          ks-help = import ./tests/module/ks-help.nix {
            inherit pkgs;
          };
          ks-lock-sync = import ./tests/module/ks-lock-sync.nix {
            inherit pkgs;
          };
          nixfmt-check = import ./tests/module/nixfmt-check.nix {
            inherit pkgs;
          };
          shellcheck = import ./tests/module/shellcheck.nix {
            inherit pkgs;
          };
          keystone-photos = import ./tests/module/keystone-photos.nix {
            inherit pkgs lib;
          };
          projects-schema = import ./tests/module/projects-schema.nix {
            inherit pkgs lib;
          };
          pz-regression = import ./tests/module/pz-regression.nix {
            inherit pkgs lib;
          };
          pz-project-menu = import ./tests/module/pz-project-menu.nix {
            inherit pkgs lib;
          };
          pz-host-launcher-state = import ./tests/module/pz-host-launcher-state.nix {
            inherit pkgs lib;
          };
          keystone-secrets-menu = import ./tests/module/keystone-secrets-menu.nix {
            inherit pkgs lib;
          };
          keystone-update-menu = import ./tests/module/keystone-update-menu.nix {
            inherit pkgs lib;
          };
          keystone-fingerprint-menu = import ./tests/module/keystone-fingerprint-menu.nix {
            inherit pkgs lib;
          };
          hyprland-bindings-agent-conflict = import ./tests/module/hyprland-bindings-agent-conflict.nix {
            inherit pkgs;
          };
          ks-approve = import ./tests/module/ks-approve.nix {
            inherit pkgs;
          };
          agentctl-regression = import ./tests/module/agentctl-regression.nix {
            inherit pkgs;
          };
          zellij-tab-prompt = import ./tests/module/zellij-tab-prompt.nix {
            inherit
              pkgs
              lib
              self
              home-manager
              ;
          };
          agent-task-loop-hash-regression = import ./tests/module/agent-task-loop-hash-regression.nix {
            inherit pkgs lib;
          };
        };

      # Packages exported for consumption — sourced from the overlay (single source of truth)
      # Note: Integration/VM tests are in ./tests/flake.nix (separate flake to avoid IFD issues)
      packages.x86_64-linux =
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ self.overlays.default ];
          };
        in
        {
          iso = self.lib.mkInstallerIso { inherit nixpkgs; };
          inherit (pkgs.keystone)
            zesh
            agents-e2e
            agent-coding-agent
            agent-mail
            fetch-email-source
            fetch-forgejo-sources
            forgejo-cli-ex
            forgejo-project
            fetch-github-sources
            repo-sync
            podman-agent
            ks
            pz
            keystone-photos
            cfait
            zellij-tab-name
            chrome-devtools-mcp
            grafana-mcp
            lfs-s3
            deepwork-library-jobs
            keystone-deepwork-jobs
            keystone-conventions
            slidev
            ;
          keystone-tui = pkgs.callPackage ./packages/keystone-tui { };
          keystone-ha-tui-client = pkgs.callPackage ./packages/keystone-ha/tui { };
        };

      # Development shell
      devShells.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        {
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
              shellcheck
              deepwork.packages.${pkgs.stdenv.hostPlatform.system}.default
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
              echo "  ci                     - Run nix flake check"
              echo ""
              echo "Rust packages:  packages/keystone-ha/, packages/keystone-tui/"

              alias ci='nix flake check'
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
            # keystone-config

            Your Keystone config repo has been initialized.

            ## Quick Start

            Recommended scaffold command:
               nix flake new -t github:ncrmro/keystone keystone-config

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
