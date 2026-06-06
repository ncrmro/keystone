{
  config,
  pkgs,
  lib,
  keystone,
  ...
}:
{
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

  # Keystone packages (keystone-conventions, hyprpolkitagent wrapper, etc.)
  # live under `pkgs.keystone.*` via the overlay.
  nixpkgs.overlays = [ keystone.overlays.default ];

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

  # Enable Keystone desktop components
  keystone.desktop = {
    enable = true;
    user = "testuser";
  };

  # The desktop module reserves /etc/resolv.conf as a direct symlink (for
  # Tailscale MagicDNS) and assumes keystone.os enables systemd-resolved.
  # This VM doesn't enable keystone.os, so wire resolved here and disable
  # resolvconf to satisfy the resolv.conf-ownership assertion.
  services.resolved.enable = true;
  networking.resolvconf.enable = false;

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

  # VM-specific configuration for build-vm
  # Forward SSH port for headless access: ssh -p 2222 testuser@localhost
  virtualisation.vmVariant = {
    virtualisation.forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];
  };

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
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVcGK+pUZOTUA7MLoD5vYK/kaPF6TNNyoDmwNl2 ncrmro@ncrmro-laptop-fw7k"
    ];
  };

  # Root password for easy access
  users.users.root.initialPassword = "root";

  # Allow sudo without password (testing only)
  security.sudo.wheelNeedsPassword = false;

  # System packages
  environment.systemPackages = [
  ];

  # Nix settings
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "testuser"
    ];
  };

  # Configure home-manager for test user
  home-manager.users.testuser = {
    home.stateVersion = "25.05";

    # Git configuration
    programs.git = {
      enable = true;
      settings = {
        user.name = "Hyprland Test User";
        user.email = "testuser@keystone-buildvm-desktop";
      };
    };
  };
}
