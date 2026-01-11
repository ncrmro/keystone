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
}:
{
  # MicroVM settings
  microvm = {
    hypervisor = "qemu";

    # Workers need less resources than primer
    # Note: Using 2049 instead of 2048 to avoid QEMU hang bug
    mem = 2049;
    vcpu = 1;

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
  # hostname is set per-worker in flake.nix
  system.stateVersion = "25.05";

  # Enable cluster worker
  keystone.cluster.worker = {
    enable = true;
    # Connect to primer's Headscale (via host port forward)
    headscaleUrl = "http://10.0.2.2:8080"; # Host from guest perspective
  };

  # SSH for debugging - prefer key-based auth, fall back to password
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true; # Fallback for debugging
    };
  };

  # Set root password for testing (fallback)
  users.users.root = {
    initialPassword = "root";
    # Test SSH key for automated testing (NOT FOR PRODUCTION)
    openssh.authorizedKeys.keyFiles = [ ../fixtures/test-ssh-key.pub ];
  };

  # Firewall off for testing
  networking.firewall.enable = false;
}
