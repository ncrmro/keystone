{
  config,
  pkgs,
  lib,
  ...
}: {
  # Minimal Keystone client configuration for Hyprland desktop testing
  # This configuration enables testing of the Hyprland desktop environment

  # NixOS state version - do not change after initial deployment
  system.stateVersion = "25.05";

  # System identity
  networking.hostName = "keystone-hyprland-test";
  # Required for ZFS - unique 8-character hex string
  networking.hostId = "cafebabe";

  # Boot loader configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable Keystone client modules
  keystone = {
    # Disk configuration with ZFS and encryption
    disko = {
      enable = true;
      # Disk device for VM testing
      device = "/dev/vda";
    };

    # Enable client configuration with desktop
    client = {
      enable = true;

      # Desktop components (all enabled by default)
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
  };

  # Serial console support for VM testing
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  # Enable serial console in systemd
  boot.initrd.systemd.emergencyAccess = true;

  # Ensure virtio modules are available in initrd
  boot.initrd.availableKernelModules = ["virtio_blk" "virtio_pci" "virtio_net"];

  # Test user with desktop environment
  keystone.users = {
    testuser = {
      uid = 1001;
      fullName = "Hyprland Test User";
      initialPassword = "testpass"; # Test only - insecure
      zfsProperties = {
        quota = "50G";
        compression = "lz4";
      };
    };
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
      userEmail = "testuser@keystone-hyprland-test";
    };
  };

  # Allow testuser to receive nix store paths over SSH
  nix.settings.trusted-users = ["root" "testuser"];

  # SSH access for testing
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVcGK+pUZOTUA7MLoD5vYK/kaPF6TNNyoDmwNl2 ncrmro@ncrmro-laptop-fw7k"
  ];
}
