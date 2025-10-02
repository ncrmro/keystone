# Storage/NAS Server Configuration
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
    nas = {
      enable = true;
      dataDisks = [
        "/dev/disk/by-id/virtio-data-disk-001"
        "/dev/disk/by-id/virtio-data-disk-002"
      ];
    };
    media.enable = true;
    backup.enable = true;
    monitoring.enable = true;
  };

  # Disko configuration for encrypted root
  keystone.disko = {
    enable = true;
    device = "/dev/disk/by-id/virtio-os-disk-storage";
    enableEncryptedSwap = true;
  };

  # Network configuration
  networking = {
    hostName = "keystone-storage";
    hostId = "a1b2c3d4"; # Random 8-char hex string

    # Use DHCP with static lease (defined in network config)
    useDHCP = false;
    interfaces.enp1s0.useDHCP = true;
  };

  # ZFS configuration for data pool
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.requestEncryptionCredentials = true;

  # Additional storage services
  services = {
    # Samba for Windows/macOS compatibility
    samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          "workgroup" = "WORKGROUP";
          "server string" = "Keystone Storage";
          "netbios name" = "keystone-storage";
          "security" = "user";
          "map to guest" = "bad user";
        };
      };
    };

    # NFS for Linux clients
    nfs.server = {
      enable = true;
      exports = ''
        /srv/nfs/shared *(rw,sync,no_subtree_check)
      '';
    };
  };

  # Create NFS export directory
  systemd.tmpfiles.rules = [
    "d /srv/nfs/shared 0755 nobody nogroup"
  ];

  # Open firewall for storage services
  networking.firewall.allowedTCPPorts = [2049 139 445];
  networking.firewall.allowedUDPPorts = [2049 137 138];

  # System configuration
  system.stateVersion = "25.05";
}
