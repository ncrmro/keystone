{
  lib,
  config,
  pkgs,
  pkgs-unstable ? pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.mail-server;
in {
  options.keystone.mail-server = {
    enable = mkEnableOption "Keystone mail server using Stalwart";

    hostname = mkOption {
      type = types.str;
      example = "mail.example.com";
      description = "The hostname for the mail server";
    };

    primaryDomain = mkOption {
      type = types.str;
      example = "example.com";
      description = "The primary domain for email addresses";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open firewall ports for mail services";
    };

    acmeEmail = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "admin@example.com";
      description = "Email address for ACME certificate registration. If null, certificates must be managed manually.";
    };

    package = mkOption {
      type = types.package;
      description = "The stalwart-mail package to use";
    };
  };

  config = mkIf cfg.enable {
    # Use stalwart-mail from unstable via module arg
    keystone.mail-server.package = mkDefault pkgs-unstable.stalwart-mail;

    # Enable Stalwart mail service
    services.stalwart-mail = {
      enable = true;
      package = cfg.package;

      settings = {
        server = {
          hostname = cfg.hostname;

          listener = {
            # SMTP listeners
            "smtp" = {
              bind = ["[::]:25"];
              protocol = "smtp";
            };
            "submission" = {
              bind = ["[::]:587"];
              protocol = "smtp";
            };
            "submissions" = {
              bind = ["[::]:465"];
              protocol = "smtp";
              tls.implicit = true;
            };

            # IMAP listeners
            "imap" = {
              bind = ["[::]:143"];
              protocol = "imap";
            };
            "imaps" = {
              bind = ["[::]:993"];
              protocol = "imap";
              tls.implicit = true;
            };

            # HTTP/JMAP/Admin listener
            "https" = {
              bind = ["[::]:443"];
              protocol = "http";
              tls.implicit = true;
            };

            # Management interface
            "management" = {
              bind = ["127.0.0.1:8080"];
              protocol = "http";
            };
          };
        };

        # TLS configuration
        certificate."default" = mkIf (cfg.acmeEmail != null) {
          cert = "%{file:/var/lib/acme/${cfg.hostname}/cert.pem}%";
          private-key = "%{file:/var/lib/acme/${cfg.hostname}/key.pem}%";
        };

        # Storage configuration
        storage = {
          data = "rocksdb";
          blob = "rocksdb";
          lookup = "rocksdb";
          fts = "rocksdb";
        };

        store."rocksdb" = {
          type = "rocksdb";
          path = "/var/lib/stalwart-mail/data";
          compression = "lz4";
        };

        # Directory configuration - using internal directory by default
        directory."default" = {
          type = "internal";
          store = "rocksdb";
        };

        # Session and queue settings
        session.rcpt = {
          directory = "default";
        };

        queue = {
          schedule = {
            retry = ["2s" "5s" "10s" "30s" "1m" "5m" "10m" "30m" "1h" "2h"];
          };
        };
      };
    };

    # ACME certificate configuration
    security.acme = mkIf (cfg.acmeEmail != null) {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;

      certs."${cfg.hostname}" = {
        group = "stalwart-mail";
        reloadServices = ["stalwart-mail"];
      };
    };

    # Ensure stalwart-mail user has access to certificates
    users.users.stalwart-mail = mkIf (cfg.acmeEmail != null) {
      extraGroups = ["acme"];
    };

    # Firewall configuration
    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        25   # SMTP
        587  # Submission
        465  # Submissions (SMTPS)
        143  # IMAP
        993  # IMAPS
        443  # HTTPS (JMAP & Admin)
      ];
    };

    # Ensure data directory exists with correct permissions
    systemd.tmpfiles.rules = [
      "d /var/lib/stalwart-mail 0750 stalwart-mail stalwart-mail -"
      "d /var/lib/stalwart-mail/data 0750 stalwart-mail stalwart-mail -"
    ];

    # DNS configuration hints for users
    # These are not automatically configured - users must set these DNS records manually
    warnings = [
      ''
        Mail server is enabled for ${cfg.hostname}.

        Ensure the following DNS records are configured:

        A/AAAA records:
          ${cfg.hostname}. IN A <your-ipv4>
          ${cfg.hostname}. IN AAAA <your-ipv6>

        MX record:
          ${cfg.primaryDomain}. IN MX 10 ${cfg.hostname}.

        SPF record:
          ${cfg.primaryDomain}. IN TXT "v=spf1 mx -all"

        DKIM and DMARC records should be configured after initial setup.
        Refer to Stalwart documentation for DKIM key generation.

        Management interface available at: http://localhost:8080
        ${optionalString (cfg.acmeEmail != null) "HTTPS interface available at: https://${cfg.hostname}"}
      ''
    ];
  };
}
