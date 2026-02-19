# ISO installer configuration with TUI installer
{
  config,
  pkgs,
  lib,
  sshKeys ? [],
  ...
}: let
  keystone-tui = pkgs.callPackage ../packages/keystone-tui {};
in {
  # Enable SSH daemon for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
    };
    # Start SSH as early as possible
    extraConfig = ''
      UseDNS no
    '';
  };

  # Configure root user with SSH keys
  users.users.root = {
    openssh.authorizedKeys.keys = sshKeys;
  };

  # Enable networking via NetworkManager (for TUI installer network detection)
  networking = {
    wireless.enable = false;
  };

  # Include TUI installer and tools for installation
  environment.systemPackages = with pkgs; [
    keystone-tui
    git
    curl
    wget
    vim
    htop
    lsof
    rsync
    jq
    # Tools needed for installation
    parted
    cryptsetup
    util-linux
    dosfstools
    e2fsprogs
    nix
    nixos-install-tools
    disko
    shadow
    iproute2
    networkmanager
    tpm2-tools
    # ZFS utilities
    config.boot.kernelPackages.zfs_2_3
    # Secure Boot key management
    sbctl
  ];

  # NetworkManager for network detection (required by TUI installer)
  networking.networkmanager.enable = true;

  # Disable getty on tty1 so TUI installer can use it
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Keystone TUI installer service - auto-starts on boot
  systemd.services.keystone-installer = {
    description = "Keystone Installer TUI";
    after = ["network.target" "NetworkManager.service"];
    wants = ["NetworkManager.service"];
    wantedBy = ["multi-user.target"];
    conflicts = ["getty@tty1.service" "autovt@tty1.service"];

    path = with pkgs; [
      networkmanager
      iproute2
      util-linux
      jq
      tpm2-tools
      parted
      cryptsetup
      config.boot.kernelPackages.zfs_2_3
      dosfstools
      e2fsprogs
      nix
      nixos-install-tools
      disko
      git
      shadow
    ];

    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStart = "${keystone-tui}/bin/keystone-tui";
      Restart = "on-failure";
      RestartSec = "5s";
      StandardInput = "tty";
      StandardOutput = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = "yes";
      TTYVHangup = "yes";
    };
  };

  # Enable console on both serial (for remote) and tty1 (for TUI installer)
  boot.kernelParams = ["console=ttyS0,115200" "console=tty1"];

  # Ensure SSH starts on boot
  systemd.services.sshd.wantedBy = lib.mkForce ["multi-user.target"];

  # Note: kernel is set in flake.nix to override minimal CD default

  # Enable ZFS for nixos-anywhere deployments
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;

  # Ensure ZFS kernel modules are loaded and available
  boot.kernelModules = ["zfs"];
  boot.extraModulePackages = [config.boot.kernelPackages.zfs_2_3];

  # Critical: Add ZFS packages to system for nixos-anywhere
  services.udev.packages = [config.boot.kernelPackages.zfs_2_3];
  systemd.packages = [config.boot.kernelPackages.zfs_2_3];

  # Set required hostId for ZFS
  networking.hostId = lib.mkDefault "8425e349";

  # Enable flakes - required for installation
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Optimize for installation - less bloat
  documentation.enable = false;
  documentation.nixos.enable = false;

  # Set the ISO label
  image.fileName = lib.mkForce "keystone-installer.iso";
  isoImage.volumeID = lib.mkForce "KEYSTONE";

  # Include the keystone modules in the ISO for reference
  environment.etc."keystone-modules".source = ../modules;
}
