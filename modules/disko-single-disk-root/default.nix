{
  lib,
  config,
  pkgs,
  utils,
  ...
}:
with lib; let
  cfg = config.keystone.disko;
in {
  options.keystone.disko = {
    enable = mkEnableOption "Keystone disko configuration";

    device = mkOption {
      type = types.str;
      example = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0W127373V";
      description = "The disk device to use for installation (by-id path recommended)";
    };

    enableEncryptedSwap = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to create an encrypted swap partition";
    };

    swapSize = mkOption {
      type = types.str;
      default = "64G";
      description = "Size of the swap partition";
    };

    espSize = mkOption {
      type = types.str;
      default = "1G";
      description = "Size of the EFI System Partition";
    };
  };

  config = mkIf cfg.enable {
    # Ensure ZFS support is enabled
    boot.supportedFilesystems = ["zfs"];

    # Boot loader configuration
    boot.initrd.systemd.emergencyAccess = lib.mkDefault false;
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Complex initrd configuration for ZFS with encrypted credstore
    boot.initrd = {
      # This would be a nightmare without systemd initrd
      systemd.enable = true;

      # Disable NixOS's systemd service that imports the pool
      systemd.services.zfs-import-rpool.enable = false;

      systemd.services.import-rpool-bare = let
        # Compute the systemd units for the devices in the pool
        devices = map (p: utils.escapeSystemdPath p + ".device") [
          cfg.device
        ];
      in {
        after = ["modprobe@zfs.service"] ++ devices;
        requires = ["modprobe@zfs.service"];

        # Devices are added to 'wants' instead of 'requires' so that a
        # degraded import may be attempted if one of them times out.
        # 'cryptsetup-pre.target' is wanted because it isn't pulled in
        # normally and we want this service to finish before
        # 'systemd-cryptsetup@.service' instances begin running.
        wants = ["cryptsetup-pre.target"] ++ devices;
        before = ["cryptsetup-pre.target"];

        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [config.boot.zfs.package];
        enableStrictShellChecks = true;
        script = let
          # Check that the FSes we're about to mount actually come from
          # our encryptionroot. If not, they may be fraudulent.
          shouldCheckFS = fs: fs.fsType == "zfs" && utils.fsNeededForBoot fs;
          checkFS = fs: ''
            encroot="$(zfs get -H -o value encryptionroot ${fs.device})"
            if [ "$encroot" != rpool/crypt ]; then
              echo ${fs.device} has invalid encryptionroot "$encroot" >&2
              exit 1
            else
              echo ${fs.device} has valid encryptionroot "$encroot" >&2
            fi
          '';
        in ''
          function cleanup() {
            exit_code=$?
            if [ "$exit_code" != 0 ]; then
              zpool export rpool
            fi
          }
          trap cleanup EXIT
          zpool import -N -d /dev/disk/by-id rpool

          # Check that the file systems we will mount have the right encryptionroot.
          ${lib.concatStringsSep "\n" (lib.map checkFS (lib.filter shouldCheckFS config.system.build.fileSystems))}
        '';
      };

      luks.devices.credstore = {
        device = "/dev/zvol/rpool/credstore";
        # 'tpm2-device=auto' usually isn't necessary, but for reasons
        # that bewilder me, adding 'tpm2-measure-pcr=yes' makes it
        # required. And 'tpm2-measure-pcr=yes' is necessary to make sure
        # the TPM2 enters a state where the LUKS volume can no longer be
        # decrypted. That way if we accidentally boot an untrustworthy
        # OS somehow, they can't decrypt the LUKS volume.
        crypttabExtraOpts = ["tpm2-measure-pcr=yes" "tpm2-device=auto"];
      };

      # Adding an fstab is the easiest way to add file systems whose
      # purpose is solely in the initrd and aren't a part of '/sysroot'.
      # The 'x-systemd.after=' might seem unnecessary, since the mount
      # unit will already be ordered after the mapped device, but it
      # helps when stopping the mount unit and cryptsetup service to
      # make sure the LUKS device can close, thanks to how systemd
      # orders the way units are stopped.
      supportedFilesystems.ext4 = true;
      systemd.contents."/etc/fstab".text = ''
        /dev/mapper/credstore /etc/credstore ext4 defaults,x-systemd.after=systemd-cryptsetup@credstore.service 0 2
      '';

      # Add some conflicts to ensure the credstore closes before leaving initrd.
      systemd.targets.initrd-switch-root = {
        conflicts = ["etc-credstore.mount" "systemd-cryptsetup@credstore.service"];
        after = ["etc-credstore.mount" "systemd-cryptsetup@credstore.service"];
      };

      # After the pool is imported and the credstore is mounted, finally
      # load the key. This uses systemd credentials, which is why the
      # credstore is mounted at '/etc/credstore'. systemd will look
      # there for a credential file called 'zfs-sysroot.mount' and
      # provide it in the 'CREDENTIALS_DIRECTORY' that is private to
      # this service. If we really wanted, we could make the credstore a
      # 'WantsMountsFor' instead and allow providing the key through any
      # of the numerous other systemd credential provision mechanisms.
      systemd.services.rpool-load-key = {
        requiredBy = ["initrd.target"];
        before = ["sysroot.mount" "initrd.target"];
        requires = ["import-rpool-bare.service"];
        after = ["import-rpool-bare.service"];
        unitConfig.RequiresMountsFor = "/etc/credstore";
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          ImportCredential = "zfs-sysroot.mount";
          RemainAfterExit = true;
          ExecStart = "${config.boot.zfs.package}/bin/zfs load-key -L file://\"\${CREDENTIALS_DIRECTORY}\"/zfs-sysroot.mount rpool/crypt";
        };
      };

      # Ensure udev doesn't shutdown before cryptsetup detach completes.
      # There's a race condition where udev is being shutdown as we transition
      # out of initrd, but the cryptsetup detach verb needs to do one last udev
      # update, so that has to happen before udev shuts down.
      systemd.services.systemd-udevd.before = ["systemd-cryptsetup@credstore.service"];
    };

    # Disko configuration
    disko.devices = {
      disk.primary = {
        type = "disk";
        device = cfg.device;
        content = {
          type = "gpt";
          partitions =
            {
              esp = {
                name = "ESP";
                size = cfg.espSize;
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = ["umask=0077"];
                };
              };
              zfs = mkMerge [
                {
                  content = {
                    type = "zfs";
                    pool = "rpool";
                  };
                }
                (mkIf cfg.enableEncryptedSwap {
                  end = "-${cfg.swapSize}";
                })
                (mkIf (!cfg.enableEncryptedSwap) {
                  size = "100%";
                })
              ];
            }
            // (mkIf cfg.enableEncryptedSwap {
              encryptedSwap = {
                size = "100%";
                content = {
                  type = "swap";
                  randomEncryption = true;
                  priority = 100;
                };
              };
            });
        };
      };

      zpool.rpool = {
        type = "zpool";
        rootFsOptions = {
          mountpoint = "none";
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
          "com.sun:auto-snapshot" = "true";
        };
        options = {
          ashift = "12";
          autotrim = "on";
        };
        datasets = {
          # Credstore for encryption keys
          credstore = {
            type = "zfs_volume";
            size = "100M";
            content = {
              type = "luks";
              name = "credstore";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = null; # Managed by systemd service
              };
            };
          };

          # Encrypted root dataset
          crypt = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
              encryption = "aes-256-gcm";
              keyformat = "raw";
              keylocation = "file:///etc/credstore/zfs-sysroot.mount";
            };
            preCreateHook = ''
              mount -o X-mount.mkdir /dev/mapper/credstore /etc/credstore
              head -c 32 /dev/urandom > /etc/credstore/zfs-sysroot.mount
            '';
            postCreateHook = ''
              umount /etc/credstore
              cryptsetup luksClose credstore
            '';
          };

          # System datasets under encryption
          "crypt/system" = {
            type = "zfs_fs";
            mountpoint = "/";
            options = {
              mountpoint = "/";
            };
          };

          "crypt/system/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options = {
              "com.sun:auto-snapshot" = "false";
              mountpoint = "/nix";
            };
          };

          "crypt/system/var" = {
            type = "zfs_fs";
            mountpoint = "/var";
            options = {
              mountpoint = "/var";
            };
          };

          "crypt/system/home" = {
            type = "zfs_fs";
            mountpoint = "/home";
            options = {
              mountpoint = "/home";
              "com.sun:auto-snapshot" = "true";
            };
          };

          "crypt/system/tmp" = {
            type = "zfs_fs";
            mountpoint = "/tmp";
            options = {
              mountpoint = "/tmp";
              "com.sun:auto-snapshot" = "false";
              sync = "disabled";
            };
          };
        };
      };
    };

    # All my datasets use 'mountpoint=$path', but you have to be careful
    # with this. You don't want any such datasets to be mounted via
    # 'fileSystems', because it will cause issues when
    # 'zfs-mount.service' also tries to do so. But that's only true in
    # stage 2. For the '/sysroot' file systems that have to be mounted
    # in stage 1, we do need to explicitly add them, and we need to add
    # the 'zfsutil' option. For my pool, that's the '/', '/nix', and
    # '/var' datasets.
    #
    # All of that is incorrect if you just use 'mountpoint=legacy'
    fileSystems = lib.genAttrs ["/" "/nix" "/var"] (fs: {
      device = "rpool/crypt/system${lib.optionalString (fs != "/") fs}";
      fsType = "zfs";
      options = ["zfsutil"];
    });

    # ZFS configuration
    boot.zfs = {
      forceImportRoot = false;
      allowHibernation = false;
    };

    # Kernel parameters for ZFS
    boot.kernelParams = [
      "zfs.zfs_arc_max=${toString (1024 * 1024 * 1024 * 4)}" # 4GB ARC max
    ];

    # Enable ZFS services
    services.zfs = {
      autoScrub = {
        enable = true;
        interval = "weekly";
      };
      autoSnapshot = {
        enable = true;
        flags = "-k -p --utc";
        frequent = 8; # Keep 8 frequent snapshots (15 minutes apart)
        hourly = 24; # Keep 24 hourly snapshots
        daily = 7; # Keep 7 daily snapshots
        weekly = 4; # Keep 4 weekly snapshots
        monthly = 12; # Keep 12 monthly snapshots
      };
      trim = {
        enable = true;
        interval = "weekly";
      };
    };

    # Ensure proper ZFS module loading
    boot.kernelModules = ["zfs"];
    boot.extraModulePackages = with config.boot.kernelPackages; [zfs];
  };
}
