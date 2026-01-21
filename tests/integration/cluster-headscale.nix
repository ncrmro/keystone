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
    primer =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        # Build Headscale image for the test
        headscaleImage = pkgs.dockerTools.buildImage {
          name = "headscale/headscale";
          tag = "0.23.0";
          copyToRoot = [
            pkgs.headscale
            pkgs.cacert
            pkgs.busybox
          ];
          config = {
            Cmd = [ "/bin/headscale" ];
            Env = [
              "PATH=/bin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        # Build Pause image for k3s sandbox
        pauseImage = pkgs.dockerTools.buildImage {
          name = "rancher/mirrored-pause";
          tag = "3.6";
          copyToRoot = [ pkgs.busybox ];
          config = {
            Cmd = [
              "/bin/sh"
              "-c"
              "sleep inf"
            ];
          };
        };
      in
      {
        imports = [ self.nixosModules.cluster-primer ];

        system.stateVersion = "25.05";

        # Pre-load images into k3s
        systemd.services.k3s-import-images = {
          description = "Import images into k3s";
          wantedBy = [ "multi-user.target" ];
          before = [ "headscale-deploy.service" ];
          after = [ "k3s.service" ];
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
        systemd.services.headscale-deploy.requires = [ "k3s-import-images.service" ];
        systemd.services.headscale-deploy.after = [ "k3s-import-images.service" ];

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
    worker1 =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      {
        imports = [ self.nixosModules.cluster-worker ];

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
    worker2 =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      {
        imports = [ self.nixosModules.cluster-worker ];

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
    worker3 =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      {
        imports = [ self.nixosModules.cluster-worker ];

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

    # Try to wait for deployment, but capture logs if it fails
    try:
        primer.wait_for_unit("headscale-deploy.service", timeout=300)
        print("Headscale deployment service completed")
    except Exception as e:
        print(f"Deployment failed: {e}")
        print("\n=== Checking pod status ===")
        pod_status = primer.execute("kubectl get pods -n headscale-system -o wide")[1]
        print(pod_status)
        print("\n=== Checking deployment status ===")
        deploy_status = primer.execute("kubectl describe deployment headscale -n headscale-system")[1]
        print(deploy_status)
        print("\n=== Capturing pod logs ===")
        pod_logs = primer.execute("kubectl logs -n headscale-system -l app=headscale --tail=100")[1]
        print(pod_logs)
        print("\n=== Checking events ===")
        events = primer.execute("kubectl get events -n headscale-system --sort-by='.lastTimestamp'")[1]
        print(events)
        raise

    # Verify Headscale pod is running
    primer.succeed("kubectl get pods -n headscale-system")
    print("Headscale pods are running")

    # Wait for NodePort to be accessible
    primer.wait_for_open_port(30080)
    print("Headscale HTTP endpoint is accessible on port 30080")

    # Phase 3: Generate pre-auth key
    print("\n[Phase 3] Generating pre-auth key...")
    
    # First, list users to get the user ID
    print("Listing users to get user ID...")
    users_output = primer.succeed(
        "kubectl exec -n headscale-system deploy/headscale -- "
        "headscale users list --output json"
    ).strip()
    print(f"Users output: {users_output}")
    
    # Extract user ID from JSON output (first user should be 'default')
    import json
    users = json.loads(users_output)
    if not users:
        raise Exception("No users found in headscale")
    
    user_id = users[0]["id"]
    print(f"Using user ID: {user_id}")
    
    # Now create preauth key with numeric user ID
    auth_key = primer.succeed(
        f"kubectl exec -n headscale-system deploy/headscale -- "
        f"headscale preauthkeys create --user {user_id} --reusable --expiration 1h"
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
    worker1.succeed("tailscale ping -c 3 worker2")
    print("    OK")

    # worker2 -> worker3
    print("  worker2 -> worker3...")
    worker2.succeed("tailscale ping -c 3 worker3")
    print("    OK")

    # worker3 -> worker1
    print("  worker3 -> worker1...")
    worker3.succeed("tailscale ping -c 3 worker1")
    print("    OK")

    print("\n" + "=" * 60)
    print("SUCCESS: All cluster nodes can communicate via Headscale mesh!")
    print("=" * 60)
  '';
}
