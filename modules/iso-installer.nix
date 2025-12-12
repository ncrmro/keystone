# ISO installer configuration for nixos-anywhere compatibility
{
  config,
  pkgs,
  lib,
  sshKeys ? [],
  ...
}: let
  keystone-installer-ui = pkgs.callPackage ../packages/keystone-installer-ui {};
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

  # Enable networking with NetworkManager for WiFi support
  networking = {
    dhcpcd.enable = false; # Disable dhcpcd in favor of NetworkManager
    wireless.enable = false; # NetworkManager handles WiFi
    networkmanager = {
      enable = true;
      # Ensure NetworkManager starts early
      dispatcherScripts = [];
    };
    useDHCP = false; # NetworkManager handles DHCP
  };

  # Include useful tools for nixos-anywhere and debugging
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    vim
    htop
    lsof
    tcpdump
    nmap
    rsync
    # Tools needed for nixos-anywhere
    parted
    cryptsetup
    util-linux
    # ZFS utilities for nixos-anywhere deployment
    config.boot.kernelPackages.zfs_2_3
    # Secure Boot key management
    sbctl
    # Keystone installer UI
    keystone-installer-ui
    # NetworkManager CLI for WiFi management
    networkmanager
    # JSON parsing for lsblk disk detection
    jq
    # TPM2 detection for encrypted installation
    tpm2-tools
  ];

  # Enable the serial console for remote debugging
  boot.kernelParams = ["console=ttyS0,115200"];

  # Ensure SSH starts on boot
  systemd.services.sshd.wantedBy = lib.mkForce ["multi-user.target"];

  # Disable getty on tty1 so the installer can use it
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Keystone installer service - auto-start the TUI
  systemd.services.keystone-installer = {
    description = "Keystone Installer TUI";
    wantedBy = ["multi-user.target"];
    after = ["network.target" "NetworkManager.service"];
    wants = ["NetworkManager.service"];
    conflicts = ["getty@tty1.service" "autovt@tty1.service"];

    # Add required tools to PATH for the installer
    path = with pkgs; [
      networkmanager # nmcli
      iproute2 # ip
      util-linux # lsblk
      jq # JSON parsing
      tpm2-tools # TPM detection
      parted # disk partitioning
      cryptsetup # LUKS encryption
      config.boot.kernelPackages.zfs_2_3 # ZFS tools
      dosfstools # mkfs.fat
      e2fsprogs # mkfs.ext4
      nix # nix command for flake operations
      nixos-install-tools # nixos-install, nixos-generate-config, nixos-enter
      disko # disk partitioning and formatting
      git # git clone for repository installation
      shadow # chpasswd for setting user passwords
    ];

    # NOTE: Git initialization removed from installer to avoid ownership errors
    # User should run `git init` after first boot as their own user

    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStart = "${keystone-installer-ui}/bin/keystone-installer";
      Restart = "on-failure";
      RestartSec = "5s";
      StandardInput = "tty";
      StandardOutput = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = "yes";
      TTYVHangup = "yes";
    };
  };

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

  # Enable flakes for disko and nixos-install
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Optimize for installation - less bloat
  documentation.enable = false;
  documentation.nixos.enable = false;

  # Set the ISO label
  isoImage.isoName = lib.mkForce "keystone-installer.iso";
  isoImage.volumeID = lib.mkForce "KEYSTONE";

  # Custom welcome banner
  environment.etc."issue".text = lib.mkForce ''

    \e[1;35m╔═══════════════════════════════════════════════════════════════╗
    ║           \e[1;36mKeystone Installer\e[1;35m - NixOS ${config.system.nixos.release}            ║
    ╚═══════════════════════════════════════════════════════════════╝\e[0m

    The installer TUI is running on \e[1;33mtty1\e[0m.
    Press \e[1;32mAlt+F1\e[0m to switch to the installer.

    For manual access:
      - SSH: \e[1;36mssh root@<this-ip>\e[0m (key-based auth only)
      - Root shell: This terminal

  '';

  # Include the keystone modules in the ISO for reference
  environment.etc."keystone-modules".source = ../modules;
}
