{
  config,
  pkgs,
  lib,
  ...
}: {
  # Minimal Keystone configuration for Hyprland desktop testing
  # Uses nixos-rebuild build-vm for fast iteration without encryption/secure boot
  #
  # Build with: nixos-rebuild build-vm --flake .#build-vm-desktop
  # Run with: ./result/bin/run-build-vm-desktop-vm
  #
  # The VM:
  # - Mounts host Nix store via 9P (read-only)
  # - Creates persistent qcow2 disk at ./build-vm-desktop.qcow2
  # - Much faster than full deployment for testing desktop configs

  # NixOS state version
  system.stateVersion = "25.05";

  # System identity
  networking.hostName = "keystone-buildvm-desktop";

  # Simple boot configuration for VM
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Root filesystem (required for NixOS)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Import individual Keystone client modules WITHOUT disko/secure boot
  # We import these directly to avoid the disko dependency in the main client module
  imports = [
    ../../modules/client/desktop/hyprland.nix
    ../../modules/client/desktop/audio.nix
    ../../modules/client/desktop/greetd.nix
    ../../modules/client/desktop/packages.nix
    ../../modules/client/services/networking.nix
    ../../modules/client/services/system.nix
    ../../modules/client/home
  ];

  # Enable Keystone desktop components
  keystone.client = {
    # Desktop components
    desktop = {
      hyprland.enable = true;
      greetd.enable = true;
      audio.enable = true;
      packages.enable = true;
    };

    # Network and system services
    services = {
      networking.enable = true;
      system.enable = true;
    };

    # Home-manager configuration
    home = {
      enable = true;
      omarchy.enable = true;
    };
  };

  # Enable SSH for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Basic networking with DHCP
  networking.useDHCP = lib.mkDefault true;

  # Enable serial console for VM
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  # Enable mutable users for easy testing
  users.mutableUsers = true;

  # Test user with desktop environment
  users.users.testuser = {
    isNormalUser = true;
    description = "Hyprland Test User";
    initialPassword = "testpass"; # Test only - insecure
    extraGroups = ["wheel" "networkmanager" "video" "audio"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVcGK+pUZOTUA7MLoD5vYK/kaPF6TNNyoDmwNl2 ncrmro@ncrmro-laptop-fw7k"
    ];
  };

  # Root password for easy access
  users.users.root.initialPassword = "root";

  # Allow sudo without password (testing only)
  security.sudo.wheelNeedsPassword = false;

  # Nix settings
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = ["root" "testuser"];
  };

  # Configure home-manager for test user
  home-manager.users.testuser = {
    home.stateVersion = "25.05";

    # Enable desktop environment modules
    programs.desktop.hyprland = {
      enable = true;

      # All components enabled by default
      components = {
        waybar = true;
        mako = true;
        hyprpaper = true;
        hyprlock = true;
        hypridle = true;
      };
    };

    # Enable terminal dev environment
    programs.terminal-dev-environment = {
      enable = true;

      tools = {
        git = true;
        editor = true;
        shell = true;
        multiplexer = true;
        terminal = true;
      };
    };

    # Git configuration
    programs.git = {
      userName = "Hyprland Test User";
      userEmail = "testuser@keystone-buildvm-desktop";
    };
  };
}
