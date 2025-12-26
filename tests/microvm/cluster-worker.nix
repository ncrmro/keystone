# MicroVM Configuration for Cluster Workers
#
# This configuration runs worker nodes with Tailscale client in microVMs.
# Workers connect to the primer's Headscale server.
#
# Run: nix build .#nixosConfigurations.cluster-worker1.config.microvm.declaredRunner
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

    # Workers need less resources than primer
    mem = 2048;
    vcpu = 1;

    # User-mode networking
    interfaces = [
      {
        type = "user";
        id = "net0";
        # MAC will be overridden per-worker
        mac = "02:00:00:00:00:10";
      }
    ];

    # Forward SSH for debugging
    forwardPorts = [
      {
        from = "host";
        host.port = 2223; # Adjust per worker
        guest.port = 22;
      }
    ];

    # Share /nix/store from host
    shares = [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      }
    ];
  };

  # Basic system configuration
  # hostname is set per-worker in flake.nix
  system.stateVersion = "25.05";

  # Enable cluster worker
  keystone.cluster.worker = {
    enable = true;
    # Connect to primer's Headscale (via host port forward)
    headscaleUrl = "http://10.0.2.2:8080"; # Host from guest perspective
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
