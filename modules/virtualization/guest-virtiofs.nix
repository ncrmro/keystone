# Guest configuration for virtiofs filesystem sharing
#
# This module configures a NixOS guest to mount a virtiofs share from the host
# using OverlayFS to provide a writable /nix/store backed by the read-only host share.
#
# Usage:
#   In your VM configuration.nix:
#
#   imports = [ ./modules/virtualization/guest-virtiofs.nix ];
#
#   keystone.virtualization.guest.virtiofs = {
#     enable = true;
#     shareName = "nix-store-share";  # Must match libvirt XML <target dir>
#   };
#
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.virtualization.guest.virtiofs;
in
{
  options.keystone.virtualization.guest.virtiofs = {
    enable = mkEnableOption "virtiofs filesystem sharing from host";

    shareName = mkOption {
      type = types.str;
      default = "nix-store-share";
      description = "Name of the virtiofs share (must match libvirt XML target dir)";
    };

    mountPoint = mkOption {
      type = types.str;
      default = "/nix/store";
      description = "Where to mount the overlayfs";
    };

    roStoreMount = mkOption {
      type = types.str;
      default = "/sysroot/nix/.ro-store";
      description = "Mount point for read-only host share";
    };

    rwStoreMount = mkOption {
      type = types.str;
      default = "/sysroot/nix/.rw-store";
      description = "Mount point for writable layer (tmpfs)";
    };

    persistentRwStore = mkOption {
      type = types.bool;
      default = false;
      description = "Use persistent disk storage instead of tmpfs for writable layer";
    };
  };

  config = mkIf cfg.enable {
    # Ensure required kernel modules are available at boot
    boot.initrd.availableKernelModules = [
      "virtiofs"
      "overlay"
    ];

    # Define the overlay mount for /nix/store
    fileSystems."${cfg.mountPoint}" = {
      device = "overlay";
      fsType = "overlay";
      options = [
        "lowerdir=${cfg.roStoreMount}"
        "upperdir=${cfg.rwStoreMount}/upper"
        "workdir=${cfg.rwStoreMount}/work"
      ];
      depends = [
        cfg.roStoreMount
        cfg.rwStoreMount
      ];
    };

    # Mount the read-only host share via virtiofs
    fileSystems."${cfg.roStoreMount}" = {
      device = cfg.shareName;
      fsType = "virtiofs";
      options = [ "ro" ];
      neededForBoot = true;
    };

    # Mount the writable upper layer
    fileSystems."${cfg.rwStoreMount}" =
      if cfg.persistentRwStore then
        {
          # Use a persistent directory (requires pre-existing path)
          device = "none";
          fsType = "none";
          options = [ "bind" ];
          neededForBoot = true;
        }
      else
        {
          # Use tmpfs (RAM disk) - default for testing
          device = "tmpfs";
          fsType = "tmpfs";
          options = [ "mode=0755" ];
          neededForBoot = true;
        };
  };
}
