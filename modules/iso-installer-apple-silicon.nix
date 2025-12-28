# Apple Silicon ISO installer configuration
# Imports base installer and adds Asahi-specific overrides
#
# Key differences from x86_64 installer:
# - Uses Asahi kernel (provided by nixos-apple-silicon module)
# - No ZFS support (Asahi kernel doesn't include ZFS modules)
# - Uses iwd for WiFi (better WPA3-SAE support on Broadcom chips)
# - canTouchEfiVariables = false (U-Boot limitation, prevents bricking Mac)
{
  config,
  pkgs,
  lib,
  sshKeys ? [],
  enableTui ? true,
  ...
}: let
  keystone-installer-ui = pkgs.callPackage ../packages/keystone-installer-ui {};
in {
  imports = [./iso-installer.nix];

  # Apple Silicon / Asahi-specific overrides

  # CRITICAL: U-Boot cannot write EFI variables - must be false to prevent bricking Mac
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # systemd-boot console mode for U-Boot compatibility
  boot.loader.systemd-boot.consoleMode = lib.mkForce "0";

  # Make ISO EFI bootable
  isoImage.makeEfiBootable = true;

  # Asahi firmware settings for installer
  # Don't extract firmware in ISO - it's extracted at runtime from EFI partition
  hardware.asahi.extractPeripheralFirmware = lib.mkForce false;
  # Don't setup sound in installer - not needed
  hardware.asahi.setupAsahiSound = lib.mkForce false;

  # Use iwd instead of wpa_supplicant (better WPA3-SAE support on Apple Broadcom chips)
  networking.wireless.iwd.enable = true;
  networking.wireless.enable = lib.mkForce false;

  # Disable ZFS - Asahi kernel does not support ZFS modules
  boot.supportedFilesystems = lib.mkForce ["vfat" "ext4"];
  boot.zfs.forceImportRoot = lib.mkForce false;
  boot.kernelModules = lib.mkForce [];
  boot.extraModulePackages = lib.mkForce [];

  # Remove ZFS-related udev/systemd packages
  services.udev.packages = lib.mkForce [];
  systemd.packages = lib.mkForce [];

  # Override environment packages to exclude ZFS utilities
  environment.systemPackages = lib.mkForce (with pkgs; [
    keystone-installer-ui
    git
    curl
    wget
    vim
    htop
    lsof
    rsync
    jq
    # Tools needed for installation (no ZFS)
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
    # iwd for WiFi
    iwd
    # Secure Boot key management (useful for reference)
    sbctl
  ]);

  # Override TUI installer service path to exclude ZFS
  systemd.services.keystone-installer = lib.mkIf enableTui {
    path = lib.mkForce (with pkgs; [
      networkmanager
      iproute2
      util-linux
      jq
      parted
      cryptsetup
      dosfstools
      e2fsprogs
      nix
      nixos-install-tools
      disko
      git
      shadow
      iwd
    ]);
  };

  # ISO label for Apple Silicon
  isoImage.volumeID = lib.mkForce "KEYSTONE-ASAHI";
}
