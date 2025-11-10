{
  config,
  pkgs,
  lib,
  ...
}: {
  # Confined VM for sandboxed development work
  # Designed for AI assistants like Claude to work in isolated environments
  #
  # Build with: nixos-rebuild build-vm --flake .#confined-dev
  # Run with: ./bin/confined-vm [workspace-path]

  system.stateVersion = "25.05";

  # System identity
  networking.hostName = "keystone-confined-dev";

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Root filesystem (required for NixOS)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Workspace mount point (configured at runtime via 9P)
  fileSystems."/mnt/workspace" = {
    device = "workspace";
    fsType = "9p";
    options = [
      "trans=virtio"
      "version=9p2000.L"
      "msize=104857600" # 100MB msize for better performance
      "cache=loose" # Better performance for development
      "rw"
    ];
    # Don't fail boot if workspace not mounted (might not be configured)
    neededForBoot = false;
  };

  # NETWORK ISOLATION: Completely disable networking
  networking.interfaces = lib.mkForce {};
  networking.useDHCP = lib.mkForce false;
  networking.dhcpcd.enable = lib.mkForce false;
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = lib.mkForce false;

  # Firewall: deny all (defense in depth)
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };

  # VM-specific configuration for build-vm
  virtualisation.vmVariant = {
    # No network device at all (most secure)
    virtualisation.qemu.networkingOptions = [];

    # Generous resources for development
    virtualisation.memorySize = 4096; # 4GB RAM
    virtualisation.cores = 4; # 4 CPU cores
    virtualisation.diskSize = 20000; # 20GB disk
  };

  # Enable serial console for debugging
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  # Enable mutable users for easy testing
  users.mutableUsers = true;

  # Development user
  users.users.dev = {
    isNormalUser = true;
    description = "Confined Development User";
    initialPassword = "dev";
    extraGroups = ["wheel"];
    shell = pkgs.zsh;
  };

  # Root password for emergency access
  users.users.root.initialPassword = "root";

  # Allow sudo without password (testing environment)
  security.sudo.wheelNeedsPassword = false;

  # Nix settings
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = ["root" "dev"];
    # Disable network access for nix (defense in depth)
    allowed-uris = lib.mkForce [];
    # Build settings
    cores = 4;
    max-jobs = 2;
  };

  # Complete development environment
  environment.systemPackages = with pkgs; [
    # Editors
    vim
    neovim
    helix

    # Version control
    git
    git-lfs

    # Core utilities
    curl
    wget
    htop
    btop
    tree
    file
    which
    gnused
    gnugrep
    coreutils

    # Terminal multiplexers
    tmux
    zellij

    # Build tools
    gnumake
    gcc
    clang
    cmake
    pkg-config

    # Language toolchains
    rustc
    cargo
    rust-analyzer
    clippy
    rustfmt
    go
    gopls
    nodejs_22
    python3
    python3Packages.pip

    # Nix tools
    nix-tree
    nix-diff
    nixfmt-rfc-style
    nixos-rebuild

    # Development utilities
    ripgrep
    fd
    bat
    eza
    zoxide
    fzf
    jq
    yq

    # Debugging tools
    strace
    ltrace
    gdb
    valgrind
  ];

  # ZSH configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    shellInit = ''
      # Welcome message
      echo "Confined Development Environment"
      echo "Workspace: /mnt/workspace"
      echo "Network: DISABLED"
      echo ""
    '';
  };

  # Git configuration
  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      safe.directory = "/mnt/workspace";
    };
  };

  # Configure home-manager
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    # Import terminal dev environment if available
    sharedModules = [
      ../../home-manager/modules/terminal-dev-environment
    ];
  };

  # Configure home-manager for dev user
  home-manager.users.dev = {
    home.stateVersion = "25.05";

    # Enable terminal dev environment
    programs.terminal-dev-environment = {
      enable = true;

      tools = {
        git = true;
        editor = true;
        shell = true;
        multiplexer = true;
        terminal = false; # No GUI in confined VM
      };
    };

    # Git configuration
    programs.git = {
      userName = "Confined Dev";
      userEmail = "dev@confined-vm";
    };

    # ZSH customization
    programs.zsh = {
      enable = true;
      shellAliases = {
        ws = "cd /mnt/workspace";
        ll = "eza -la";
        lt = "eza -la --tree";
      };

      initExtra = ''
        # Environment variables
        export WORKSPACE=/mnt/workspace
        export EDITOR=hx

        # Auto-cd to workspace on login
        if [ -d "$WORKSPACE" ] && [ "$PWD" = "$HOME" ]; then
          cd "$WORKSPACE"
        fi

        # Show network status
        echo "Network isolation: $(ip link show | grep -c '^[0-9]') interfaces (lo only)"
      '';
    };

    # Helix editor configuration
    programs.helix = {
      enable = true;
      settings = {
        theme = "base16_transparent";
        editor = {
          line-number = "relative";
          mouse = false;
        };
      };
    };
  };
}
