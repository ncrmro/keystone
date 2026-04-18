# Pi Kodi Appliance — bootstrap USB installer
#
# Two-phase appliance model:
#   Phase 1 (this module): an ext4 image flashed to a USB stick. Pi boots
#     from USB, runs an auto-install onto the inserted SD card, then reboots.
#   Phase 2 (final system): ZFS root on the SD card + Kodi kiosk, booting via
#     pftf UEFI + systemd-boot on the SD's FAT32 ESP.
#
# Why ZFS lives on the SD (not on USB): SD cards suffer silent bit rot; ZFS
# scrub surfaces + repairs data corruption that ext4 on SD would silently
# return as healthy. The USB is a disposable installer carrier.
#
# Pi 4/5 EEPROM must be configured for USB-boot priority (or SD removed at
# first boot) so the bootrom picks the USB installer. Configure via
# `rpi-eeprom-config` with BOOT_ORDER=0xf14 (USB → SD → network).
#
# The final system's full Nix closure is embedded into the bootstrap image
# via system.extraDependencies so first-boot install works offline.
#
# Consumers don't import this directly — use lib.mkPiKodiAppliance instead.
{
  config,
  pkgs,
  lib,
  finalSystem,
  finalSystemToplevel,
  ...
}:
with lib;
let
  cfg = config.keystone.piKodi;

  # Shell snippet that copies every uefiFirmware entry into /mnt/boot at
  # install time. Keys may contain subdirs (e.g. "overlays/foo.dtbo").
  pftfCopyCommands = concatStrings (
    mapAttrsToList (name: src: ''
      install -D -m0644 ${src} "/mnt/boot/${name}"
    '') cfg.uefiFirmware
  );
