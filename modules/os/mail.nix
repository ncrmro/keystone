# TODO this should move to a dedicated server-os module at some point to delinate it from deskop (maybe)
# Keystone Mail Server (Stalwart)
#
# See conventions/tool.stalwart.md
# Implements REQ-007 (OS Agents — FR-004: Email via Stalwart)
#
# This module provides a Stalwart mail server configuration with:
# - Prometheus metrics on 127.0.0.1:9010 (default-on, see conventions/tool.stalwart.md)
# - Per-agent CalDAV calendar + CardDAV addressbook provisioning at system activation
# - Team principal with shared calendar/addressbook + per-agent ACL grants
#
# On first boot, Stalwart generates a random admin password in the logs.
#
# ## Setting Admin Password with Agenix
#
# To use a managed admin password instead, extend this config in your host:
#
# ```nix
# # 1. Add to secrets.nix:
# "secrets/stalwart-admin-password.age".publicKeys = adminKeys ++ [ systems.yourhost ];
#
# # 2. Create the secret with a SHA-512 hashed password (NOT plaintext).
# #    fallback-admin.secret requires a $6$ hash format.
# #    Generate the hash: mkpasswd -m sha-512 "your-password"
# #    Then store it:     echo -n '$6$...' | agenix -e secrets/stalwart-admin-password.age
#
# # 3. In your host configuration:
# age.secrets.stalwart-admin-password = {
#   file = ../../secrets/stalwart-admin-password.age;
#   owner = "root";
#   mode = "0400";
# };
#
# services.stalwart-mail = {
#   credentials = {
#     admin_password = config.age.secrets.stalwart-admin-password.path;
#   };
#   settings.authentication.fallback-admin = {
#     user = "admin";
#     secret = "%{file:/run/credentials/stalwart-mail.service/admin_password}%";
#   };
# };
# ```
#
# The credentials option uses systemd's LoadCredential to securely pass
# the secret to the service, accessible via the %{file:...}% macro.
#
# ## IMAP/SMTP Client Authentication
#
# When connecting with an IMAP/SMTP client (e.g. himalaya), the login
# username is the Stalwart account **name** (e.g. "ncrmro"), NOT the
# email address. The email is only used as the envelope/from address.
#
# ## Team Resources
#
# A shared `team` principal is provisioned with a shared CalDAV calendar
# at /dav/cal/team/shared/ and CardDAV addressbook at /dav/card/team/shared/.
# All agents with mail.provision = true are granted read-write ACL on these
# resources. Requires agenix secret: stalwart-team-password.
#
# See conventions/tool.stalwart.md for full provisioning specification.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.os.mail;
  topDomain = config.keystone.domain;

  # Agents that want mail provisioning on this host (where Stalwart runs).
  # This is NOT filtered by agent.host — provisioning runs on the mail server,
  # which is typically a different host from the agent's designated host.
  #
  # CRITICAL (agenix): agent-{name}-mail-password must list BOTH the agent's
  # host (for himalaya client) AND this server's host key (for Stalwart
  # provisioning) in its publicKeys recipients. Otherwise agenix will fail
  # to decrypt at activation time on this host.
  provisionAgents = filterAttrs (_: a: a.mail.provision) config.keystone.os.agents;
  hasProvisionAgents = provisionAgents != { };

  # Sorted agent usernames for deterministic ordering in team ACL grants.
  provisionAgentUsernames = map (name: "agent-${name}") (sort lessThan (attrNames provisionAgents));

  # JMAP/admin API base URL (localhost only)
  jmapUrl = "http://127.0.0.1:8082";
  adminPasswordPath = "/run/agenix/stalwart-admin-password";
  teamPasswordPath = "/run/agenix/stalwart-team-password";
