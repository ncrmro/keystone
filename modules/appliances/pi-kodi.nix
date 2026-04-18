# Pi Kodi Appliance — bootstrap sd-image
#
# Two-phase appliance model:
#   Phase 1 (this module): an ext4 sd-image that boots once, runs an
#     auto-install onto an attached USB disk, then reboots.
#   Phase 2 (final system): ZFS root on the USB disk + Kodi kiosk,
#     booting via pftf UEFI + systemd-boot on the SD's FAT32 partition.
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
      description = "pftf/RPi4 firmware files staged onto the SD's FAT32 partition.";
    };

    targetDiskPattern = mkOption {
      type = types.str;
      default = "usb-";
      description = ''
        Prefix of the /dev/disk/by-id/ entry identifying the target USB disk
        for the ZFS pool. First matching non-partition entry wins.
      '';
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
    # Arbitrary, only for the bootstrap system's ZFS hostId requirement.
    networking.hostId = "b00751ad";

    # Stage pftf firmware files onto the FAT32 firmware partition that the
    # sd-image builder creates. After install, systemd-boot will coexist here.
    # sd-image-aarch64 sets its own populateFirmwareCommands (rpi firmware +
    # extlinux.conf) using types.lines, so ours concatenates. Each line MUST
    # end in a newline or bash merges it with the next block.
    sdImage.firmwareSize = 1024; # MiB — pftf + future systemd-boot + kernels
    sdImage.populateFirmwareCommands = concatStrings (
      mapAttrsToList (name: src: "cp -v ${src} firmware/${name}\n") cfg.uefiFirmware
    );
    sdImage.imageBaseName = mkForce "keystone-pi-kodi-bootstrap";

    # Expand the ext4 bootstrap rootfs to fill the SD so the closure fits.
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
      description = "Install Kodi appliance to ZFS on attached USB disk";
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

      # The marker file prevents re-running if the first attempt succeeded but
      # the reboot didn't happen for some reason.
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
        echo "Waiting up to 60s for a USB disk matching '${cfg.targetDiskPattern}'…"

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
          banner "ERROR: No USB disk detected."
          echo "Plug in a USB SSD/HDD and reboot the Pi to retry."
          exit 1
        fi

        banner "Target USB disk: $target"
        target_real=$(readlink -f "$target")
        echo "Resolved to: $target_real"

        banner "Partitioning + creating ZFS pool"
        # Wipe any prior signatures so zpool create doesn't refuse.
        wipefs -af "$target_real" || true
        sgdisk --zap-all "$target_real" || parted -s "$target_real" mklabel gpt
        parted -s "$target_real" mklabel gpt
        parted -s "$target_real" mkpart primary 1MiB 100%
        # Allow udev to settle before touching the new partition.
        udevadm settle

        zfs_part="$target-part1"
        if [ ! -e "$zfs_part" ]; then
          # Fallback: append -part1 to the resolved /dev path.
          zfs_part="$(echo "$target_real" | sed 's/$/p1/')"
          [ -e "$zfs_part" ] || zfs_part="''${target_real}1"
        fi
        echo "ZFS partition: $zfs_part"

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

        banner "Mounting ZFS + binding SD /boot"
        mkdir -p /mnt
        mount -t zfs -o zfsutil rpool/root /mnt
        mkdir -p /mnt/nix /mnt/var /mnt/boot
        mount -t zfs -o zfsutil rpool/nix /mnt/nix
        mount -t zfs -o zfsutil rpool/var /mnt/var
        # Bind the SD's FAT32 (already mounted at /boot here in the bootstrap)
        # so nixos-install writes systemd-boot to it.
        mount --bind /boot /mnt/boot

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
