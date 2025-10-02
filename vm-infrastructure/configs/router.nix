# Router/Gateway Server Configuration
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
    router = {
      enable = true;
      lanInterface = "enp1s0";
      wanInterface = "enp2s0"; # If dual-NIC setup
    };
    vpn.enable = true;
    dns.enable = true;
    firewall.enable = true;
  };

  # Disko configuration for encrypted root
  keystone.disko = {
    enable = true;
    device = "/dev/disk/by-id/virtio-os-disk-router";
    enableEncryptedSwap = false; # Router doesn't need much swap
  };

  # Network configuration
  networking = {
    hostName = "keystone-router";
    hostId = "8425e349"; # Random 8-char hex string

    # Router-specific networking
    useDHCP = false;
    interfaces.enp1s0 = {
      ipv4.addresses = [
        {
          address = "192.168.100.10";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = "192.168.100.1";
    nameservers = ["192.168.100.1"];
  };

  # Enable IP forwarding for routing
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # System configuration
  system.stateVersion = "25.05";
}
