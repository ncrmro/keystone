# Hardware configuration for MacBook Air (Apple Silicon / Asahi Linux)
#
# This file is specific to the target MacBook. The disk identifiers below
# were copied from the MacBook's actual /etc/nixos/hardware-configuration.nix.
#
# If deploying to a different MacBook, update the fileSystems entries
# to match that machine's disk layout.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [];

  # MacBook Air disk configuration
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partuuid/456551a3-4160-44c0-8763-b5dd56969569";
    fsType = "vfat";
  };

  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
