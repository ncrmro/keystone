# Offline service-account startup regression test
#
# Verifies that service-account-related services reach a provisioned state
# when the VM has no outbound internet access. Catches regressions where
# startup daemons block on DNS lookups, DERP relay connections, or external
# API calls absent in a no-egress environment.
#
# Services under test:
#   - Forgejo (git server) + agent user provisioning via provision-agent-git.sh
#   - Stalwart (mail server) + agent account provisioning (inline script)
#
# Both services are configured directly to avoid unrelated agenix assertions
# from the keystone mail-client module. The Forgejo provisioning uses the
# actual script from the keystone source tree; Stalwart provisioning uses
# an inline script mirroring mail.nix behaviour.
#
# ISSUE-REQ-9, ISSUE-REQ-10, ISSUE-REQ-11
#
# Build:       nix build .#checks.x86_64-linux.test-service-account-offline
# Interactive: nix build .#checks.x86_64-linux.test-service-account-offline.driverInteractive
{
  pkgs,
  lib,
  self,
  home-manager,
}:
pkgs.testers.nixosTest {
  name = "service-account-offline";

  nodes.machine =
    { config, pkgs, ... }:
    {
      # ---------- Forgejo (direct config) ----------
      services.forgejo = {
        enable = true;
        package = pkgs.forgejo;
        stateDir = "/var/lib/forgejo";
        settings = {
          server = {
            DOMAIN = "machine";
            ROOT_URL = "http://machine:3000/";
            HTTP_PORT = 3000;
            SSH_PORT = 2222;
            START_SSH_SERVER = true;
          };
          database.DB_TYPE = "sqlite3";
          repository.ROOT = "/var/lib/forgejo/repositories";
          service = {
            DISABLE_REGISTRATION = false;
            REQUIRE_SIGNIN_VIEW = false;
          };
          actions.ENABLED = false;
          security.INSTALL_LOCK = true;
        };
      };

      # ---------- Stalwart (direct config) ----------
      services.stalwart-mail = {
        enable = true;
        settings = {
          server = {
            hostname = "machine";
            tls.enable = false;
            listener.http = {
              protocol = "http";
              bind = [ "127.0.0.1:8082" ];
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
            secret = "offline-admin-pass";
          };
          queue.strategy.route = "'local'";
          resolver.type = "system";
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

      # ---------- Users ----------
      users.users.agent-test = {
        isNormalUser = true;
        uid = 4001;
        home = "/home/agent-test";
        createHome = true;
        initialPassword = "unused";
        shell = pkgs.bash;
      };
      users.groups.agents = {
        members = [ "agent-test" ];
      };

      system.activationScripts.mock-offline-secrets = {
        text = ''
          mkdir -p /run/agenix
          printf '%s' 'offline-admin-pass'   > /run/agenix/stalwart-admin-password
          printf '%s' 'offline-agent-pass'   > /run/agenix/agent-test-mail-password
          chmod 0400 /run/agenix/*
        '';
        deps = [ "users" ];
      };

      # ---------- Stalwart provisioning ----------
      systemd.services.provision-agent-mail-offline = {
        description = "Offline: provision Stalwart account for agent-test";
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

          # Bounded readiness probe — explicit failure after 120 s (ISSUE-REQ-11)
          echo "provision-offline: waiting for Stalwart API (no-egress)..."
          for i in $(seq 1 60); do
            if curl -s -o /dev/null -w "%{http_code}" -u "admin:$ADMIN_PASS" \
                "$API/principal/admin" | grep -q "^200$"; then
              echo "provision-offline: Stalwart API ready"
              break
            fi
            if [ "$i" -eq 60 ]; then
              echo "provision-offline: FAIL — Stalwart not ready after 120 s" >&2
              exit 1
            fi
            sleep 2
          done

          STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "admin:$ADMIN_PASS" "$API/principal/$USERNAME")
          if [ "$STATUS" != "200" ]; then
            curl -sf -u "admin:$ADMIN_PASS" "$API/principal" \
              -H "Content-Type: application/json" \
              -d "$(jq -n \
                --arg name "$USERNAME" \
                --arg pass "$AGENT_PASS" \
                --arg email "$USERNAME@test.local" \
                '{type:"individual",name:$name,secrets:[$pass],emails:[$email]}')"
            echo "provision-offline: $USERNAME created"
          else
            echo "provision-offline: $USERNAME already exists"
          fi
          echo "provision-offline: done"
        '';
      };

      # ---------- Forgejo provisioning (real script from keystone source) ----------
      system.activationScripts.create-forgejo-cli-dirs = {
        text = ''
          mkdir -p /home/agent-test/.config/tea
          mkdir -p /home/agent-test/.local/share/forgejo-cli
          echo '{"logins":[{"name":"forgejo","url":"http://machine:3000","token":"","default":true,"ssh_host":"machine","ssh_key":"~/.ssh/id_ed25519","ssh_agent":true,"version_check":false,"user":"test"}],"preferences":{"editor":false,"flag_defaults":{"remote":""}}}' \
            > /home/agent-test/.config/tea/config.yml
          echo '{"hosts":{},"aliases":{"machine:2222":"machine"},"default_ssh":[]}' \
            > /home/agent-test/.local/share/forgejo-cli/keys.json
          chown -R agent-test:agents /home/agent-test/.config /home/agent-test/.local
          chmod 0600 /home/agent-test/.config/tea/config.yml
          chmod 0600 /home/agent-test/.local/share/forgejo-cli/keys.json
        '';
        deps = [ "users" ];
      };

      systemd.services.provision-agent-git-offline = {
        description = "Offline: provision Forgejo user for agent-test";
        after = [ "forgejo.service" ];
        requires = [ "forgejo.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.forgejo
          pkgs.curl
          pkgs.jq
          pkgs.coreutils
          pkgs.sudo
          pkgs.yq-go
        ];
        environment = {
          FORGEJO_USER = "forgejo";
          STATE_DIR = "/var/lib/forgejo";
          API_URL = "http://127.0.0.1:3000/api/v1";
          USERNAME = "test";
          EMAIL = "agent-test@test.local";
          REPO_NAME = "notes";
          AGENT_NAME = "test";
          DOMAIN = "machine";
          AGENT_PUBKEY = "";
          ADMIN_USERS_JSON = "[]";
        };
        script = builtins.readFile "${self}/modules/os/git-server/scripts/provision-agent-git.sh";
      };

      environment.systemPackages = [
        pkgs.forgejo
        pkgs.git
      ];

      # ---------- Network: block outbound (simulate no-egress) ----------
      networking.useDHCP = false;
      networking.interfaces.eth0.useDHCP = true;
      networking.firewall.enable = true;
      # Drop outbound except localhost and the VM's host gateway
      networking.firewall.extraCommands = ''
        iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT
        iptables -A OUTPUT -d 10.0.2.0/24 -j ACCEPT
        iptables -A OUTPUT -j DROP
      '';

      virtualisation = {
        memorySize = 3072;
        cores = 2;
      };
    };

  testScript = ''
    print("=== service-account-offline: starting test ===")
    machine.wait_for_unit("multi-user.target")
    print("System booted in no-egress mode")

    # Forgejo must start without outbound internet (ISSUE-REQ-10)
    machine.wait_for_unit("forgejo.service", timeout=180)
    machine.wait_for_open_port(3000, timeout=120)
    print("PASS: Forgejo started in no-egress mode")

    # Stalwart must start without outbound internet (ISSUE-REQ-10)
    machine.wait_for_unit("stalwart.service", timeout=180)
    machine.wait_for_open_port(8082, timeout=120)
    print("PASS: Stalwart started in no-egress mode")

    # Both provisioning services must complete (ISSUE-REQ-9)
    machine.wait_for_unit("provision-agent-git-offline.service", timeout=300)
    print("PASS: Forgejo agent provisioning completed in no-egress mode")

    machine.wait_for_unit("provision-agent-mail-offline.service", timeout=300)
    print("PASS: Stalwart agent provisioning completed in no-egress mode")

    print("=== service-account-offline: all tests passed ===")
  '';
}
