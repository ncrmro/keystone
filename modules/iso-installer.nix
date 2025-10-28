# ISO installer configuration for nixos-anywhere compatibility
{
  config,
  pkgs,
  lib,
  sshKeys ? [],
  ...
}: {
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

  # Enable networking
  networking = {
    dhcpcd.enable = true;
    wireless.enable = false; # We'll use dhcp for simplicity
    useDHCP = true;
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
  ];

  # Enable the serial console for remote debugging
  boot.kernelParams = ["console=ttyS0,115200"];

  # Ensure SSH starts on boot
  systemd.services.sshd.wantedBy = lib.mkForce ["multi-user.target"];

  # Automatically configure network on boot
  systemd.services.dhcpcd.wantedBy = ["multi-user.target"];

  # Note: kernel is set in flake.nix to override minimal CD default

  # Enable ZFS for nixos-anywhere deployments
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  # Ensure ZFS kernel modules are loaded and available
  boot.kernelModules = [ "zfs" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.zfs_2_3 ];

  # Critical: Add ZFS packages to system for nixos-anywhere
  services.udev.packages = [ config.boot.kernelPackages.zfs_2_3 ];
  systemd.packages = [ config.boot.kernelPackages.zfs_2_3 ];

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
