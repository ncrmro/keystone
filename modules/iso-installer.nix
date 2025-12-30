# ISO installer configuration (x86_64 / ZFS enabled)
{
  config,
  pkgs,
  lib,
  enableTui ? true,
  ...
}: {
  imports = [./iso-base.nix];

  # Include ZFS utilities in system packages
  environment.systemPackages = [
    config.boot.kernelPackages.zfs_2_3
    pkgs.tpm2-tools
  ];

  # Add ZFS tools to the installer service path
  systemd.services.keystone-installer = lib.mkIf enableTui {
    path = [
      config.boot.kernelPackages.zfs_2_3
      pkgs.tpm2-tools
    ];
  };

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
}
