# Forgejo Configuration Cheat Sheet: https://forgejo.org/docs/next/admin/config-cheat-sheet/
# Keystone Git Server Module
#
# Provides a self-hosted git server using Forgejo (Gitea fork):
# - Web-based repository management
# - Issue tracking and pull requests
# - CI/CD integration (via Actions/Runners)
# - User authentication and access control
#
# Forgejo Actions Runner:
# - Enable via keystone.os.gitServer.runner.enable = true
# - Option A (auto-provision): set runner.autoProvision.adminUser = "alice"
#     The module automatically calls the Forgejo admin API to obtain and store
#     the registration token; no manual steps required.
# - Option B (manual): provide runner.tokenFile = "/run/agenix/forgejo-runner-token"
#     Get the token from: Forgejo web UI → Site Administration → Runners → Create Runner
#     OR via admin API: POST /api/v1/admin/runners/registration-token
# - Default label "native:host" runs jobs directly on the host without Docker
# - For Docker isolation, override labels with e.g. [ "ubuntu-latest:docker://node:18" ]
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.keystone.os.gitServer;
  keysCfg = config.keystone.keys;

  # Agents that want git provisioning on this host (where Forgejo runs).
  # This is NOT filtered by agent.host — provisioning runs on the git server,
  # which is typically a different host from the agent's designated host.
  provisionAgents = filterAttrs (_: a: a.git.provision) config.keystone.os.agents;
  hasProvisionAgents = provisionAgents != { };

  # Get an agent's SSH public key from the keystone.keys registry
  agentPublicKey = name: let
    registryName = "agent-${name}";
    u = keysCfg.${registryName} or null;
    hostKeys = if u != null then mapAttrsToList (_: h: h.publicKey) u.hosts else [];
  in if hostKeys != [] then head hostKeys else null;
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

    runner = {
      enable = mkEnableOption "Forgejo Actions runner (CI/CD job execution)";

      name = mkOption {
        type = types.str;
        default = config.networking.hostName;
        description = "Name of the runner instance as registered in Forgejo";
      };

      url = mkOption {
        type = types.str;
        default = "http://127.0.0.1:${toString cfg.httpPort}";
        description = "URL of the Forgejo instance the runner connects to";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/agenix/forgejo-runner-token";
        description = ''
          Path to a file containing the runner registration token.
          Obtain this token from: Forgejo web UI → Site Administration → Runners → Create Runner,
          or via the admin API: POST /api/v1/admin/runners/registration-token.
          Store the token as an agenix secret and reference its runtime path here.
        '';
      };

      labels = mkOption {
        type = types.listOf types.str;
        default = [ "native:host" ];
        example = [ "ubuntu-latest:docker://node:18-bullseye" "native:host" ];
        description = ''
          Runner labels that determine which workflow jobs this runner accepts.
          The "native:host" label runs jobs directly on the host without Docker.
          Docker-based labels (e.g. "ubuntu-latest:docker://node:18-bullseye") provide
          job isolation but require Docker to be available on the host.
        '';
      };

      autoProvision = {
        adminUser = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "alice";
          description = ''
            Forgejo admin username used to automatically obtain a runner
            registration token via the Forgejo admin API.
            When set, a systemd service will call the Forgejo API (using a
            short-lived admin token generated via the forgejo CLI) to fetch a
            runner registration token and write it to a system-managed path.
            This eliminates the need to manually obtain and store the token
            as an agenix secret.  Either this option or runner.tokenFile must
            be set when runner.enable is true.
          '';
        };
      };
    };
  };

  # Auto-enable when keystone.services.git.host matches this machine's hostname,
  # or when explicitly enabled via keystone.os.gitServer.enable.
  config = mkIf (cfg.enable
    || (config.keystone.services.git.host != null
        && config.keystone.services.git.host == config.networking.hostName)) (mkMerge [{
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
          # See: https://forgejo.org/docs/next/admin/config-cheat-sheet/
          DEFAULT_MERGE_STYLE = "squash";
        };

        # Server-side commit signing (merge commits, web editor, etc.)
        # SIGNING_KEY must point to the SSH public key file (.pub) — Forgejo
        # calls ssh.ParseAuthorizedKey() on the file contents, not the private key.
        # The corresponding private key is used by the built-in SSH server for signing.
        "repository.signing" = {
          SIGNING_KEY = "${cfg.stateDir}/ssh/ssh_host_ed25519_key.pub";
          FORMAT = "ssh";
          SIGNING_NAME = "Forgejo";
          SIGNING_EMAIL = "noreply@${cfg.domain}";
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

  }
  (mkIf cfg.runner.enable (let
    # When auto-provisioning, write the token to a persistent system-managed path.
    # The token is only needed for initial registration; once the runner has its
    # .runner config file it no longer reads the token file.
    autoTokenPath = "/var/lib/forgejo-runner-tokens/${cfg.runner.name}";
    effectiveTokenFile =
      if cfg.runner.tokenFile != null
      then cfg.runner.tokenFile
      else autoTokenPath;
  in {
    assertions = [
      {
        assertion = cfg.runner.tokenFile != null || cfg.runner.autoProvision.adminUser != null;
        message = "keystone.os.gitServer.runner: either runner.tokenFile or "
          + "runner.autoProvision.adminUser must be set when runner.enable is true. "
          + "Set adminUser to auto-provision the token from the local Forgejo instance, "
          + "or obtain a token manually from: Forgejo web UI → Site Administration → Runners → Create Runner.";
      }
    ];

    # Auto-provision the runner registration token by calling the Forgejo admin API
    # using a short-lived admin token generated via the forgejo CLI.
    # SECURITY: The token file is written with mode 0600, owned by the
    # gitea-actions-runner system user. The admin token is deleted immediately
    # after the registration token is obtained.
    systemd.services."provision-runner-token-${cfg.runner.name}" = mkIf
      (cfg.runner.autoProvision.adminUser != null) {
        description = "Auto-provision Forgejo runner registration token for ${cfg.runner.name}";
        # Run before the runner so the token is ready on first start.
        # After initial registration the runner saves its own credentials and
        # no longer needs this file.
        before = [ "gitea-actions-runner-${cfg.runner.name}.service" ];
        wantedBy = [ "gitea-actions-runner-${cfg.runner.name}.service" ];
        requires = [ "forgejo.service" ];
        after = [ "forgejo.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        path = [ pkgs.forgejo pkgs.curl pkgs.jq pkgs.coreutils pkgs.sudo ];

        script = ''
          set -euo pipefail

          RUNNER_STATE="/var/lib/gitea-actions-runner/${cfg.runner.name}/.runner"
          TOKEN_FILE="${autoTokenPath}"

          # Runner already registered — nothing to provision
          if [ -f "$RUNNER_STATE" ]; then
            echo "provision-runner-token: runner already registered, skipping"
            exit 0
          fi

          # Token file already present from a previous (failed) registration attempt
          if [ -f "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
            echo "provision-runner-token: token file already exists at $TOKEN_FILE"
            exit 0
          fi

          echo "provision-runner-token: obtaining runner registration token from Forgejo..."

          FORGEJO_CMD="sudo -u ${config.services.forgejo.user} forgejo --work-path ${cfg.stateDir} admin"
          API_URL="http://127.0.0.1:${toString cfg.httpPort}/api/v1"
          ADMIN_USER="${cfg.runner.autoProvision.adminUser}"
          TEMP_TOKEN_NAME="runner-provision-$(date +%s)"

          # Generate a short-lived admin API token via the forgejo CLI.
          # The CLI bypasses HTTP auth and talks directly to the database,
          # so no existing credentials are required.
          ADMIN_TOKEN=$($FORGEJO_CMD user generate-access-token \
            --username "$ADMIN_USER" \
            --token-name "$TEMP_TOKEN_NAME" \
            --scopes "write:admin" \
            --raw 2>/dev/null)

          if [ -z "$ADMIN_TOKEN" ]; then
            echo "provision-runner-token: ERROR — could not generate admin token for user $ADMIN_USER"
            exit 1
          fi

          # Always delete the short-lived admin token on exit
          cleanup() {
            curl -sf -X DELETE \
              -H "Authorization: token $ADMIN_TOKEN" \
              "$API_URL/users/$ADMIN_USER/tokens/$TEMP_TOKEN_NAME" || true
          }
          trap cleanup EXIT

          # Fetch the runner registration token from the Forgejo admin API
          REGISTRATION_TOKEN=$(curl -sf \
            -X POST \
            -H "Authorization: token $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            "$API_URL/admin/runners/registration-token" \
            | jq -r '.token')

          if [ -z "$REGISTRATION_TOKEN" ] || [ "$REGISTRATION_TOKEN" = "null" ]; then
            echo "provision-runner-token: ERROR — Forgejo API did not return a registration token"
            exit 1
          fi

          # Write token with secure permissions before populating it
          mkdir -p "$(dirname "$TOKEN_FILE")"
          touch "$TOKEN_FILE"
          chmod 0600 "$TOKEN_FILE"
          # Transfer ownership to the runner service user if it exists
          chown gitea-actions-runner "$TOKEN_FILE" 2>/dev/null || true
          printf '%s' "$REGISTRATION_TOKEN" > "$TOKEN_FILE"

          echo "provision-runner-token: registration token written to $TOKEN_FILE"
        '';
      };

    # Forgejo Actions runner — executes CI/CD jobs submitted by Forgejo Actions.
    # The runner registers with Forgejo using a one-time token and then polls for jobs.
    # SECURITY: The runner runs with its own system user and limited privileges.
    # For stronger isolation, set labels to Docker-based images instead of "native:host".
    services.gitea-actions-runner.instances.${cfg.runner.name} = {
      enable = true;
      name = cfg.runner.name;
      url = cfg.runner.url;
      tokenFile = effectiveTokenFile;
      labels = cfg.runner.labels;
    };
  }))
  {
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
        after = [ "forgejo.service" "home-manager-agent-${name}.service" ];
        requires = [ "forgejo.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        path = [ pkgs.forgejo pkgs.curl pkgs.jq pkgs.coreutils pkgs.sudo pkgs.yq-go ];

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
          # Keys registered here are for authentication only. Forgejo requires
          # SSH signing keys to be separately "verified" before commit signatures
          # are trusted. There is no REST API for this — agents must verify their
          # own key once via the web UI (Settings → SSH/GPG Keys → Verify) or
          # during onboarding. See:
          # https://forgejo.org/docs/next/admin/advanced/signing/
          ${let pubKey = agentPublicKey name; in optionalString (pubKey != null) ''
            EXISTING_KEYS=$(curl -sf -H "$AUTH" "$API/users/${username}/keys" | jq length)
            if [ "$EXISTING_KEYS" -gt 0 ]; then
              echo "${username}: SSH key already registered, skipping"
            else
              echo "${username}: Adding SSH public key..."
              curl -sf -H "$AUTH" "$API/user/keys" \
                -H "Content-Type: application/json" \
                -d "$(jq -n \
                  --arg title "agent-${name}" \
                  --arg key ${escapeShellArg pubKey} \
                  '{title: $title, key: $key}')"
              echo "${username}: SSH key added"
              echo "${username}: NOTE: To enable signed commit verification, verify the SSH key in Forgejo web UI: Settings → SSH/GPG Keys → Verify"
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

          # --- Persistent API token for tea/fj CLI access ---
          # tea's ssh_agent:true only authenticates git transport, not REST API.
          # Generate a long-lived token so agents can use tea pr/issue commands.
          API_TOKEN_NAME="api-agent-${name}"
          EXISTING_API_TOKEN=$(curl -sf -H "$AUTH" "$API/users/${username}/tokens" \
            | jq -r --arg n "$API_TOKEN_NAME" '.[] | select(.name == $n) | .name' || true)

          if [ -z "$EXISTING_API_TOKEN" ]; then
            echo "${username}: Generating persistent API token..."
            API_TOKEN=$($FORGEJO user generate-access-token \
              --username "${username}" \
              --token-name "$API_TOKEN_NAME" \
              --scopes "write:activitypub,write:issue,write:misc,write:notification,write:organization,write:package,write:repository,write:user" \
              --raw 2>/dev/null || true)

            if [ -n "$API_TOKEN" ]; then
              AGENT_HOME=$(eval echo ~agent-${name})

              # Write token into tea config
              TEA_FILE="$AGENT_HOME/.config/tea/config.yml"
              if [ -f "$TEA_FILE" ]; then
                API_TOKEN="$API_TOKEN" yq -i '.logins[0].token = strenv(API_TOKEN)' "$TEA_FILE"
                chown agent-${name}:agents "$TEA_FILE"
                chmod 0600 "$TEA_FILE"
                echo "${username}: Wrote API token to tea config"
              fi

              # Write token into fj keys.json (tagged enum format)
              FJ_FILE="$AGENT_HOME/.local/share/forgejo-cli/keys.json"
              if [ -f "$FJ_FILE" ]; then
                jq --arg host "${cfg.domain}" --arg token "$API_TOKEN" --arg name "$API_TOKEN_NAME" \
                  '.hosts[$host] = {"type": "Application", "name": $name, "token": $token}' "$FJ_FILE" > "$FJ_FILE.tmp" \
                  && mv "$FJ_FILE.tmp" "$FJ_FILE"
                chown agent-${name}:agents "$FJ_FILE"
                chmod 0600 "$FJ_FILE"
                echo "${username}: Wrote API token to fj config"
              fi
            else
              echo "${username}: Could not generate persistent API token"
            fi
          else
            echo "${username}: Persistent API token already exists, skipping"
          fi

          echo "${username}: Forgejo provisioning complete"
        '';
      }
    ) provisionAgents);
  }]);
}
