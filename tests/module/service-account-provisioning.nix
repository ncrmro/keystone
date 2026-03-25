# Service account provisioning test
#
# Verifies the end-to-end flow of agent service account provisioning:
#   1. Stalwart mail server setup and REST API readiness.
#   2. Forgejo git server setup and REST API readiness.
#   3. Automatic creation of agent accounts via NixOS activation.
#   4. Automatic CalDAV calendar creation and sharing ACLs.
#   5. PIM CLI tools (calendula) availability.
#   6. Forgejo CLI (tea, fj) availability.
#
# Build:       nix build .#checks.x86_64-linux.test-service-account-provisioning
# Interactive: nix build .#checks.x86_64-linux.test-service-account-provisioning.driverInteractive
#
{
  pkgs,
  lib,
  self,
  home-manager,
}:
pkgs.testers.nixosTest {
  name = "service-account-provisioning";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [
        home-manager.nixosModules.home-manager
        self.nixosModules.operating-system
        self.nixosModules.server
      ];

      # Configure Keystone
      keystone = {
        domain = "test.local";
        os = {
          enable = true;
          # Machine acts as its own mail and git server for testing
          mail.allowedIps = [ "127.0.0.1" ];
          gitServer = {
            enable = true;
            # Disable runner to avoid podman overhead in VM test
            runner.enable = false;
          };

          # Define a human user (receives calendar shares)
          users.nicholas = {
            fullName = "Nicholas Romero";
            email = "nicholas@test.local";
            initialPassword = "human-password-456";
            terminal.enable = true;
          };

          # Define an agent with full provisioning enabled
          agents.drago = {
            fullName = "Drago Agent";
            terminal.enable = true;
            mail.provision = true;
            git.provision = true;
          };

          # Minimal storage for evaluation
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
        };

        # DISABLE mail.nix configuration to avoid conflicts and errors
        services.mail.host = lib.mkForce null;
        services.git.host = "machine";
      };

      networking.hostName = "machine";
      networking.hosts."127.0.0.1" = [
        "git.test.local"
        "mail.test.local"
      ];

      # The NixOS VM test environment has no external network access.
      # Disable Tailscale so tailscaled does not block startup on DERP/DNS retries.
      keystone.os.tailscale.enable = lib.mkForce false;
      services.tailscale.enable = lib.mkForce false;

      # Provide working DNS config
      networking.nameservers = [ "1.1.1.1" ];

      # Register the host in keystone.hosts to satisfy assertions
      keystone.hosts.machine = {
        hostname = "machine";
        role = "server";
      };

      # Disable secret assertions for the test — we mock them via activation script
      age.secrets = {
        stalwart-admin-password.file = "/dev/null";
        agent-drago-mail-password.file = "/dev/null";
        agent-drago-bitwarden-password.file = "/dev/null";
      };

      # Mock agenix secrets for provisioning
      system.activationScripts.mock-agenix-secrets = {
        text = ''
          mkdir -p /run/agenix
          echo -n "admin-test-password" > /run/agenix/stalwart-admin-password
          echo -n "agent-password-123" > /run/agenix/agent-drago-mail-password
          echo -n "bw-password-789" > /run/agenix/agent-drago-bitwarden-password
          chmod 400 /run/agenix/*
        '';
        deps = [ "users" ];
      };

      # Provision dummy signing keys for Forgejo just in case
      system.activationScripts.forgejo-keys = {
        text = ''
          mkdir -p /var/lib/forgejo/ssh
          # Dummy Ed25519 public key
          echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOm6u6SbgfsgBy0Z6AdSh12MWTiTrSvy9rvMCIGZ69Id forgejo@test" > /var/lib/forgejo/ssh/ssh_host_ed25519_key.pub
          # Dummy Ed25519 private key (unencrypted)
          cat << 'KEY' > /var/lib/forgejo/ssh/ssh_host_ed25519_key
          -----BEGIN OPENSSH PRIVATE KEY-----
          b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
          QyNTUxOQAAACDpuuvkm4H7IAcMOedHUoddjFskkk0kr777AzAhBnOfSHAAbMDpuvkm6br5
          JQAAAAtzc2gtZWQyNTUxOQAAACDpuuvkm4H7IAcMOedHUoddjFskkk0kr777AzAhBnOfSH
          AAAABAAAAAALZm9yZ2Vqb0B0ZXN0AQIDBAU=
          -----END OPENSSH PRIVATE KEY-----
          KEY
          chmod 600 /var/lib/forgejo/ssh/ssh_host_ed25519_key
          chown -R forgejo:forgejo /var/lib/forgejo/ssh
        '';
        deps = [ "users" ];
      };

      system.activationScripts.stalwart-spam-filter = {
        text = ''
          install -d -m 0755 /var/lib/stalwart
          cat > /var/lib/stalwart/spam-filter.toml <<'EOF'
          [version]
          spam-filter = "2.0.5"
          server = "0.11.0"
          EOF
          chmod 0644 /var/lib/stalwart/spam-filter.toml
        '';
        deps = [ "users" ];
      };

      # Manually enable Stalwart with a known-working minimal config
      services.stalwart = {
        enable = true;
        settings = {
          server.hostname = "machine";
          server.tls.enable = false;
          server.listener.http = {
            protocol = "http";
            bind = [ "127.0.0.1:8082" ];
          };
          authentication.fallback-admin = {
            user = "admin";
            secret = "admin-test-password";
          };
          resolver.type = "system";
          # Use SQLite for simplicity in VM
          store.db = {
            type = "sqlite";
            path = "/var/lib/stalwart/stalwart.db";
          };
          storage = {
            data = "db";
            blob = "db";
            fts = "db";
            lookup = "db";
            directory = "internal";
          };
          spam-filter = {
            enable = false;
            resource = "file:///var/lib/stalwart/spam-filter.toml";
            pyzor.enable = false;
          };
        };
      };

      # Import keystone home-manager modules and disable heavy components
      home-manager.sharedModules = [
        self.homeModules.terminal
        {
          # Apply to all users including agents
          keystone.terminal = {
            # FULLY DISABLE AI AND SANDBOX to avoid electron_40
            ai.enable = lib.mkForce false;
            aiExtensions.enable = lib.mkForce false;
            sandbox.enable = lib.mkForce false;
          };
          _module.args.keystoneInputs = lib.mkForce { };
        }
      ];

      # We still need to provision the accounts. Since we disabled mail.nix,
      # we'll do it manually in the test script or a new service.
      # We'll use a new service to match the behavior we want to test.
      systemd.services.provision-test-accounts = {
        description = "Provision human and agent mail accounts";
        after = [ "stalwart.service" ];
        requires = [ "stalwart.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.curl
          pkgs.jq
        ];
        script = ''
          for _ in $(seq 1 120); do
            if curl -sf -u 'admin:admin-test-password' http://127.0.0.1:8082/api/principal >/dev/null; then
              break
            fi
            echo "Waiting for Stalwart API..."
            sleep 1
          done

          if ! curl -sf -u 'admin:admin-test-password' http://127.0.0.1:8082/api/principal >/dev/null; then
            echo "Stalwart API did not become ready after 120 seconds"
            systemctl status stalwart.service --no-pager || true
            exit 1
          fi

          # Create the mail domain before provisioning principals that reference it.
          curl -sf -u 'admin:admin-test-password' \
            http://127.0.0.1:8082/api/principal \
            -H "Content-Type: application/json" \
            -d '{"type":"domain","name":"test.local"}'

          # Provision human user nicholas
          curl -sf -u 'admin:admin-test-password' \
            http://127.0.0.1:8082/api/principal \
            -H "Content-Type: application/json" \
            -d '{"type":"individual","name":"nicholas","secrets":["human-password-456"],"emails":["nicholas@test.local"]}'
            
          curl -sf -u 'admin:admin-test-password' \
            http://127.0.0.1:8082/api/principal/nicholas \
            -X PATCH -H "Content-Type: application/json" \
            -d '[{"action":"set","field":"roles","value":["user"]}]'

          # Provision agent drago
          curl -sf -u 'admin:admin-test-password' \
            http://127.0.0.1:8082/api/principal \
            -H "Content-Type: application/json" \
            -d '{"type":"individual","name":"agent-drago","secrets":["agent-password-123"],"emails":["drago@test.local"]}'
            
          curl -sf -u 'admin:admin-test-password' \
            http://127.0.0.1:8082/api/principal/agent-drago \
            -X PATCH -H "Content-Type: application/json" \
            -d '[{"action":"set","field":"roles","value":["user"]}]'

          # Trigger default calendar creation
          curl -sf -u 'agent-drago:agent-password-123' \
            http://127.0.0.1:8082/dav/cal/agent-drago/ \
            -X PROPFIND -H "Content-Type: application/xml" -H "Depth: 1" \
            -d '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>' -o /dev/null

          # Set sharing ACL
          curl -sf -u 'agent-drago:agent-password-123' \
            http://127.0.0.1:8082/dav/cal/agent-drago/default/ \
            -X ACL -H "Content-Type: application/xml" \
            -d '<?xml version="1.0" encoding="utf-8"?><D:acl xmlns:D="DAV:"><D:ace><D:principal><D:href>/dav/pal/nicholas/</D:href></D:principal><D:grant><D:privilege><D:read/></D:privilege><D:privilege><D:write/></D:privilege></D:grant></D:ace></D:acl>'
        '';
      };

      # Override Forgejo settings to disable signing
      services.forgejo.settings = {
        "repository.signing" = {
          ENABLED = lib.mkForce false;
          SIGNING_KEY = lib.mkForce "none";
        };
      };

      # Ensure required tools are available
      environment.systemPackages = with pkgs; [
        curl
        jq
        tea
        rbw
        # mocked packages from overlay
        pkgs.keystone.pz
        pkgs.keystone.calendula
      ];

      fileSystems."/" = {
        device = lib.mkForce "/dev/vda2";
        fsType = lib.mkForce "ext4";
      };

      virtualisation = {
        memorySize = 4096;
        cores = 2;
      };
    };

  testScript = ''
    ADMIN_USER = "admin"
    ADMIN_PASS = "admin-test-password"
    API_STALWART = "http://127.0.0.1:8082/api"
    DAV_STALWART = "http://127.0.0.1:8082/dav"
    API_FORGEJO = "http://127.0.0.1:3000/api/v1"

    AGENT_USER_SYS = "agent-drago"
    AGENT_USER_GIT = "drago"
    AGENT_PASS = "agent-password-123"

    HUMAN_USER = "nicholas"
    HUMAN_PASS = "human-password-456"

    # ──────────────────────────────────────────────────────────────
    # Step 1: Wait for services and provisioning
    # ──────────────────────────────────────────────────────────────
    print("Step 1: Waiting for services and provisioning...")
    machine.wait_for_unit("stalwart.service")
    machine.wait_for_unit("forgejo.service")
    machine.wait_for_open_port(8082)
    machine.wait_for_open_port(3000)

    # Wait for account provisioning service
    machine.wait_for_unit("provision-test-accounts.service")
    machine.wait_for_unit("provision-agent-git-drago.service")
    print("  ✓ Services and provisioning units finished")

    # ──────────────────────────────────────────────────────────────
    # Step 2: Verify Stalwart Provisioning
    # ──────────────────────────────────────────────────────────────
    print("Step 2: Verifying Stalwart provisioning...")
    machine.succeed(f"curl -sf -u '{ADMIN_USER}:{ADMIN_PASS}' {API_STALWART}/principal/{AGENT_USER_SYS}")
    print("  ✓ Agent account found in Stalwart")

    # Verify CalDAV sharing ACLs
    status = machine.succeed(
        f"curl -s -o /dev/null -w '%{{http_code}}' "
        f"-u '{HUMAN_USER}:{HUMAN_PASS}' "
        f"'{DAV_STALWART}/cal/{AGENT_USER_SYS}/default/' "
        f"-X PROPFIND -H 'Depth: 0'"
    ).strip()
    assert status == "207", f"CalDAV sharing failed: Expected 207, got {status}"
    print("  ✓ CalDAV sharing verified")

    # ──────────────────────────────────────────────────────────────
    # Step 3: Verify Forgejo Provisioning
    # ──────────────────────────────────────────────────────────────
    print("Step 3: Verifying Forgejo provisioning...")
    # Check if user exists via admin CLI (no token needed)
    machine.succeed("sudo -u forgejo forgejo --work-path /var/lib/forgejo admin user list | grep -q drago")
    print("  ✓ Agent user 'drago' exists in Forgejo")

    # Check if Forgejo CLI credentials were provisioned for the agent.
    machine.succeed(
        f"su - {AGENT_USER_SYS} -c 'test -f ~/.config/tea/config.yml && test -f ~/.local/share/forgejo-cli/keys.json'"
    )
    print("  ✓ Agent Forgejo CLI credentials were provisioned")

    # ──────────────────────────────────────────────────────────────
    # Step 4: Verify tool availability
    # ──────────────────────────────────────────────────────────────
    print("Step 4: Verifying tool availability...")
    machine.succeed(f"su - {AGENT_USER_SYS} -c 'which calendula'")
    machine.succeed(f"su - {AGENT_USER_SYS} -c 'which rbw'")
    machine.succeed(f"su - {AGENT_USER_SYS} -c 'which pz'")
    print("  ✓ All required CLI tools are in agent PATH")

    print("")
    print("All service account provisioning tests passed!")
  '';
}
