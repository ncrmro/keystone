# Client Workstation Configuration
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
    device = "/dev/disk/by-id/virtio-os-disk-client";
    enableEncryptedSwap = true;
  };

  # Network configuration
  networking = {
    hostName = "keystone-client";
    hostId = "b2c3d4e5"; # Random 8-char hex string

    # Use DHCP (will get IP from keystone-net)
    useDHCP = false;
    interfaces.enp1s0.useDHCP = true;
  };

  # User configuration
  users.users.user = {
    isNormalUser = true;
    description = "Keystone User";
    extraGroups = ["wheel" "networkmanager" "audio" "video"];
    shell = pkgs.zsh;

    # Set initial password (change on first login)
    initialPassword = "keystone";
  };

  # Enable programs for desktop use
  programs = {
    zsh.enable = true;
    firefox.enable = true;
    git.enable = true;
  };

  # Development tools
  environment.systemPackages = with pkgs; [
    # Editors
    vscode
    vim

    # Development
    git
    docker
    docker-compose

    # System tools
    htop
    btop
    ripgrep
    fd
    jq

    # Media
    mpv
    imv

    # Communication
    discord

    # Productivity
    libreoffice

    # Terminal
    kitty
    tmux
  ];

  # Enable Docker
  virtualisation.docker.enable = true;
  users.users.user.extraGroups = ["docker"];

  # System configuration
  system.stateVersion = "25.05";
}
