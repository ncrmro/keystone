# Keystone OS Mac - Storage Module
#
# Handles disk partitioning and encryption for Apple Silicon Macs.
# Uses ext4 with LUKS encryption (no ZFS support yet).
# Manual password entry required (no TPM auto-unlock).
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  osCfg = config.keystone.os;
  cfg = osCfg.storage;

  # Helper to check if swap is enabled
  enableSwap = cfg.swap.size != "0" && cfg.swap.size != "";

  # Helper to get first device
  firstDevice =
    if cfg.devices != []
    then elemAt cfg.devices 0
    else "/dev/null";
in {
  config = mkIf osCfg.enable {
    assertions = [
      {
        assertion = cfg.type != "zfs";
        message = "Mac module does not support ZFS. Use type = \"ext4\" instead.";
      }
      {
        assertion = cfg.mode == "single";
        message = "Mac module only supports single-disk mode (no RAID).";
      }
      {
        assertion = length cfg.devices == 1;
        message = "Mac module requires exactly one device";
      }
    ];

    # Disko configuration for ext4 with LUKS
    disko.devices = {
      disk = {
        main = {
          type = "disk";
          device = firstDevice;
          content = {
            type = "gpt";
            partitions = {
              # EFI System Partition
              ESP = {
                type = "EF00";
                size = cfg.esp.size;
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = ["fmask=0077" "dmask=0077"];
                };
              };

              # Swap partition (optional)
              swap = mkIf enableSwap {
                size = cfg.swap.size;
                content = {
                  type = "swap";
                  randomEncryption = true;
                };
              };

              # Root partition with LUKS encryption
              root = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypted";
                  # LUKS2 with Argon2id for better security
                  settings = {
                    allowDiscards = true;
                  };
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/";
                  };
                };
              };
            };
          };
        };
      };
    };

    # LUKS device configuration for initrd
    boot.initrd.luks.devices = {
      crypted = {
        device = "/dev/disk/by-partlabel/disk-main-root";
        preLVM = true;
        # Allow discards for SSD performance
        allowDiscards = true;
      };
    };

    # SystemD initrd for better boot experience
    boot.initrd.systemd.enable = true;
  };
}
