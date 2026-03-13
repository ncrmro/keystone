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

  # Agents that want git provisioning on this host (where Forgejo runs).
  # This is NOT filtered by agent.host — provisioning runs on the git server,
  # which is typically a different host from the agent's designated host.
  provisionAgents = filterAttrs (_: a: a.git.provision) config.keystone.os.agents;
  hasProvisionAgents = provisionAgents != { };
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
      default = false;
      description = "Open firewall ports for HTTP and SSH";
    };

    ssh = {
      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = "Open firewall for Git SSH port";
      };

      tailscaleOnly = mkOption {
        type = types.bool;
        default = false;
        description = "Restrict SSH access to Tailscale interface only (requires openFirewall = true)";
      };
    };

    adminUsers = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Forgejo usernames to add as admin collaborators on every provisioned agent repo";
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
          ROOT_URL = mkDefault "http://${cfg.domain}:${toString cfg.httpPort}/";
          HTTP_PORT = cfg.httpPort;
          SSH_PORT = cfg.sshPort;
          SSH_LISTEN_HOST = "0.0.0.0";
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

    # Firewall configuration for HTTP (when openFirewall is true)
    networking.firewall.allowedTCPPorts =
      (optionals cfg.openFirewall [ cfg.httpPort cfg.sshPort ])
      ++ (optionals (cfg.ssh.openFirewall && !cfg.ssh.tailscaleOnly) [ cfg.sshPort ]);

    # SSH firewall: restrict to Tailscale interface only
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      mkIf (cfg.ssh.openFirewall && cfg.ssh.tailscaleOnly) [ cfg.sshPort ];

    # Add helpful packages
    environment.systemPackages = with pkgs; [
      forgejo
      git
    ];

    # Auto-provision Forgejo users and repos for agents with git.provision = true.
    # Uses `forgejo admin` CLI for user creation (must run as the forgejo system
    # user — hence sudo -u) and the local API with a short-lived token for SSH
    # keys and repos. The token is scoped to the agent's own user (--username),
    # not the global admin. The --raw flag outputs just the token string.
    systemd.services = mkIf hasProvisionAgents (mapAttrs' (name: agentCfg:
      let
        username = agentCfg.git.username;
        email = if agentCfg.email != null
          then agentCfg.email
          else "agent-${name}@${config.keystone.domain}";
        repoName = agentCfg.git.repoName;
        apiUrl = "http://127.0.0.1:${toString cfg.httpPort}/api/v1";
        forgejoUser = config.services.forgejo.user;
      in
      nameValuePair "provision-agent-git-${name}" {
        description = "Provision Forgejo user and repo for agent-${name}";
        after = [ "forgejo.service" ];
        requires = [ "forgejo.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        path = [ pkgs.forgejo pkgs.curl pkgs.jq pkgs.coreutils pkgs.sudo ];

        script = ''
          set -euo pipefail

          FORGEJO="sudo -u ${forgejoUser} forgejo --work-path ${cfg.stateDir} admin"
          API="${apiUrl}"

          # --- User provisioning (via CLI, no token needed) ---
          # NOTE: Do not use `--admin` flag here — it filters to admin users only,
          # causing manually-created non-admin accounts to be missed.
          if $FORGEJO user list 2>/dev/null | grep -q "^.*\b${username}\b"; then
            echo "${username}: Forgejo user already exists"
          else
            echo "${username}: Creating Forgejo user..."
            RAND_PASS=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 24)
            $FORGEJO user create \
              --username "${username}" \
              --email "${email}" \
              --password "$RAND_PASS" \
              --must-change-password=false
            echo "${username}: Forgejo user created"
          fi

          # --- Create short-lived admin token for API operations ---
          TOKEN_NAME="provision-$(date +%s)"
          TOKEN=$($FORGEJO user generate-access-token \
            --username "${username}" \
            --token-name "$TOKEN_NAME" \
            --scopes "write:user,write:repository" \
            --raw 2>/dev/null || true)

          if [ -z "$TOKEN" ]; then
            echo "${username}: Could not generate API token, skipping SSH key and repo provisioning"
            exit 0
          fi
          AUTH="Authorization: token $TOKEN"

          # Cleanup function to delete the provisioning token when done
          cleanup_token() {
            curl -sf -X DELETE -H "$AUTH" "$API/users/${username}/tokens/$TOKEN_NAME" || true
          }
          trap cleanup_token EXIT

          # --- SSH key provisioning ---
          ${optionalString (agentCfg.ssh.publicKey != null) ''
            EXISTING_KEYS=$(curl -sf -H "$AUTH" "$API/users/${username}/keys" | jq length)
            if [ "$EXISTING_KEYS" -gt 0 ]; then
              echo "${username}: SSH key already registered, skipping"
            else
              echo "${username}: Adding SSH public key..."
              curl -sf -H "$AUTH" "$API/user/keys" \
                -H "Content-Type: application/json" \
                -d "$(jq -n \
                  --arg title "agent-${name}" \
                  --arg key ${escapeShellArg agentCfg.ssh.publicKey} \
                  '{title: $title, key: $key}')"
              echo "${username}: SSH key added"
            fi
          ''}

          # --- Repo provisioning ---
          REPO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "$AUTH" "$API/repos/${username}/${repoName}")

          if [ "$REPO_STATUS" = "200" ]; then
            echo "${username}: Repo ${repoName} already exists"
          else
            echo "${username}: Creating repo ${repoName}..."
            curl -sf -H "$AUTH" "$API/user/repos" \
              -H "Content-Type: application/json" \
              -d "$(jq -n \
                --arg name "${repoName}" \
                --arg desc "Notes and task workspace for agent-${name}" \
                '{name: $name, description: $desc, private: true, auto_init: true}')"
            echo "${username}: Repo ${repoName} created"
          fi

          # --- Add admin collaborators ---
          ${concatMapStringsSep "\n" (collab: ''
            COLLAB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
              -H "$AUTH" "$API/repos/${username}/${repoName}/collaborators/${collab}")
            if [ "$COLLAB_STATUS" = "204" ]; then
              echo "${username}: ${collab} already a collaborator on ${repoName}"
            else
              curl -sf -X PUT -H "$AUTH" \
                "$API/repos/${username}/${repoName}/collaborators/${collab}" \
                -H "Content-Type: application/json" \
                -d '{"permission": "admin"}'
              echo "${username}: Added ${collab} as admin collaborator on ${repoName}"
            fi
          '') cfg.adminUsers}

          echo "${username}: Forgejo provisioning complete"
        '';
      }
    ) provisionAgents);
  };
}
