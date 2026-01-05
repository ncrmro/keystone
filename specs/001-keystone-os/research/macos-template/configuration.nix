# Keystone NixOS Configuration - Apple Silicon MacBook
# Remote build template: builds on OrbStack, deploys to MacBook
{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [./hardware-configuration.nix];

  # ============================================================================
  # SYSTEM IDENTITY
  # ============================================================================

  # TODO: Change to your preferred hostname
  networking.hostName = "macbook";
  system.stateVersion = "25.05";

  # ============================================================================
  # NIXPKGS CONFIGURATION
  # ============================================================================

  nixpkgs.config.allowUnfree = true;

  # WORKAROUND: Some Keystone desktop packages (gpu-screen-recorder) are x86_64 only.
  # This allows the build to proceed; unavailable packages are skipped.
  # TODO: This should be fixed in Keystone's desktop module with platform checks.
  nixpkgs.config.allowUnsupportedSystem = true;

  # ============================================================================
  # KEYSTONE DESKTOP (SYSTEM LEVEL)
  # ============================================================================

  keystone.desktop = {
    enable = true;
    user = "admin"; # TODO: Change to your username
  };

  # ============================================================================
  # APPLE SILICON HARDWARE
  # ============================================================================

  # Asahi Linux hardware support
  # NOTE: extractPeripheralFirmware = false allows pure remote builds.
  # Firmware is already installed on the MacBook from initial Asahi setup.
  # See README.md "Asahi Firmware Handling" for alternatives.
  hardware.asahi = {
    enable = true;
    extractPeripheralFirmware = false;
    setupAsahiSound = true;
  };

  # ============================================================================
  # APPLE SILICON BOOT CONFIGURATION
  # ============================================================================

  # CRITICAL: U-Boot cannot write EFI variables - this prevents bricking!
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "0";

  # ============================================================================
  # NETWORKING
  # ============================================================================

  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
  networking.wireless.iwd.enable = true;

  # ============================================================================
  # USERS
  # ============================================================================

  users.users.admin = {
    isNormalUser = true;
    description = "System Administrator"; # TODO: Change to your name
    extraGroups = ["wheel" "networkmanager" "video" "audio"];
    initialPassword = "changeme"; # TODO: Change after first login!
    openssh.authorizedKeys.keys = [
      # TODO: Add your SSH public key here for remote deployment
      # "ssh-ed25519 AAAAC3... your-key-comment"
    ];
  };

  # ============================================================================
  # HOME-MANAGER - USER DESKTOP CONFIGURATION
  # ============================================================================

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  # Required for XDG portal integration with home-manager
  environment.pathsToLink = ["/share/applications" "/share/xdg-desktop-portal"];

  home-manager.users.admin = {pkgs, ...}: {
    home.stateVersion = "25.05";

    # Enable Keystone desktop (Hyprland)
    keystone.desktop = {
      enable = true;
      hyprland = {
        enable = true;
        modifierKey = "SUPER"; # Command key as modifier
        capslockAsControl = true;
        scale = 2; # HiDPI for Retina display
      };
    };

    # Enable Keystone terminal tools
    keystone.terminal = {
      enable = true;
      git = {
        userName = "Admin"; # TODO: Change to your name
        userEmail = "admin@macbook"; # TODO: Change to your email
      };
    };
  };

  # ============================================================================
  # SERVICES
  # ============================================================================

  services.openssh = {
    enable = true;
    settings = {
      # IMPORTANT: Root login required for nixos-rebuild --target-host
      PermitRootLogin = "yes";
      PasswordAuthentication = true; # Set to false after adding SSH keys
    };
  };

  # ============================================================================
  # NIX SETTINGS
  # ============================================================================

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = ["root" "@wheel"];
  };

  # ============================================================================
  # PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    tree
  ];

  # TODO: Change to your timezone
  time.timeZone = "UTC";
}
