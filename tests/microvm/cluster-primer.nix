# MicroVM Configuration for Cluster Primer
#
# This configuration runs the primer server (k3s + Headscale) in a microVM
# with user-mode networking for internet access to pull container images.
#
# Run: nix build .#nixosConfigurations.cluster-primer.config.microvm.declaredRunner
#      ./result/bin/microvm-run
#
{
  config,
  pkgs,
  lib,
  ...
}: {
  # MicroVM settings
  microvm = {
    hypervisor = "qemu";

    # Resources - k3s needs decent memory
    mem = 4096;
    vcpu = 2;

    # User-mode networking with port forwards
    # This provides NAT internet access without root
    interfaces = [
      {
        type = "user";
        id = "net0";
        mac = "02:00:00:00:00:01";
      }
    ];

    # Forward ports for access from host
    # Using high port numbers to avoid conflicts with other VMs/containers
    forwardPorts = [
      # SSH
      {
        from = "host";
        host.port = 22223;
        guest.port = 22;
      }
      # k3s API
      {
        from = "host";
        host.port = 16443;
        guest.port = 6443;
      }
      # Headscale HTTP
      {
        from = "host";
        host.port = 18080;
        guest.port = 30080;
      }
    ];

    # Persistent volume for k3s data
    volumes = [
      {
        mountPoint = "/var/lib/rancher";
        image = "rancher.img";
        size = 4096; # 4GB
      }
    ];

    # Share /nix/store from host (faster builds)
    shares = [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      }
    ];
  };

  # Basic system configuration
  networking.hostName = "primer";
  system.stateVersion = "25.05";

  # Enable cluster primer
  keystone.cluster.primer = {
    enable = true;
    headscale = {
      # Use localhost since we're port-forwarding
      serverUrl = "http://localhost:8080";
      baseDomain = "cluster.local";
    };
  };

  # SSH for debugging
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Set root password for testing
  users.users.root.initialPassword = "root";

  # Firewall off for testing
  networking.firewall.enable = false;
}
