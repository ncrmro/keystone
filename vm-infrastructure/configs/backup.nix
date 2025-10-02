# Backup Server Configuration
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../modules/server
    ../modules/disko-single-disk-root
  ];

  # Enable Keystone server modules
  keystone.server = {
    enable = true;
    backup = {
      enable = true;
      storageDevice = "/dev/disk/by-id/virtio-backup-disk-001";
    };
    monitoring.enable = true;
  };

  # Disko configuration for encrypted root
  keystone.disko = {
    enable = true;
    device = "/dev/disk/by-id/virtio-os-disk-backup";
    enableEncryptedSwap = false;
  };

  # Network configuration
  networking = {
    hostName = "keystone-backup";
    hostId = "c3d4e5f6"; # Random 8-char hex string

    # Use DHCP with static lease
    useDHCP = false;
    interfaces.enp1s0.useDHCP = true;
  };

  # Backup services
  services = {
    # Restic backup service
    restic.backups = {
      daily = {
        initialize = true;
        repository = "/srv/backup/restic";
        passwordFile = "/etc/nixos/secrets/restic-password";
        paths = [
          "/home"
          "/var/lib"
          "/etc/nixos"
        ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    };

    # Rsync daemon for remote backups
    rsyncd = {
      enable = true;
      settings = {
        global = {
          "use chroot" = true;
          "max connections" = 4;
        };
        backup = {
          path = "/srv/backup/rsync";
          comment = "Backup storage";
          "read only" = false;
          "auth users" = "backup";
          "secrets file" = "/etc/rsyncd.secrets";
        };
      };
    };
  };

  # Create backup directories
  systemd.tmpfiles.rules = [
    "d /srv/backup 0755 root root"
    "d /srv/backup/restic 0755 root root"
    "d /srv/backup/rsync 0755 backup backup"
  ];

  # Backup user
  users.users.backup = {
    isSystemUser = true;
    group = "backup";
    home = "/srv/backup";
    createHome = true;
  };
  users.groups.backup = {};

  # Open firewall for backup services
  networking.firewall.allowedTCPPorts = [873]; # rsync

  # System configuration
  system.stateVersion = "25.05";
}
