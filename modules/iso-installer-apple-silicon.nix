# Apple Silicon ISO installer configuration
# Minimal "vanilla" configuration with SSH support
{
  config,
  pkgs,
  lib,
  sshKeys ? [],
  ...
}: let
  # Package the install script for inclusion in the ISO
  install-apple-silicon = pkgs.writeShellScriptBin "install-apple-silicon" (builtins.readFile ../bin/install-apple-silicon);
in {
  # Enable SSH daemon
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
    };
  };

  # Root user SSH keys
  users.users.root.openssh.authorizedKeys.keys = sshKeys;

  # Networking: Enable NetworkManager with iwd backend
  # This provides the best experience for hotplugging USB Ethernet and WiFi
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";

  # Wireless support (via iwd directly is disabled in favor of NM)
  networking.wireless.iwd.enable = true;
  networking.wireless.enable = lib.mkForce false;

  # Apple Silicon specific boot settings
  # CRITICAL: U-Boot cannot write EFI variables - must be false to prevent bricking Mac
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.systemd-boot.consoleMode = lib.mkForce "0";

  # Make ISO EFI bootable
  isoImage.makeEfiBootable = true;

  # Asahi firmware settings for installer
  # Don't extract firmware in ISO - it's extracted at runtime from EFI partition
  hardware.asahi.extractPeripheralFirmware = lib.mkForce false;
  hardware.asahi.setupAsahiSound = lib.mkForce false;

  # Minimal toolset
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    parted
    gptfdisk
    nixos-install-tools
    sbctl
    # Hardware debugging tools
    usbutils
    pciutils
    ethtool
    # Networking tools
    networkmanager # Explicitly add NetworkManager package
    dhcpcd # DHCP client daemon
    # Keystone installer
    install-apple-silicon
  ];

  # Disable ZFS to reduce size and complexity (not supported on Asahi kernel easily)
  boot.supportedFilesystems = lib.mkForce ["vfat" "ext4"];
  boot.zfs.forceImportRoot = lib.mkForce false;

  # Enable flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # ISO Identity
  isoImage.volumeID = lib.mkForce "KEYSTONE-ASAHI";
}
