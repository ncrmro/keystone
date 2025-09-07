# ISO installer configuration for nixos-anywhere compatibility
{ config, pkgs, lib, sshKeys ? [], ... }:

{
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
  ];

  # Enable the serial console for remote debugging
  boot.kernelParams = [ "console=ttyS0,115200" ];
  
  # Ensure SSH starts on boot
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  # Automatically configure network on boot
  systemd.services.dhcpcd.wantedBy = [ "multi-user.target" ];

  # Set a reasonable timeout for the installation media
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Optimize for installation - less bloat
  documentation.enable = false;
  documentation.nixos.enable = false;
  
  # Enable zfs support (common for nixos-anywhere setups)
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # Set the ISO label
  isoImage.isoName = "keystone-installer.iso";
  isoImage.volumeID = "KEYSTONE";

  # Include the keystone modules in the ISO for reference
  environment.etc."keystone-modules".source = ../modules;
}