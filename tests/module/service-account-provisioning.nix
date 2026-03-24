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
          gitServer.enable = true;

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

        # Set hostname to match services
        services.mail.host = "machine";
        services.git.host = "machine";
      };

      networking.hostName = "machine";

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

      # Mock problem packages at node level
      nixpkgs.overlays = [
        (final: prev: {
          keystone = prev.keystone // {
            auto-claude =
              final.runCommand "mock-auto-claude" { }
                "mkdir -p $out/bin; touch $out/bin/auto-claude; chmod +x $out/bin/auto-claude";
          };
        })
      ];

      # Override Stalwart settings for the test environment (no TLS, localhost)
      services.stalwart-mail.settings = {
        server.tls.enable = false;
        server.listener.http = {
          protocol = "http";
          bind = [ "127.0.0.1:8082" ];
        };
        authentication.fallback-admin = {
          user = "admin";
          secret = "admin-test-password";
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
    import json

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

    # Wait for agent provisioning services
    machine.wait_for_unit("provision-agent-mail-drago.service")
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
    machine.succeed("sudo -u forgejo forgejo admin user list | grep -q drago")
    print("  ✓ Agent user 'drago' exists in Forgejo")

    # Check if repo exists
    # Provisioning creates 'agent-space' by default
    machine.succeed(f"su - {AGENT_USER_SYS} -c 'tea repo list | grep -q agent-space'")
    print("  ✓ Agent repo 'agent-space' listed via tea CLI")

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
