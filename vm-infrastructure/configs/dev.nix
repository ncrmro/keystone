# Development Workstation Configuration
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../modules/client
    ../modules/disko-single-disk-root
  ];

  # Enable Keystone client modules
  keystone.client = {
    enable = true;
    desktop = {
      hyprland.enable = true;
      audio.enable = true;
      packages.enable = true;
    };
    services = {
      networking.enable = true;
      system.enable = true;
    };
  };

  # Disko configuration for encrypted root
  keystone.disko = {
    enable = true;
    device = "/dev/disk/by-id/virtio-os-disk-dev";
    enableEncryptedSwap = true;
  };

  # Network configuration
  networking = {
    hostName = "keystone-dev";
    hostId = "d4e5f6a7"; # Random 8-char hex string

    # Use DHCP (will get IP from keystone-net)
    useDHCP = false;
    interfaces.enp1s0.useDHCP = true;
  };

  # Developer user configuration
  users.users.dev = {
    isNormalUser = true;
    description = "Developer";
    extraGroups = ["wheel" "networkmanager" "audio" "video" "docker" "libvirtd"];
    shell = pkgs.zsh;

    # Set initial password (change on first login)
    initialPassword = "developer";
  };

  # Enable programs
  programs = {
    zsh.enable = true;
    firefox.enable = true;
    git.enable = true;
    neovim = {
      enable = true;
      defaultEditor = true;
    };
  };

  # Development environment
  environment.systemPackages = with pkgs; [
    # Development tools
    git
    gh # GitHub CLI
    neovim
    vscode

    # Languages and runtimes
    nodejs_20
    python3
    go
    rustc
    cargo

    # Container and virtualization
    docker
    docker-compose
    podman
    qemu
    libvirt
    virt-manager

    # Database tools
    postgresql
    sqlite
    redis

    # System tools
    htop
    btop
    ripgrep
    fd
    jq
    yq
    tree
    wget
    curl

    # Network tools
    nmap
    wireshark
    tcpdump

    # Build tools
    gnumake
    cmake
    gcc
    clang

    # Terminal and shell
    kitty
    tmux
    zsh
    oh-my-zsh

    # Text processing
    bat
    eza
    delta

    # Media and graphics
    mpv
    imv
    gimp
    inkscape

    # Productivity
    libreoffice
    obsidian

    # Communication
    discord
    slack
  ];

  # Enable development services
  virtualisation = {
    docker.enable = true;
    libvirtd.enable = true;
    podman.enable = true;
  };

  # Enable databases
  services = {
    postgresql = {
      enable = true;
      ensureDatabases = ["dev"];
      ensureUsers = [
        {
          name = "dev";
          ensureDBOwnership = true;
        }
      ];
    };

    redis.servers."" = {
      enable = true;
      port = 6379;
    };
  };

  # Development environment variables
  environment.variables = {
    EDITOR = "nvim";
    BROWSER = "firefox";
  };

  # Enable Nix flakes and command
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # System configuration
  system.stateVersion = "25.05";
}