in
{
  options.keystone.os.mail = {
    allowedIps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "IP ranges to whitelist from fail2ban blocking (e.g., Tailscale ranges)";
      example = [
        "100.64.0.0/10"
        "fd7a:115c:a1e0::/48"
      ];
    };
  };

  # Auto-enable when keystone.services.mail.host matches this machine's hostname.
  # No manual `enable = true` needed — just set keystone.services.mail.host once.
  config =
    mkIf
      (
        config.keystone.services.mail.host != null
        && config.keystone.services.mail.host == config.networking.hostName
      )
      {
        services.stalwart-mail = {
          enable = true;
          package = pkgs.stalwart-mail;
          openFirewall = true;

          settings = {
            # Server configuration
            server = {
              hostname = config.networking.hostName;

              # Allow IPs to bypass fail2ban blocking
              # Using table syntax instead of set notation (NixOS can't generate { "ip" } sets)
              "allowed-ip" = lib.listToAttrs (map (ip: lib.nameValuePair ip "") cfg.allowedIps);
              tls = {
                enable = true;
                implicit = true;
              };
              listener = {
                # SMTP for mail delivery (port 25)
                smtp = {
                  protocol = "smtp";
                  bind = [ "[::]:25" ];
                };
                # SMTP Submission with TLS (port 465)
                submissions = {
                  protocol = "smtp";
                  bind = [ "[::]:465" ];
                  tls.implicit = true;
                };
                # SMTP Submission (port 587)
                submission = {
                  protocol = "smtp";
                  bind = [ "[::]:587" ];
                };
                # IMAPS (port 993)
                imaps = {
                  protocol = "imap";
                  bind = [ "[::]:993" ];
                  tls.implicit = true;
                };
                # JMAP/Management interface (localhost only)
                # Using 8082 to avoid conflict with common ingress port 8080
                # TODO: Can revert to 8080 after removing k8s ingress-nginx
                jmap = {
                  protocol = "http";
                  bind = [ "127.0.0.1:8082" ];
                };
                # Prometheus metrics (localhost only, Tailscale-accessible)
                # Default-on per conventions/tool.stalwart.md rules 1-4.
                prometheus = {
                  protocol = "http";
                  bind = [ "127.0.0.1:9010" ];
                };
              };
            };

            # Storage configuration - use RocksDB for persistence
            store = {
              db = {
                type = "rocksdb";
                path = "/var/lib/stalwart-mail/data";
              };
              blob = {
                type = "rocksdb";
                path = "/var/lib/stalwart-mail/blob";
              };
            };
            storage = {
              data = "db";
              blob = "blob";
              fts = "db";
              lookup = "db";
            };

            # Directory for user authentication
            directory = {
              internal = {
                type = "internal";
                store = "db";
              };
            };

            # Session configuration
            # Note: Directory references need single quotes for Stalwart TOML
            session = {
              rcpt = {
                directory = "'internal'";
              };
              auth = {
                directory = "'internal'";
                mechanisms = "[plain, login]";
              };
            };

            # Queue configuration - route all mail locally
            # (next-hop deprecated in v0.13.0, replaced by queue.strategy.route)
            queue.strategy.route = "'local'";

            # Resolver configuration
            resolver = {
              type = "system";
            };

            # Tracing/logging
            tracer = {
              stdout = {
                type = "stdout";
                level = "info";
                ansi = false;
                enable = true;
              };
              # Prometheus metrics endpoint — default-on per tool.stalwart rule 4.
              # Scraped by Grafana Alloy at http://127.0.0.1:9010/metrics.
              prometheus = {
                type = "prometheus";
                enable = true;
              };
            };

            # Web admin interface is configured automatically by nixpkgs
            # (sets webadmin.path to /var/cache/stalwart-mail)

            # Spam filter - disabled to avoid missing file error
            # TODO: Spam filter is currently disabled because the default `spamfilter.toml`
            # resource was not found in the Stalwart Mail package. To re-enable, either:
            # 1. Find or create a `spamfilter.toml` file and point the `resource`
            #    option to its path.
            # 2. Configure spam filtering directly within the `spam-filter` section.
            spam-filter = {
              resource = "";
            };
          };
        };

        # Firewall configuration for mail ports
        networking.firewall = {
          allowedTCPPorts = [
            25 # SMTP
            465 # SMTPS (Submission over TLS)
            587 # Submission
            993 # IMAPS
          ];
          # NOTE: Prometheus (9010) and JMAP (8082) bind to 127.0.0.1 — no firewall rule needed.
        };

        # Auto-provision Stalwart mail accounts + CalDAV/CardDAV for agents with mail.provision = true.
        # Also provisions team principal + shared resources.
        assertions = mkIf hasProvisionAgents (
          [
            {
              assertion = config.age.secrets ? "stalwart-admin-password";
              message = "Agent mail provisioning requires agenix secret 'stalwart-admin-password' for Stalwart admin API access.";
            }
            {
              assertion = config.age.secrets ? "stalwart-team-password";
              message = "Agent mail provisioning requires agenix secret 'stalwart-team-password' for the shared team principal.";
            }
          ]
          ++ (mapAttrsToList (name: _: {
            assertion = config.age.secrets ? "agent-${name}-mail-password";
            message = ''
              Agent '${name}' has mail.provision = true but agenix secret "agent-${name}-mail-password" is not declared.
              This secret must contain the plaintext password for the agent's Stalwart account.
            '';
          }) provisionAgents)
        );

        systemd.services = mkIf hasProvisionAgents (
          # Team provisioning: create team principal + shared CalDAV/CardDAV + grant all agent ACLs.
          # Runs before per-agent services so the team principal exists when agents need ACL.
          # See conventions/tool.stalwart.md rules 12-16.
          {
            provision-stalwart-team = {
              description = "Provision Stalwart team principal, shared calendar, and addressbook";
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

                ADMIN_PASS=$(cat ${adminPasswordPath})
                TEAM_PASS=$(cat ${teamPasswordPath})
                API="${jmapUrl}/api"
                JMAP="${jmapUrl}"

                # 1. Create team account if it doesn't exist.
                # Team is an individual principal with no email and no mail role
                # (calendar/contacts only — no mail delivery).
                STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                  -u "admin:$ADMIN_PASS" \
                  "$API/principal/team")

                if [ "$STATUS" != "200" ]; then
                  echo "team: Creating Stalwart team account..."
                  curl -sf -u "admin:$ADMIN_PASS" \
                    "$API/principal" \
                    -H "Content-Type: application/json" \
                    -d "$(jq -n --arg pass "$TEAM_PASS" \
                      '{type: "individual", name: "team", secrets: [$pass]}')"
                  echo "team: Stalwart team account created"
                else
                  echo "team: Stalwart account already exists"
                fi

                # 2. Create team CalDAV calendar at /dav/cal/team/shared/ (idempotent).
                # Auth as team user — Stalwart's CalDAV namespace is per-user.
                CAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                  -X PROPFIND -u "team:$TEAM_PASS" \
                  "$JMAP/dav/cal/team/shared/")

                if [ "$CAL_STATUS" = "404" ]; then
                  echo "team: Creating shared CalDAV calendar..."
                  curl -sf -X MKCALENDAR \
                    -u "team:$TEAM_PASS" \
                    -H "Content-Type: application/xml" \
                    -d '<A:mkcalendar xmlns:D="DAV:" xmlns:A="urn:ietf:params:xml:ns:caldav">
                          <D:set><D:prop><D:displayname>Team</D:displayname></D:prop></D:set>
                        </A:mkcalendar>' \
                    "$JMAP/dav/cal/team/shared/"
                  echo "team: Shared CalDAV calendar created"
                else
                  echo "team: Shared CalDAV calendar already exists (HTTP $CAL_STATUS)"
                fi

                # 3. Create team CardDAV addressbook at /dav/card/team/shared/ (idempotent).
                CARD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                  -X PROPFIND -u "team:$TEAM_PASS" \
                  "$JMAP/dav/card/team/shared/")

                if [ "$CARD_STATUS" = "404" ]; then
                  echo "team: Creating shared CardDAV addressbook..."
                  curl -sf -X MKCOL \
                    -u "team:$TEAM_PASS" \
                    -H "Content-Type: application/xml" \
                    -d '<?xml version="1.0" encoding="utf-8"?>
                        <D:mkcol xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
                          <D:set><D:prop>
                            <D:resourcetype><D:collection/><C:addressbook/></D:resourcetype>
                            <D:displayname>Team</D:displayname>
                          </D:prop></D:set>
                        </D:mkcol>' \
                    "$JMAP/dav/card/team/shared/"
                  echo "team: Shared CardDAV addressbook created"
                else
                  echo "team: Shared CardDAV addressbook already exists (HTTP $CARD_STATUS)"
                fi

                # 4. Grant each provision agent read-write ACL on team resources.
                # addItem is idempotent — Stalwart deduplicates ACL entries.
                # ACL format: "{principal}\t{permissions}" (tab-separated, rw = read-write).
                ${concatStringsSep "\n" (
                  map (username: ''
                    echo "team: Granting ${username} read-write ACL on team resources..."
                    curl -sf -u "admin:$ADMIN_PASS" \
                      "$API/principal/team" -X PATCH \
                      -H "Content-Type: application/json" \
                      -d '[{"action":"addItem","field":"acl","value":"${username}\trw"}]'
                  '') provisionAgentUsernames
                )}

                echo "team: Provisioning complete"
              '';
            };
          }

          # Per-agent provisioning: mail account + CalDAV calendar + CardDAV addressbook.
          # Runs after provision-stalwart-team so ACL grants can reference the team principal.
          # NOTE: The systemd unit is "stalwart.service" (not "stalwart-mail.service").
          # The admin password secret may be a SHA-512 hash ($6$...) — Stalwart
          # accepts hashed passwords in HTTP basic auth, so provisioning still works.
          // mapAttrs' (
            name: agentCfg:
            let
              username = "agent-${name}";
              mailAddr =
                if agentCfg.mail.address != null then agentCfg.mail.address else "${username}@${topDomain}";
              agentPasswordPath = "/run/agenix/${username}-mail-password";
            in
            nameValuePair "provision-agent-mail-${name}" {
              description = "Provision Stalwart mail account + CalDAV/CardDAV for ${username}";
              # Must run after team service so team principal exists (needed for ACL in team service,
              # and agents may reference team calendar immediately after their session starts).
              after = [
                "stalwart.service"
                "provision-stalwart-team.service"
              ];
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

                ADMIN_PASS=$(cat ${adminPasswordPath})
                AGENT_PASS=$(tr -d '\n' < ${agentPasswordPath})
                API="${jmapUrl}/api"
                JMAP="${jmapUrl}"

                # Step 1: Create mail account if it doesn't exist (idempotent).
                # NOTE: We do NOT exit early here — CalDAV/CardDAV provisioning must
                # run regardless of whether the mail account was just created or
                # already existed (e.g., after a re-deploy).
                ACCT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                  -u "admin:$ADMIN_PASS" \
                  "$API/principal/${username}")

                if [ "$ACCT_STATUS" = "200" ]; then
                  echo "${username}: Stalwart account already exists"
                else
                  echo "${username}: Creating Stalwart mail account..."

                  curl -sf -u "admin:$ADMIN_PASS" \
                    "$API/principal" \
                    -H "Content-Type: application/json" \
                    -d "$(jq -n \
                      --arg name "${username}" \
                      --arg pass "$AGENT_PASS" \
                      --arg email "${mailAddr}" \
                      '{type: "individual", name: $name, secrets: [$pass], emails: [$email]}')"

                  # Set role to user
                  curl -sf -u "admin:$ADMIN_PASS" \
                    "$API/principal/${username}" -X PATCH \
                    -H "Content-Type: application/json" \
                    -d '[{"action":"set","field":"roles","value":["user"]}]'

                  echo "${username}: Stalwart mail account created"
                fi

                # Step 2: Create personal CalDAV calendar at /dav/cal/{username}/personal/ (idempotent).
                # Auth as agent — Stalwart's CalDAV namespace is per-user; admin auth is not valid.
                # See conventions/tool.stalwart.md rules 5-8.
                CAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                  -X PROPFIND -u "${username}:$AGENT_PASS" \
                  "$JMAP/dav/cal/${username}/personal/")

                if [ "$CAL_STATUS" = "404" ]; then
                  echo "${username}: Creating personal CalDAV calendar..."
                  curl -sf -X MKCALENDAR \
                    -u "${username}:$AGENT_PASS" \
                    -H "Content-Type: application/xml" \
                    -d '<A:mkcalendar xmlns:D="DAV:" xmlns:A="urn:ietf:params:xml:ns:caldav">
                          <D:set><D:prop><D:displayname>Personal</D:displayname></D:prop></D:set>
                        </A:mkcalendar>' \
                    "$JMAP/dav/cal/${username}/personal/"
                  echo "${username}: CalDAV calendar created"
                else
                  echo "${username}: CalDAV calendar already exists (HTTP $CAL_STATUS)"
                fi

                # Step 3: Create personal CardDAV addressbook at /dav/card/{username}/personal/ (idempotent).
                # See conventions/tool.stalwart.md rules 9-11.
                CARD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                  -X PROPFIND -u "${username}:$AGENT_PASS" \
                  "$JMAP/dav/card/${username}/personal/")

                if [ "$CARD_STATUS" = "404" ]; then
                  echo "${username}: Creating personal CardDAV addressbook..."
                  curl -sf -X MKCOL \
                    -u "${username}:$AGENT_PASS" \
                    -H "Content-Type: application/xml" \
                    -d '<?xml version="1.0" encoding="utf-8"?>
                        <D:mkcol xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
                          <D:set><D:prop>
                            <D:resourcetype><D:collection/><C:addressbook/></D:resourcetype>
                            <D:displayname>Personal</D:displayname>
                          </D:prop></D:set>
                        </D:mkcol>' \
                    "$JMAP/dav/card/${username}/personal/"
                  echo "${username}: CardDAV addressbook created"
                else
                  echo "${username}: CardDAV addressbook already exists (HTTP $CARD_STATUS)"
                fi

                echo "${username}: Provisioning complete"
              '';
            }
          ) provisionAgents
        );
      };
}
