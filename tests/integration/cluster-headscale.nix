# Cluster Headscale Integration Test
#
# Tests the Headscale mesh networking between a primer and 3 worker nodes.
# Validates that:
# - k3s starts on primer
# - Headscale deploys successfully in k3s
# - Workers can register with Headscale
# - All nodes can ping each other via the mesh
#
# Build: nix build .#cluster-headscale
# Interactive: nix build .#cluster-headscale.driverInteractive
#
{
  pkgs,
  lib,
  self,
}:
pkgs.testers.nixosTest {
  name = "cluster-headscale";

  nodes = {
    # Primer server with k3s and Headscale
    primer = {
      config,
      pkgs,
      lib,
      ...
    }: let
      # Build Headscale image for the test
      headscaleImage = pkgs.dockerTools.buildImage {
        name = "headscale/headscale";
        tag = "0.23.0";
        copyToRoot = [ pkgs.headscale pkgs.cacert pkgs.busybox ];
        config = {
          Cmd = [ "/bin/headscale" ];
          Env = [ "PATH=/bin" "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];
        };
      };

      # Build Pause image for k3s sandbox
      pauseImage = pkgs.dockerTools.buildImage {
        name = "rancher/mirrored-pause";
        tag = "3.6";
        copyToRoot = [ pkgs.busybox ];
        config = {
          Cmd = [ "/bin/sh" "-c" "sleep inf" ];
        };
      };
    in {
      imports = [self.nixosModules.cluster-primer];

      system.stateVersion = "25.05";

      # Pre-load images into k3s
      systemd.services.k3s-import-images = {
        description = "Import images into k3s";
        wantedBy = ["multi-user.target"];
        before = ["headscale-deploy.service"];
        after = ["k3s.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.k3s}/bin/k3s ctr images import ${headscaleImage}
          ${pkgs.k3s}/bin/k3s ctr images import ${pauseImage}
        '';
      };

      # Ensure deployment waits for image import
      systemd.services.headscale-deploy.requires = ["k3s-import-images.service"];
      systemd.services.headscale-deploy.after = ["k3s-import-images.service"];

      keystone.cluster.primer = {
        enable = true;
        headscale = {
          serverUrl = "http://primer:30080";
          baseDomain = "test.local";
          storage.type = "ephemeral";
        };
        k3s.disableComponents = [
          "traefik"
          "metrics-server"
          "local-storage"
          "coredns"
        ];
      };

      # VM settings - k3s needs more resources
      virtualisation = {
        memorySize = 4096;
        cores = 2;
        # k3s needs writable /var/lib/rancher
        writableStoreUseTmpfs = false;
      };

      # Disable firewall for testing simplicity
      networking.firewall.enable = lib.mkForce false;
    };

    # Worker 1
    worker1 = {
      config,
      pkgs,
      lib,
      ...
    }: {
      imports = [self.nixosModules.cluster-worker];

      system.stateVersion = "25.05";

      keystone.cluster.worker = {
        enable = true;
        headscaleUrl = "http://primer:30080";
      };

      virtualisation = {
        memorySize = 2048;
        cores = 1;
      };

      networking.firewall.enable = lib.mkForce false;
    };

    # Worker 2
    worker2 = {
      config,
      pkgs,
      lib,
      ...
    }: {
      imports = [self.nixosModules.cluster-worker];

      system.stateVersion = "25.05";

      keystone.cluster.worker = {
        enable = true;
        headscaleUrl = "http://primer:30080";
      };

      virtualisation = {
        memorySize = 2048;
        cores = 1;
      };

      networking.firewall.enable = lib.mkForce false;
    };

    # Worker 3
    worker3 = {
      config,
      pkgs,
      lib,
      ...
    }: {
      imports = [self.nixosModules.cluster-worker];

      system.stateVersion = "25.05";

      keystone.cluster.worker = {
        enable = true;
        headscaleUrl = "http://primer:30080";
      };

      virtualisation = {
        memorySize = 2048;
        cores = 1;
      };

      networking.firewall.enable = lib.mkForce false;
    };
  };

  testScript = ''
    print("=" * 60)
    print("Starting Keystone Cluster Headscale Test")
    print("=" * 60)

    # Phase 1: Start primer and wait for k3s
    print("\n[Phase 1] Starting primer node...")
    primer.start()
    primer.wait_for_unit("multi-user.target")
    print("Primer booted successfully")

    # Wait for k3s to be ready
    print("Waiting for k3s to start...")
    primer.wait_for_unit("k3s.service")
    primer.wait_for_open_port(6443)
    print("k3s API server is running")

    # Wait for k3s-ready service
    print("Waiting for k3s-ready service...")
    primer.wait_for_unit("k3s-ready.service")
    print("k3s is fully ready")

    # Phase 2: Wait for Headscale deployment
    print("\n[Phase 2] Waiting for Headscale deployment...")

    # Wait for headscale-deploy service
    primer.wait_for_unit("headscale-deploy.service", timeout=300)
    print("Headscale deployment service completed")

    # Verify Headscale pod is running
    primer.succeed("kubectl get pods -n headscale-system")
    print("Headscale pods are running")

    # Wait for NodePort to be accessible
    primer.wait_for_open_port(30080)
    print("Headscale HTTP endpoint is accessible on port 30080")

    # Phase 3: Generate pre-auth key
    print("\n[Phase 3] Generating pre-auth key...")
    auth_key = primer.succeed(
        "kubectl exec -n headscale-system deploy/headscale -- "
        "headscale preauthkeys create --user default --reusable --expiration 1h"
    ).strip()
    print(f"Generated auth key: {auth_key[:20]}...")

    # Phase 4: Start workers and register with Headscale
    print("\n[Phase 4] Starting worker nodes...")

    workers = [worker1, worker2, worker3]
    worker_names = ["worker1", "worker2", "worker3"]

    for i, (worker, name) in enumerate(zip(workers, worker_names)):
        print(f"Starting {name}...")
        worker.start()
        worker.wait_for_unit("multi-user.target")
        worker.wait_for_unit("tailscaled.service")
        print(f"{name} booted successfully")

        # Register with Headscale
        print(f"Registering {name} with Headscale...")
        worker.succeed(
            f"tailscale up --login-server=http://primer:30080 "
            f"--authkey={auth_key} --hostname={name} --accept-dns=false"
        )
        print(f"{name} registered successfully")

    # Phase 5: Verify mesh connectivity
    print("\n[Phase 5] Verifying mesh connectivity...")

    # List all nodes in Headscale
    print("Nodes registered with Headscale:")
    primer.succeed("kubectl exec -n headscale-system deploy/headscale -- headscale nodes list")

    # Verify tailscale status on all workers
    for worker, name in zip(workers, worker_names):
        print(f"\n{name} tailscale status:")
        worker.succeed("tailscale status")

    # Test ping between workers
    print("\nTesting mesh connectivity:")

    # worker1 -> worker2
    print("  worker1 -> worker2...")
    worker1.succeed("tailscale ping worker2 --timeout=30s")
    print("    OK")

    # worker2 -> worker3
    print("  worker2 -> worker3...")
    worker2.succeed("tailscale ping worker3 --timeout=30s")
    print("    OK")

    # worker3 -> worker1
    print("  worker3 -> worker1...")
    worker3.succeed("tailscale ping worker1 --timeout=30s")
    print("    OK")

    # All workers -> primer (via Tailscale IP)
    print("\nTesting connectivity to primer...")
    for worker, name in zip(workers, worker_names):
        print(f"  {name} -> primer...")
        # Get primer's Tailscale IP
        primer_ip = primer.succeed("tailscale ip -4").strip()
        worker.succeed(f"ping -c 1 {primer_ip}")
        print(f"    OK (primer IP: {primer_ip})")

    print("\n" + "=" * 60)
    print("SUCCESS: All cluster nodes can communicate via Headscale mesh!")
    print("=" * 60)
  '';
}
