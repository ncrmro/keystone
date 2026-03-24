# Service account provisioning test
#
# Verifies the end-to-end flow of agent service account provisioning:
#   1. Stalwart mail server setup and REST API readiness.
#   2. Automatic creation of agent accounts via NixOS activation.
#   3. Automatic CalDAV calendar creation and sharing ACLs.
#   4. PIM CLI tools (calendula) auto-auth for agents.
#
# Build:       nix build .#checks.x86_64-linux.test-service-account-provisioning
# Interactive: nix build .#checks.x86_64-linux.test-service-account-provisioning.driverInteractive
#
{
  pkgs,
  lib,
  self,
}:
pkgs.testers.nixosTest {
  name = "service-account-provisioning";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [
        self.nixosModules.operating-system
      ];

      # Configure Keystone
      keystone = {
        domain = "test.local";
        os = {
          enable = true;
          # Machine acts as its own mail server for testing
          mail.allowedIps = [ "127.0.0.1" ];

          # Define a human user (receives calendar shares)
          users.nicholas = {
            fullName = "Nicholas Romero";
            initialPassword = "human-password-456";
          };

          # Define an agent with mail provisioning enabled
          agents.drago = {
            fullName = "Drago Agent";
            terminal.enable = true;
            mail.provision = true;
          };

          # Minimal storage for evaluation
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
        };

        # Set hostname to match mail host
        services.mail.host = "machine";
      };

      networking.hostName = "machine";

      # Register the host in keystone.hosts to satisfy assertions
      keystone.hosts.machine = {
        hostname = "machine";
        role = "server";
      };

      # Disable secret assertions for the test — we mock them via activation script
      # because agenix doesn't run during nixosTest evaluation.
      # We do this by declaring the secrets in age.secrets to satisfy the module's ? check.
      age.secrets = {
        stalwart-admin-password.file = "/dev/null";
        agent-drago-mail-password.file = "/dev/null";
      };

      # Mock agenix secrets for provisioning
      # The provisioning script expects these to exist at /run/agenix/
      system.activationScripts.mock-agenix-secrets = {
        text = ''
          mkdir -p /run/agenix
          echo -n "admin-test-password" > /run/agenix/stalwart-admin-password
          echo -n "agent-password-123" > /run/agenix/agent-drago-mail-password
          chmod 400 /run/agenix/stalwart-admin-password /run/agenix/agent-drago-mail-password
        '';
        deps = [ "users" ];
      };

      # Override Stalwart settings for the test environment (no TLS, localhost)
      services.stalwart-mail.settings = {
        server.tls.enable = false;
        server.listener.http = {
          protocol = "http";
          bind = [ "127.0.0.1:8082" ];
        };
        # Set a predictable admin password for testing
        authentication.fallback-admin = {
          user = "admin";
          secret = "admin-test-password";
        };
      };

      # Ensure curl and jq are available for the test script
      environment.systemPackages = with pkgs; [
        curl
        jq
      ];

      fileSystems."/" = {
        device = lib.mkForce "/dev/vda2";
        fsType = lib.mkForce "ext4";
      };

      virtualisation = {
        memorySize = 2048;
        cores = 2;
      };
    };

  testScript = ''
    import json

    ADMIN_USER = "admin"
    ADMIN_PASS = "admin-test-password"
    API = "http://127.0.0.1:8082/api"
    DAV = "http://127.0.0.1:8082/dav"

    AGENT_USER = "agent-drago"
    AGENT_PASS = "agent-password-123"

    HUMAN_USER = "nicholas"
    HUMAN_PASS = "human-password-456"

    # ──────────────────────────────────────────────────────────────
    # Step 1: Wait for services and provisioning
    # ──────────────────────────────────────────────────────────────
    print("Step 1: Waiting for Stalwart and provisioning...")
    machine.wait_for_unit("stalwart.service")
    machine.wait_for_open_port(8082)
    machine.wait_for_unit("provision-agent-mail-drago.service")
    print("  ✓ Services are running and provisioning unit finished")

    # ──────────────────────────────────────────────────────────────
    # Step 2: Verify account existence via admin API
    # ──────────────────────────────────────────────────────────────
    print("Step 2: Verifying account creation in Stalwart...")
    machine.succeed(
        f"curl -sf -u '{ADMIN_USER}:{ADMIN_PASS}' {API}/principal/{AGENT_USER} > /dev/null"
    )
    machine.succeed(
        f"curl -sf -u '{ADMIN_USER}:{ADMIN_PASS}' {API}/principal/{HUMAN_USER} > /dev/null"
    )
    print("  ✓ Both accounts found in Stalwart directory")

    # ──────────────────────────────────────────────────────────────
    # Step 3: Verify CalDAV sharing ACLs
    # ──────────────────────────────────────────────────────────────
    print("Step 3: Verifying CalDAV ACLs...")
    # Human user should be able to PROPFIND the agent's default calendar
    status = machine.succeed(
        f"curl -s -o /dev/null -w '%{{http_code}}' "
        f"-u '{HUMAN_USER}:{HUMAN_PASS}' "
        f"'{DAV}/cal/{AGENT_USER}/default/' "
        f"-X PROPFIND -H 'Depth: 0'"
    ).strip()
    assert status == "207", f"Sharing verification failed: Expected HTTP 207, got {status}"
    print(f"  ✓ Human user '{HUMAN_USER}' has access to {AGENT_USER}'s calendar")

    # ──────────────────────────────────────────────────────────────
    # Step 4: Verify PIM CLI (calendula) auto-auth for agent
    # ──────────────────────────────────────────────────────────────
    print("Step 4: Verifying PIM CLI (calendula) auto-auth...")
    # Run calendula as the agent user.
    output = machine.succeed(
        f"su - {AGENT_USER} -c 'calendula calendars list'"
    )
    print("  Calendula output:")
    for line in output.splitlines():
        print(f"    {line}")

    assert "personal" in output.lower() or "default" in output.lower(), "Agent failed to list its calendar via calendula"
    print("  ✓ Agent authenticated successfully via calendula CLI")

    print("")
    print("All service account provisioning tests passed!")
  '';
}
