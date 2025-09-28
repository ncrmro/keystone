{
  # Shared constants for Keystone infrastructure

  # Network configuration
  network = {
    domain = "keystone.local";

    # Infrastructure VMs
    hosts = {
      router = {
        ip = "192.168.1.1";
        vpnIp = "10.100.0.1";
      };
      storage = {
        ip = "192.168.1.10";
        vpnIp = "10.100.0.10";
      };
      backup = {
        ip = "192.168.1.20";
        vpnIp = "10.100.0.20";
      };
      dev = {
        ip = "192.168.1.30";
        vpnIp = "10.100.0.30";
      };
      client = {
        ip = "192.168.1.100";
        vpnIp = "10.100.0.100";
      };
      off-site = {
        ip = "10.0.0.100"; # Different network for off-site
        vpnIp = "10.100.0.200";
      };
    };

    # VPN configuration
    vpn = {
      subnet = "10.100.0.0/24";
      port = 51820;
    };
  };

  # Service ports
  services = {
    # VPN services
    wireguard = {port = 51820;};
    headscale = {
      http = 8080;
      grpc = 50443;
    };

    # Infrastructure services
    adguard = {port = 3000;};
    jellyfin = {port = 8096;};
    nextcloud = {port = 8080;};
    grafana = {port = 3001;};
    prometheus = {port = 9090;};

    # Storage services
    nfs = {port = 2049;};
    samba = {port = 445;};
    minio = {port = 9000;};
  };

  # SSH keys for infrastructure
  sshKeys = {
    admin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG..."; # Replace with actual key
    backup = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH..."; # Replace with actual key
  };
}
