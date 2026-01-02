# Keystone Git Server Module
#
# Provides a self-hosted git server using Forgejo (Gitea fork):
# - Web-based repository management
# - Issue tracking and pull requests
# - CI/CD integration (via Actions/Runners)
# - User authentication and access control
#
# TODO: Investigate Forgejo Runner integration
# - Forgejo Runner is the CI/CD runner for Forgejo Actions (GitHub Actions compatible)
# - Need to determine compute backend options:
#   * Native systemd services (simple, local execution)
#   * Docker containers (isolation, flexibility)
#   * Kubernetes pods (if keystone.server.vpn or monitoring uses K8s)
#   * MicroVMs (matches keystone.agent sandbox pattern)
# - Consider security implications of runner execution environments
# - Evaluate resource allocation and scaling strategies
# - Research integration with existing keystone infrastructure patterns
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.os.gitServer;
in {
  options.keystone.os.gitServer = {
    enable = mkEnableOption "Git server with Forgejo (self-hosted Gitea fork)";

    domain = mkOption {
      type = types.str;
      default = config.networking.hostName;
      example = "git.example.com";
      description = "Domain name for the git server";
    };

    httpPort = mkOption {
      type = types.port;
      default = 3000;
      description = "HTTP port for Forgejo web interface";
    };

    sshPort = mkOption {
      type = types.port;
      default = 2222;
      description = "SSH port for git operations (separate from system SSH)";
    };

    database = {
      type = mkOption {
        type = types.enum ["sqlite3" "postgres" "mysql"];
        default = "sqlite3";
        description = "Database backend for Forgejo";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Database host (for postgres/mysql)";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "Database port (for postgres/mysql)";
      };

      name = mkOption {
        type = types.str;
        default = "forgejo";
        description = "Database name";
      };

      user = mkOption {
        type = types.str;
        default = "forgejo";
        description = "Database user";
      };

      # Password should be set via secrets management
      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing database password";
      };
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/forgejo";
      description = "Directory for Forgejo state and repositories";
    };

    repositoryRoot = mkOption {
      type = types.path;
      default = "${cfg.stateDir}/repositories";
      description = "Root directory for git repositories";
    };

    lfs = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Git LFS (Large File Storage) support";
      };

      contentPath = mkOption {
        type = types.path;
        default = "${cfg.stateDir}/lfs";
        description = "Directory for LFS objects";
      };
    };

    mailer = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable email notifications";
      };

      from = mkOption {
        type = types.str;
        default = "noreply@${cfg.domain}";
        description = "From address for emails";
      };

      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "SMTP server host";
      };

      port = mkOption {
        type = types.port;
        default = 25;
        description = "SMTP server port";
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for HTTP and SSH";
    };
  };

  config = mkIf cfg.enable {
    # Forgejo service configuration
    services.forgejo = {
      enable = true;
      package = pkgs.forgejo;
      stateDir = cfg.stateDir;

      settings = {
        server = {
          DOMAIN = cfg.domain;
          ROOT_URL = "http://${cfg.domain}:${toString cfg.httpPort}/";
          HTTP_PORT = cfg.httpPort;
          SSH_PORT = cfg.sshPort;
          START_SSH_SERVER = true;
        };

        database = {
          DB_TYPE = cfg.database.type;
        } // (if cfg.database.type != "sqlite3" then {
          HOST = "${cfg.database.host}:${toString cfg.database.port}";
          NAME = cfg.database.name;
          USER = cfg.database.user;
          PASSWD = mkIf (cfg.database.passwordFile != null) 
            (builtins.readFile cfg.database.passwordFile);
        } else {});

        repository = {
          ROOT = cfg.repositoryRoot;
        };

        lfs = mkIf cfg.lfs.enable {
          ENABLE = true;
          CONTENT_PATH = cfg.lfs.contentPath;
        };

        mailer = mkIf cfg.mailer.enable {
          ENABLED = true;
          FROM = cfg.mailer.from;
          SMTP_ADDR = cfg.mailer.host;
          SMTP_PORT = cfg.mailer.port;
        };

        service = {
          DISABLE_REGISTRATION = mkDefault false;
          REQUIRE_SIGNIN_VIEW = mkDefault false;
        };

        # Enable Actions (GitHub Actions compatible CI/CD)
        actions = {
          ENABLED = true;
        };
      };
    };

    # Firewall configuration
    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        cfg.httpPort
        cfg.sshPort
      ];
    };

    # Add helpful packages
    environment.systemPackages = with pkgs; [
      forgejo
      git
    ];
  };
}
