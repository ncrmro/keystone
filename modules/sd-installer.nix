# aarch64 SD-image installer for Raspberry Pi
#
# Parallel to iso-installer.nix but builds a flashable .img.zst via the
# upstream sd-image-aarch64-installer profile. Intended to be flashed to an
# SD card, booted on a Pi, and used as the install/rescue environment for
# deploying keystone Pi hosts (nixos-anywhere or manual disko + nixos-install).
#
# The installer itself boots via extlinux (the stock NixOS aarch64 sd-image
# bootloader). The *installed* system uses pftf/RPi4 UEFI + systemd-boot per
# keystone.os.storage.platform = "pi"; nothing on this installer image needs
# to change when the target system's boot stack changes.
#
# Usage (from flake.nix via lib.mkInstallerSdImage):
#   keystone.piInstaller.sshKeys = [ "ssh-ed25519 AAAAC3..." ];
{
  config,
  pkgs,
  lib,
  ...
}:
let
  installerCfg = config.keystone.piInstaller;
in
{
  options.keystone.piInstaller = {
    sshKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys for root access on the Pi SD installer.";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0";
      description = "Installer version embedded in the image basename.";
    };
  };

  config = {
    # The live installer builds the target system before first boot, so it
    # needs the shared Keystone cache.
    nix.settings.substituters = lib.mkBefore [ "https://ks-systems.cachix.org" ];
    nix.settings.trusted-public-keys = lib.mkBefore [
      "ks-systems.cachix.org-1:Abbd38auzcLIfJUtX7kSD6zdGUU4v831Sb2KfajR5Mo="
    ];

    # Pi SD cards are slow + usually small memory; zram swap gives nixos-install
    # some headroom when the cache is cold.
    zramSwap.enable = true;

    # Key-based root SSH for remote install (nixos-anywhere).
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = lib.mkForce "yes";
        PasswordAuthentication = false;
        PubkeyAuthentication = true;
      };
      extraConfig = "UseDNS no";
    };
    users.users.root.openssh.authorizedKeys.keys = installerCfg.sshKeys;
    systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

    # Stock DHCP — no NetworkManager overhead on the installer.
    networking.wireless.enable = lib.mkForce false;
    networking.useDHCP = lib.mkForce true;

    # Tools needed for installation + recovery.
    environment.systemPackages = with pkgs; [
      git
      curl
      wget
      htop
      lsof
      rsync
      jq
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
      tpm2-tools
      sbctl
      # ZFS utilities (installed Pi hosts use ZFS root).
      config.boot.zfs.package
    ];

    # ZFS support in the installer so disko/nixos-anywhere can lay down pools.
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;
    boot.kernelModules = [ "zfs" ];

    # ZFS hostId: the sd-image-installer profile already sets one, don't clobber it.

    # Trim docs to keep the image small.
    documentation.enable = false;
    documentation.nixos.enable = false;

    # sd-image output filename.
    image.baseName = lib.mkForce "keystone-pi-installer-${installerCfg.version}";

    # Pin stateVersion so rebuilds don't silently drift.
    system.stateVersion = "25.05";

    # Expand rootfs on first boot so the installer has working space beyond
    # the baked-in partition size.
    sdImage.expandOnBoot = true;

    # Keep a copy of the keystone modules on the installer for offline reference.
    environment.etc."keystone-modules".source = ../modules;

    # The aarch64 sd-image-installer profile sets the system to aarch64-linux
    # and uses generic-extlinux-compatible bootloader — nothing else to wire.
  };
}
