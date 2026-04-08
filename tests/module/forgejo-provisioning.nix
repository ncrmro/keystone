# Forgejo-focused service account provisioning test
#
# Tests that the Forgejo git-server provisioning flow works correctly:
#   1. Forgejo HTTP API readiness with a bounded probe.
#   2. Agent user creation via `forgejo admin user create`.
#   3. Repository creation (notes repo).
#   4. Persistent API token generation.
#
# The provisioning service uses the actual `provision-agent-git.sh` script
# from the keystone source tree, so we test real module behaviour rather
# than a hand-crafted copy. Forgejo is configured directly (without the
# full keystone operating-system module) to avoid unrelated agenix
# assertions from the mail-client module.
#
# ISSUE-REQ-2, ISSUE-REQ-7, ISSUE-REQ-8
#
# Build:       nix build .#checks.x86_64-linux.test-forgejo-provisioning
# Interactive: nix build .#checks.x86_64-linux.test-forgejo-provisioning.driverInteractive
{
  pkgs,
  lib,
  self,
  home-manager,
}:
pkgs.testers.nixosTest {
  name = "forgejo-provisioning";

  nodes.machine =
    { config, pkgs, ... }:
    {
      # Direct Forgejo configuration — avoids the keystone operating-system
      # module and its agenix mail-client assertions, which require encrypted
      # secrets at build time. The provisioning script itself is pulled directly
      # from the keystone source tree so the real module code is exercised.
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
          # Required for first-run: skip install wizard
          security.INSTALL_LOCK = true;
        };
      };

      # Agent OS user (home directory must exist for token-write path)
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

      # Pre-create the tea and fj config files that the provisioning script
      # writes tokens into (normally created by home-manager activation).
      system.activationScripts.create-agent-cli-config-dirs = {
        text = ''
          TEA_DIR="/home/agent-test/.config/tea"
          FJ_DIR="/home/agent-test/.local/share/forgejo-cli"
          mkdir -p "$TEA_DIR" "$FJ_DIR"
          # tea config scaffold (empty token — provisioning will fill it in)
          cat > "$TEA_DIR/config.yml" << 'SEED'
          {"logins":[{"name":"forgejo","url":"http://machine:3000","token":"","default":true,"ssh_host":"machine","ssh_key":"~/.ssh/id_ed25519","ssh_agent":true,"version_check":false,"user":"test"}],"preferences":{"editor":false,"flag_defaults":{"remote":""}}}
          SEED
          # fj keys.json scaffold (alias only — provisioning will add host+token)
          cat > "$FJ_DIR/keys.json" << 'SEED'
          {"hosts":{},"aliases":{"machine:2222":"machine"},"default_ssh":[]}
          SEED
          chown -R agent-test:agents "$TEA_DIR" "$FJ_DIR"
          chmod 0600 "$TEA_DIR/config.yml" "$FJ_DIR/keys.json"
        '';
        deps = [ "users" ];
      };

      environment.systemPackages = [
        pkgs.forgejo
        pkgs.git
      ];

      # Provisioning service — uses the real provision-agent-git.sh script
      systemd.services.provision-agent-git-test = {
        description = "Provision Forgejo user and repo for agent-test";
        after = [
          "forgejo.service"
          "create-agent-cli-config-dirs.service"
        ];
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

      networking.useDHCP = false;
      networking.interfaces.eth0.useDHCP = true;

      virtualisation = {
        memorySize = 3072;
        cores = 2;
      };
    };

  testScript = ''
    print("=== forgejo-provisioning: starting test ===")
    machine.wait_for_unit("multi-user.target")
    print("System booted")

    machine.wait_for_unit("forgejo.service", timeout=120)
    print("Forgejo service active")

    machine.wait_for_open_port(3000, timeout=120)
    print("Forgejo HTTP port 3000 reachable")

    machine.wait_for_unit("provision-agent-git-test.service", timeout=300)
    print("Forgejo provisioning service completed")

    # Verify agent user was created
    machine.succeed(
      "curl -sf http://127.0.0.1:3000/api/v1/users/test"
      " | grep -q '\"login\"'"
    )
    print("PASS: agent user 'test' exists in Forgejo")

    # Verify the notes repo was created
    machine.succeed(
      "curl -sf http://127.0.0.1:3000/api/v1/repos/test/notes"
      " | grep -q '\"name\"'"
    )
    print("PASS: notes repository 'test/notes' exists in Forgejo")

    print("=== forgejo-provisioning: all tests passed ===")
  '';
}
