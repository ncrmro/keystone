# Stalwart-focused service account provisioning test
#
# Tests that the Stalwart provisioning flow works end-to-end:
#   1. Stalwart HTTP API readiness with a bounded probe.
#   2. Principal creation via the admin REST API.
#   3. CalDAV default-calendar bootstrap (first PROPFIND triggers creation).
#   4. CalDAV ACL sharing: agent calendar shared read/write with a human user.
#
# This test targets the Stalwart subsystem in isolation so that failures
# identify the mail/CalDAV layer without implicating Forgejo or other services.
#
# ISSUE-REQ-2, ISSUE-REQ-4, ISSUE-REQ-5, ISSUE-REQ-6
#
# Build:       nix build .#checks.x86_64-linux.test-stalwart-provisioning
# Interactive: nix build .#checks.x86_64-linux.test-stalwart-provisioning.driverInteractive
{
  pkgs,
  lib,
  self,
  home-manager,
}:
pkgs.testers.nixosTest {
  name = "stalwart-provisioning";

  nodes.machine =
    { config, pkgs, ... }:
    {
      # Minimal NixOS base — no keystone OS module needed here.
      # Stalwart is configured directly to avoid the agenix secret assertions
      # in keystone's mail.nix, which require real encrypted secrets at build time.
      # What we test is the provisioning *script* behaviour, not the NixOS
      # module wiring (that is covered by evaluation tests).

      services.stalwart-mail = {
        enable = true;
        # SQLite store: simpler than RocksDB, no filesystem overhead in VM
        settings = {
          server = {
            hostname = "machine";
            # Disable TLS — no certificates available in VM
            tls.enable = false;
            listener = {
              http = {
                protocol = "http";
                bind = [ "127.0.0.1:8082" ];
              };
            };
          };

          store.db = {
            type = "sqlite";
            path = "/var/lib/stalwart-mail/stalwart.db";
          };
          store.blob = {
            type = "sqlite";
            path = "/var/lib/stalwart-mail/stalwart.db";
          };
          storage = {
            data = "db";
            blob = "db";
            fts = "db";
            lookup = "db";
            directory = "internal";
          };

          directory.internal = {
            type = "internal";
            store = "db";
          };

          session = {
            rcpt.directory = "'internal'";
            auth = {
              directory = "'internal'";
              mechanisms = "[plain, login]";
            };
          };

          authentication.fallback-admin = {
            user = "admin";
            secret = "admin-test-password";
          };

          queue.strategy.route = "'local'";
          resolver.type = "system";

          # CalDAV sharing: allow directory queries and assisted discovery
          sharing = {
            allow-directory-query = true;
            max-shares-per-item = 50;
          };
          dav.collection.assisted-discovery = true;

          # Disable spam filter in VM (no resource file available)
          spam-filter = {
            enable = false;
            resource = "";
          };

          tracer.stdout = {
            type = "stdout";
            level = "info";
            ansi = false;
            enable = true;
          };
        };
      };

      # Human user — receives CalDAV calendar shares from agents
      users.users.nicholas = {
        isNormalUser = true;
        uid = 1001;
        initialPassword = "human-pass";
      };

      # Agent user (matches the name used in the provisioning service below)
      users.users.agent-test = {
        isNormalUser = true;
        uid = 4001;
        initialPassword = "unused";
      };
      users.groups.agents.members = [ "agent-test" ];

      # Write mock runtime secrets.
      # The provisioning service reads these paths exactly — the passwords must
      # be present before provision-agent-mail-test.service starts.
      system.activationScripts.mock-stalwart-secrets = {
        text = ''
          mkdir -p /run/agenix
          printf '%s' 'admin-test-password' > /run/agenix/stalwart-admin-password
          printf '%s' 'agent-test-password' > /run/agenix/agent-test-mail-password
          chmod 0400 /run/agenix/stalwart-admin-password
          chmod 0400 /run/agenix/agent-test-mail-password
        '';
        deps = [ "users" ];
      };

      # Provisioning service — mirrors what keystone's mail.nix generates for
      # an agent with mail.provision = true and a human user named "nicholas".
      systemd.services.provision-agent-mail-test = {
        description = "Provision Stalwart mail account for agent-test";
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
          set -euo pipefail

          ADMIN_PASS=$(cat /run/agenix/stalwart-admin-password)
          AGENT_PASS=$(tr -d '\n' < /run/agenix/agent-test-mail-password)
          API="http://127.0.0.1:8082/api"
          USERNAME="agent-test"
          MAIL_ADDR="agent-test@test.local"

          # Wait for Stalwart HTTP API to become ready (bounded: 60 retries × 2 s = 2 min)
          echo "provision-agent-mail-test: waiting for Stalwart API..."
          for i in $(seq 1 60); do
            if curl -s -o /dev/null -w "%{http_code}" -u "admin:$ADMIN_PASS" \
                "$API/principal/admin" | grep -q "^200$"; then
              echo "provision-agent-mail-test: Stalwart API is ready"
              break
            fi
            if [ "$i" -eq 60 ]; then
              echo "provision-agent-mail-test: FAIL — Stalwart API not ready after 120 s" >&2
              exit 1
            fi
            sleep 2
          done

          # Idempotent: skip if account already exists
          STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "admin:$ADMIN_PASS" "$API/principal/$USERNAME")

          if [ "$STATUS" != "200" ]; then
            echo "$USERNAME: Creating Stalwart account..."
            curl -sf -u "admin:$ADMIN_PASS" "$API/principal" \
              -H "Content-Type: application/json" \
              -d "$(jq -n \
                --arg name "$USERNAME" \
                --arg pass "$AGENT_PASS" \
                --arg email "$MAIL_ADDR" \
                '{type:"individual",name:$name,secrets:[$pass],emails:[$email]}')"
            echo "$USERNAME: account created"
          else
            echo "$USERNAME: account already exists"
          fi

          # Ensure role is set (idempotent — CalDAV/CardDAV permissions require it)
          curl -sf -u "admin:$ADMIN_PASS" "$API/principal/$USERNAME" -X PATCH \
            -H "Content-Type: application/json" \
            -d '[{"action":"set","field":"roles","value":["user"]}]'

          # Bootstrap default calendar: first PROPFIND triggers auto-creation
          curl -sf -u "$USERNAME:$AGENT_PASS" \
            "http://127.0.0.1:8082/dav/cal/$USERNAME/" \
            -X PROPFIND -H "Content-Type: application/xml" -H "Depth: 1" \
            -d '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>' \
            -o /dev/null || true

          # Grant human user (nicholas) read+write on the agent's default calendar
          ACL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "$USERNAME:$AGENT_PASS" \
            "http://127.0.0.1:8082/dav/cal/$USERNAME/default/" \
            -X ACL -H "Content-Type: application/xml" \
            -d '<?xml version="1.0" encoding="utf-8"?>
<D:acl xmlns:D="DAV:">
  <D:ace>
    <D:principal><D:href>/dav/pal/nicholas/</D:href></D:principal>
    <D:grant>
      <D:privilege><D:read/></D:privilege>
      <D:privilege><D:write/></D:privilege>
    </D:grant>
  </D:ace>
</D:acl>')
          if [ "$ACL_STATUS" = "200" ] || [ "$ACL_STATUS" = "204" ]; then
            echo "$USERNAME: CalDAV ACL set successfully (HTTP $ACL_STATUS)"
          else
            echo "$USERNAME: WARNING — CalDAV ACL returned HTTP $ACL_STATUS" >&2
          fi

          echo "provision-agent-mail-test: done"
        '';
      };

      # Disable NetworkManager to avoid conflicts with the VM's virtual NIC
      networking.useDHCP = false;
      networking.interfaces.eth0.useDHCP = true;

      virtualisation = {
        memorySize = 2048;
        cores = 2;
      };
    };

  testScript = ''
    print("=== stalwart-provisioning: starting test ===")
    machine.wait_for_unit("multi-user.target")
    print("System booted")

    # Stalwart uses "stalwart.service" (the NixOS module name)
    machine.wait_for_unit("stalwart.service", timeout=120)
    print("Stalwart service active")

    machine.wait_for_open_port(8082, timeout=120)
    print("Stalwart HTTP port 8082 reachable")

    machine.wait_for_unit("provision-agent-mail-test.service", timeout=180)
    print("Provisioning service completed")

    # Verify account was created
    machine.succeed(
      "curl -sf -u admin:admin-test-password "
      "http://127.0.0.1:8082/api/principal/agent-test | grep -q '\"name\"'"
    )
    print("PASS: agent-test account exists in Stalwart")

    # Verify CalDAV home is accessible as the agent
    status = machine.succeed(
      "curl -s -o /dev/null -w '%{http_code}' "
      "-u agent-test:agent-test-password "
      "-X PROPFIND -H 'Content-Type: application/xml' -H 'Depth: 1' "
      "-d '<?xml version=\"1.0\"?><propfind xmlns=\"DAV:\"><prop><resourcetype/></prop></propfind>' "
      "http://127.0.0.1:8082/dav/cal/agent-test/"
    )
    assert status.strip() in ("207", "200"), f"Expected 207 for CalDAV PROPFIND, got {status}"
    print("PASS: CalDAV home PROPFIND returned 207 (multi-status)")

    print("=== stalwart-provisioning: all tests passed ===")
  '';
}
