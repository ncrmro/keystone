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
}:
{
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
      # Headscale DERP/STUN
      {
        from = "host";
        host.port = 13478;
        guest.port = 3478;
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
      # Use 10.0.2.2 (host IP from guest) so workers can reach it via forwarded port
      serverUrl = "http://10.0.2.2:18080";
      baseDomain = "cluster.local";
    };
    # Use agenix-managed secrets for Headscale keys
    headscaleDeployment.useAgenixSecrets = true;
  };

  # ============================================================
  # Agenix Secret Management (for testing the full secrets flow)
  # ============================================================
  # WARNING: Uses test-only age key committed to repo - NOT for production!

  # Age identity for decryption - use nix store path directly
  # IMPORTANT: The identity file MUST be available during initrd activation,
  # so we reference it from the nix store (NOT /etc which isn't mounted yet)
  age.identityPaths = [ "${../fixtures/test-age-key.txt}" ];

  # Also provision to /etc for manual decryption debugging (optional)
  environment.etc."age/test-key.txt" = {
    source = ../fixtures/test-age-key.txt;
    mode = "0400";
  };

  # Secrets to decrypt at boot (decrypted to /run/agenix/)
  age.secrets = {
    headscale-private = {
      file = ../fixtures/headscale-private.age;
    };
    headscale-noise = {
      file = ../fixtures/headscale-noise.age;
    };
    headscale-derp = {
      file = ../fixtures/headscale-derp.age;
    };
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
