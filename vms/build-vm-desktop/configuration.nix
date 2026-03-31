{
  config,
  pkgs,
  lib,
  keystone,
  ...
}:
let
  vmScreenshot = pkgs.writeShellScriptBin "keystone-vm-screenshot" ''
    set -euo pipefail

    output_path="''${1:-$HOME/Pictures/vm-screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png}"

    if [[ -z "''${XDG_RUNTIME_DIR:-}" ]]; then
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    fi

    if [[ -z "''${WAYLAND_DISPLAY:-}" ]]; then
      for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [[ -S "$socket" ]]; then
          export WAYLAND_DISPLAY="$(basename "$socket")"
          break
        fi
      done
    fi

    if [[ -z "''${WAYLAND_DISPLAY:-}" ]]; then
      echo "No Wayland socket found in $XDG_RUNTIME_DIR" >&2
      exit 1
    fi

    mkdir -p "$(dirname "$output_path")"
    ${pkgs.grim}/bin/grim "$output_path"
    printf '%s\n' "$output_path"
  '';
in
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

  # System identity
  networking.hostName = "keystone-buildvm-desktop";

  # Simple boot configuration for VM
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  nixpkgs.overlays = [ keystone.overlays.default ];

  # Root filesystem (required for NixOS)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Import Keystone desktop module WITHOUT disko/secure boot
  imports = [
    ../../modules/desktop/nixos.nix
  ];

  # Enable Keystone desktop components
  keystone.desktop = {
    enable = true;
    user = "testuser";

    hyprland.enable = true;
    greetd.enable = true;
    audio.enable = true;
    bluetooth.enable = true;
    networking.enable = true;
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

  # VM-specific configuration for build-vm
  virtualisation.vmVariant = {
    virtualisation.forwardPorts = [
      {
        from = "host";
        host.port = 2223;
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
  environment.systemPackages = with pkgs; [
    tmux
    util-linux
    jq
    vmScreenshot
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

  # Configure home-manager
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = [
      keystone.homeModules.desktop
    ];
  };

  # Configure home-manager for test user
  home-manager.users.testuser = {
    home.stateVersion = "25.05";

    keystone = {
      desktop.enable = true;
      notes = {
        enable = true;
        repo = "git@example.com:testuser/notes.git";
      };
      terminal.git = {
        userName = "Hyprland Test User";
        userEmail = "testuser@keystone-buildvm-desktop";
      };
      terminal.ai.enable = false;
      terminal.sandbox.enable = false;
    };

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
