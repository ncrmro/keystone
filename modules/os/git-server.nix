# Forgejo Configuration Cheat Sheet: https://forgejo.org/docs/next/admin/config-cheat-sheet/
# Keystone Git Server Module
#
# Provides a self-hosted git server using Forgejo (Gitea fork):
# - Web-based repository management
# - Issue tracking and pull requests
# - CI/CD integration (via Actions/Runners)
# - User authentication and access control
#
# Forgejo Actions runner is supported via keystone.os.gitServer.runner.
# Enable with runner.enable = true — the token is auto-provisioned at runtime
# by discovering the first admin user and fetching a registration token from
# the Forgejo API. A rootless podman socket is set up for the runner user so
# actions run in rootless containers via DOCKER_HOST.
#
{
  lib,
  config,
  pkgs,
  utils,
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

  # Systemd service name for the gitea-actions-runner instance
  runnerServiceName = "gitea-runner-${utils.escapeSystemdPath cfg.runner.name}";

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
      enable = mkEnableOption ''
        Forgejo Actions runner.
        The registration token is provisioned automatically at runtime by
        discovering the first admin user. Labels and container runtime are
        managed automatically — rootless podman is enabled for the runner user.

        Usage:
          keystone.os.gitServer = {
            enable = true;
            runner.enable = true;
          };
      '';

      name = mkOption {
        type = types.str;
        default = config.networking.hostName;
        description = "Runner name shown in Forgejo UI";
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
      lfs.enable = cfg.lfs.enable;

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

        "repository.pull-request" = {
          DEFAULT_MERGE_STYLE = "squash";
          DEFAULT_DELETE_BRANCH_AFTER_MERGE = true;
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
  }
  (mkIf cfg.runner.enable {
    # Rootless podman for the runner user.
    # The gitea-actions-runner module uses DynamicUser=true with User="gitea-runner".
    # Declaring a static user with the same name causes systemd to reuse it
    # (per the DynamicUser docs), giving us a stable user we can set up linger for.
    virtualisation.podman.enable = true;

    users.users.gitea-runner = {
      isSystemUser = true;
      group = "gitea-runner";
      home = "/var/lib/gitea-runner";
    };
    users.groups.gitea-runner = {};

    # Linger keeps the gitea-runner user session alive across boots so that
    # user-level systemd units (including podman.socket) start without login.
    systemd.tmpfiles.rules = [
      "f /var/lib/systemd/linger/gitea-runner 0644 root root -"
    ];

    # Start the rootless podman socket for the runner user before the runner
    # starts. Uses `systemctl --user -M gitea-runner@` to talk to the user
    # manager that linger keeps alive, matching the user instruction:
    #   systemctl --user enable --now podman.socket
    systemd.services."forgejo-runner-podman-socket" = {
      description = "Start rootless podman socket for Forgejo runner";
      wantedBy = [ "multi-user.target" ];
      before = [ "${runnerServiceName}.service" ];
      after = [ "systemd-user-sessions.service" ];
      path = [ pkgs.systemd ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Wait for the gitea-runner user manager to be ready (linger starts it
        # asynchronously at boot). Retry for up to 30 s.
        for i in $(seq 1 30); do
          systemctl --user -M gitea-runner@ is-system-running 2>/dev/null && break || true
          sleep 1
        done
        systemctl --user -M gitea-runner@ enable --now podman.socket
      '';
    };

    # Point the runner at the rootless podman socket.
    # %U is a systemd unit specifier that expands to the service user's numeric
    # UID at runtime, giving us the correct /run/user/<uid> path without
    # needing to know the UID statically.
    systemd.services.${runnerServiceName}.environment = {
      DOCKER_HOST = "unix:///run/user/%U/podman/podman.sock";
    };

    # Token auto-provisioning: discovers the first admin user at runtime,
    # generates a short-lived write:admin token, fetches the runner
    # registration token, then deletes the temp token.
    #
    # SECURITY: The temp token is scoped to write:admin and deleted on exit.
    # The TOKEN env-file is written to a root-owned path under
    # /var/lib/forgejo-runner and read by the runner via EnvironmentFile=.
    systemd.services."provision-runner-token-${cfg.runner.name}" = {
      description = "Provision Forgejo Actions runner registration token for ${cfg.runner.name}";
      after = [ "forgejo.service" ];
      requires = [ "forgejo.service" ];
      before = [ "${runnerServiceName}.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "forgejo-runner";
        StateDirectoryMode = "0700";
      };

      path = [ pkgs.forgejo pkgs.curl pkgs.jq pkgs.coreutils pkgs.sudo ];

      script = ''
        set -euo pipefail

        TOKEN_FILE="/var/lib/forgejo-runner/runner-token"

        # Idempotent: skip if token env-file already exists
        if [ -f "$TOKEN_FILE" ]; then
          echo "provision-runner-token: runner token already exists, skipping"
          exit 0
        fi

        FORGEJO_CMD="sudo -u ${config.services.forgejo.user} forgejo --work-path ${cfg.stateDir} admin"
        API="http://127.0.0.1:${toString cfg.httpPort}/api/v1"

        # Auto-discover the first Forgejo admin user.
        # --admin filters to admin accounts only; NR==2 skips the header row.
        ADMIN_USER=$($FORGEJO_CMD user list --admin 2>/dev/null | awk 'NR==2{print $2}')

        if [ -z "$ADMIN_USER" ]; then
          echo "provision-runner-token: ERROR — no admin user found in Forgejo"
          exit 1
        fi

        echo "provision-runner-token: using admin user '$ADMIN_USER'"

        TEMP_TOKEN_NAME="provision-runner-$(date +%s)"
        ADMIN_TOKEN=$($FORGEJO_CMD user generate-access-token \
          --username "$ADMIN_USER" \
          --token-name "$TEMP_TOKEN_NAME" \
          --scopes "write:admin" \
          --raw 2>/dev/null)

        if [ -z "$ADMIN_TOKEN" ]; then
          echo "provision-runner-token: ERROR — could not generate admin API token"
          exit 1
        fi

        AUTH="Authorization: token $ADMIN_TOKEN"

        # Delete the short-lived admin token on exit (success or failure)
        cleanup_token() {
          curl -sf -X DELETE -H "$AUTH" \
            "$API/users/$ADMIN_USER/tokens/$TEMP_TOKEN_NAME" || true
        }
        trap cleanup_token EXIT

        RUNNER_TOKEN=$(curl -sf -H "$AUTH" \
          -X POST "$API/admin/runners/registration-token" \
          | jq -r '.token')

        if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" = "null" ]; then
          echo "provision-runner-token: ERROR — could not fetch runner registration token"
          exit 1
        fi

        # Write as systemd EnvironmentFile (KEY=VALUE format) so the runner
        # service can load it via EnvironmentFile=
        echo "TOKEN=$RUNNER_TOKEN" > "$TOKEN_FILE"
        chmod 0600 "$TOKEN_FILE"
        echo "provision-runner-token: token written to $TOKEN_FILE"
      '';
    };

    # Use the official Forgejo runner (pkgs.forgejo-runner) rather than the
    # older gitea act_runner (pkgs.gitea-actions-runner) that the module
    # defaults to. Labels follow the standard Forgejo runner label format
    # (see `forgejo-runner generate-config`); docker:// scheme is satisfied
    # by the rootless podman socket via DOCKER_HOST above.
    services.gitea-actions-runner.package = pkgs.forgejo-runner;
    services.gitea-actions-runner.instances.${cfg.runner.name} = {
      enable = true;
      name = cfg.runner.name;
      url = "http://127.0.0.1:${toString cfg.httpPort}";
      labels = [
        "native:host"
        "ubuntu-latest:docker://node:20-bookworm"
        "ubuntu-22.04:docker://node:20-bookworm"
        "ubuntu-20.04:docker://node:20-focal"
      ];
      tokenFile = "/var/lib/forgejo-runner/runner-token";
    };
  })
]);
}