in
{
  options.keystone.piKodi = {
    sshKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "SSH keys for root on both the bootstrap and final systems.";
    };

    uefiFirmware = mkOption {
      type = types.attrsOf types.path;
      description = ''
        pftf/RPi4 firmware files. Copied onto the SD's new ESP partition by
        the install script, so they are NOT present on the USB installer
        itself (which boots via the sd-image's stock extlinux).
      '';
    };

    targetDiskPattern = mkOption {
      type = types.str;
      default = "mmc-";
      description = ''
        Prefix of the /dev/disk/by-id/ entry identifying the target SD card
        for the ZFS pool. First matching non-partition entry wins.
      '';
    };

    espSize = mkOption {
      type = types.str;
      default = "1024MiB";
      description = "Size of the ESP partition on the SD (pftf + systemd-boot + kernels).";
    };
  };

  config = {
    system.stateVersion = "25.05";

    # Embed the final system's closure so install needs no network.
    system.extraDependencies = [ finalSystemToplevel ];

    # Keep HDMI output alive throughout boot + install; serial stays as backup.
    boot.kernelParams = mkForce [
      "console=tty1"
      "console=ttyS0,115200"
    ];

    # Bootstrap needs ZFS to create the target pool.
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;
    # Arbitrary, only for the bootstrap system's own ZFS hostId requirement.
    networking.hostId = "b00751ad";

    image.baseName = mkForce "keystone-pi-kodi-bootstrap";
    # Expand the ext4 bootstrap rootfs to fill the USB so the closure fits.
    sdImage.expandOnBoot = true;

    # SSH fallback for debugging install failures.
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = mkForce "yes";
        PasswordAuthentication = false;
      };
    };
    users.users.root.openssh.authorizedKeys.keys = cfg.sshKeys;

    # Docs bloat the image and are not needed for a single-boot bootstrap.
    documentation.enable = false;
    documentation.nixos.enable = false;

    # The install oneshot. Runs after getty so the user sees output on tty1.
    systemd.services.pi-kodi-install = {
      description = "Install Kodi appliance to ZFS on the inserted SD card";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "systemd-udev-settle.service"
      ];
      wants = [ "systemd-udev-settle.service" ];
      conflicts = [ "shutdown.target" ];

      # Everything the install script uses must be on PATH in the unit.
      path = with pkgs; [
        config.boot.zfs.package
        util-linux
        parted
        gptfdisk
        dosfstools
        e2fsprogs
        systemd
        coreutils
        nix
        config.systemd.package
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
        TTYPath = "/dev/tty1";
      };

      # The marker file prevents re-running if the first attempt succeeded.
      script = ''
        set -euo pipefail

        marker=/var/lib/pi-kodi/installed
        mkdir -p "$(dirname "$marker")"
        if [ -f "$marker" ]; then
          echo "[pi-kodi] Already installed; rebooting into final system…"
          sleep 3
          systemctl reboot
          exit 0
        fi

        banner() {
          echo ""
          echo "============================================================"
          echo "  $1"
          echo "============================================================"
          echo ""
        }

        banner "Pi Kodi Appliance — first-boot install"
        echo "Waiting up to 60s for a target disk matching '${cfg.targetDiskPattern}'…"

        target=""
        for i in $(seq 1 30); do
          for entry in /dev/disk/by-id/${cfg.targetDiskPattern}*; do
            [ -e "$entry" ] || continue
            case "$entry" in *-part*) continue ;; esac
            target="$entry"
            break 2
          done
          sleep 2
        done

        if [ -z "$target" ]; then
          banner "ERROR: No SD card detected."
          echo "Insert an SD card and reboot the Pi to retry."
          exit 1
        fi

        banner "Target SD card: $target"
        target_real=$(readlink -f "$target")
        echo "Resolved to: $target_real"

        banner "Partitioning SD: ESP (FAT32) + ZFS"
        # Wipe any prior signatures so zpool/mkfs don't refuse.
        wipefs -af "$target_real" || true
        sgdisk --zap-all "$target_real"
        # ESP = partition 1, ZFS pool = partition 2 (rest of disk).
        parted -s "$target_real" mklabel gpt
        parted -s "$target_real" mkpart ESP fat32 1MiB ${cfg.espSize}
        parted -s "$target_real" set 1 esp on
        parted -s "$target_real" mkpart rpool ${cfg.espSize} 100%
        udevadm settle

        # Resolve partition paths (mmc devices use 'p1'/'p2' suffixes).
        esp_part="$target-part1"
        zfs_part="$target-part2"
        if [ ! -e "$esp_part" ]; then
          esp_part="''${target_real}p1"
          zfs_part="''${target_real}p2"
        fi
        if [ ! -e "$esp_part" ]; then
          esp_part="''${target_real}1"
          zfs_part="''${target_real}2"
        fi
        echo "ESP partition: $esp_part"
        echo "ZFS partition: $zfs_part"

        banner "Formatting ESP + creating rpool"
        mkfs.vfat -F32 -n ESP "$esp_part"

        zpool create -f \
          -o ashift=12 \
          -O mountpoint=none \
          -O compression=zstd \
          -O atime=off \
          -O acltype=posixacl \
          -O xattr=sa \
          -O dnodesize=auto \
          -O normalization=formD \
          rpool "$zfs_part"

        zfs create -o mountpoint=/ rpool/root
        zfs create -o mountpoint=/nix -o com.sun:auto-snapshot=false rpool/nix
        zfs create -o mountpoint=/var rpool/var

        banner "Mounting target filesystems"
        mkdir -p /mnt
        mount -t zfs -o zfsutil rpool/root /mnt
        mkdir -p /mnt/nix /mnt/var /mnt/boot
        mount -t zfs -o zfsutil rpool/nix /mnt/nix
        mount -t zfs -o zfsutil rpool/var /mnt/var
        mount "$esp_part" /mnt/boot

        banner "Staging pftf/RPi4 UEFI firmware onto the ESP"
        ${pftfCopyCommands}

        banner "Installing final Kodi appliance system"
        nixos-install \
          --root /mnt \
          --system ${finalSystemToplevel} \
          --no-root-password \
          --no-channel-copy

        banner "Install complete — marking + rebooting"
        mkdir -p /mnt/var/lib/pi-kodi
        touch /mnt/var/lib/pi-kodi/installed
        touch "$marker"

        umount /mnt/boot /mnt/var /mnt/nix /mnt || true
        zpool export rpool || true

        echo ""
        echo "Rebooting into Kodi appliance in 5s…"
        sleep 5
        systemctl reboot
      '';
    };

    # Helpful banner on tty1 before the install service claims it.
    systemd.services."getty@tty1" = {
      serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/echo -e '\\n[pi-kodi] Waiting for pi-kodi-install.service to finish…\\n'";
    };
  };
}
