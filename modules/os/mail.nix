{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.os.mail;
in {
  options.keystone.os.mail = {
    enable = mkEnableOption "Keystone Mail Server (Stalwart)";
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
          tls = {
            enable = true;
            implicit = true;
          };
          listener = {
            # SMTP for mail delivery (port 25)
            smtp = {
              protocol = "smtp";
              bind = ["[::]:25"];
            };
            # SMTP Submission with TLS (port 465)
            submissions = {
              protocol = "smtp";
              bind = ["[::]:465"];
              tls.implicit = true;
            };
            # SMTP Submission (port 587)
            submission = {
              protocol = "smtp";
              bind = ["[::]:587"];
            };
            # IMAPS (port 993)
            imaps = {
              protocol = "imap";
              bind = ["[::]:993"];
              tls.implicit = true;
            };
            # JMAP/Management interface (localhost only)
            jmap = {
              protocol = "http";
              bind = ["127.0.0.1:8080"];
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
        session = {
          rcpt = {
            directory = "internal";
          };
          auth = {
            directory = "internal";
            mechanisms = [
              "PLAIN"
              "LOGIN"
            ];
          };
        };

        # Queue configuration
        queue = {
          outbound = {
            next-hop = "local";
          };
        };

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

        # Spam filter - disabled to avoid missing file error
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
