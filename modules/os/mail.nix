# TODO this should move to a dedicated server-os module at some point to delinate it from deskop (maybe)
# Keystone Mail Server (Stalwart)
#
# This module provides a basic Stalwart mail server configuration.
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
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.os.mail;
in
{
  options.keystone.os.mail = {
    enable = mkEnableOption "Keystone Mail Server (Stalwart)";

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

  config = mkIf cfg.enable {
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
    };
  };
}
