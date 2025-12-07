# ISO installer configuration for nixos-anywhere compatibility
{
  config,
  pkgs,
  lib,
  sshKeys ? [],
  ...
}: 
let
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

  # Keystone installer service - auto-start the TUI
  systemd.services.keystone-installer = {
    description = "Keystone Installer TUI";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "NetworkManager.service" ];
    wants = [ "NetworkManager.service" ];
    
    serviceConfig = {
      Type = "simple";
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

  # Optimize for installation - less bloat
  documentation.enable = false;
  documentation.nixos.enable = false;

  # Set the ISO label
  isoImage.isoName = lib.mkForce "keystone-installer.iso";
  isoImage.volumeID = lib.mkForce "KEYSTONE";

  # Include the keystone modules in the ISO for reference
  environment.etc."keystone-modules".source = ../modules;
}
