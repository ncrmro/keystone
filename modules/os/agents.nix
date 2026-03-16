# Keystone OS Agents Module
#
# Creates agent users with:
# - NixOS user accounts in the agents group (no sudo, no wheel)
# - UIDs from the 4000+ reserved range
# - Home directories at /home/agent-{name} (ZFS dataset or ext4)
# - chmod 700 isolation between agents
# - Headless Wayland desktop (labwc + wayvnc) for remote viewing
# - Terminal environment (zsh, helix, zellij, git)
# - Chromium browser with remote debugging + Chrome DevTools MCP
# - Stalwart mail account with himalaya CLI
# - Vaultwarden/Bitwarden integration with per-agent collections
# - Per-agent Tailscale instances with UID-based routing
# - SSH key management via agenix (ssh-agent + git signing)
#
# Usage:
#   keystone.domain = "ks.systems";
#   keystone.os.agents.researcher = {
#     fullName = "Research Agent";
#     email = "researcher@ks.systems";
#     # SSH public key declared in keystone.keys."agent-researcher"
#   };
#
# Host filtering:
#   Agent identities are shared across all hosts (via a common import like
#   agent-identities.nix), but the `host` field controls WHERE feature-specific
#   resources are created:
#
#   ALWAYS created on every importing host (uses `cfg`, the full agent set):
#   - OS user/group accounts (agents need accounts for SSH access everywhere)
#   - Home directories
#   - User services guarded by ConditionUser (won't run unless logged in)
#
#   ONLY created on the agent's designated host (uses `localAgents`, filtered
#   by host == networking.hostName):
#   - SSH secrets + ssh-agent service (agenix assertions for private key/passphrase)
#   - Desktop environment (labwc, wayvnc)
#   - Mail client config (himalaya, mail-password assertion)
#
#   Created on SERVER hosts independently of `host` (mail.nix, git-server.nix):
#   - Mail account provisioning (where Stalwart runs, filtered by mail.provision)
#   - Git account provisioning (where Forgejo runs, filtered by git.provision)
#
#   Agenix implication: secrets like agent-{name}-mail-password may need
#   recipients on BOTH the agent's host (for himalaya) AND the server host
#   (for Stalwart provisioning). See agenix-secrets/secrets.nix.
#
# SSH: Each agent gets an ssh-agent systemd service that auto-loads its
# private key from agenix using the passphrase secret. Git is configured
# to sign commits with the SSH key. The agent's public key is added to
# its own ~/.ssh/authorized_keys for sandbox access.
#
# Security: VNC binds to 0.0.0.0 by default. Set desktop.vncBind = "127.0.0.1"
# for localhost-only. Use firewall rules or Tailscale ACLs to restrict access.
# wayvnc supports TLS but it is not yet configured here.
#
# CRITICAL: docs/agents.md documents the human-side tooling (agentctl, mail
# templates) for this module. Keep it in sync with any changes here.
#
{
  lib,
  config,
  pkgs,
  options,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.agents;
  keysCfg = config.keystone.keys;
  topDomain = config.keystone.domain;

  # Get an agent's SSH public key from the keystone.keys registry.
  # Agents have exactly one host key — this returns it (or null if not in registry).
  agentPublicKey = name: let
    registryName = "agent-${name}";
    u = keysCfg.${registryName} or null;
    hostKeys = if u != null then mapAttrsToList (_: h: h.publicKey) u.hosts else [];
  in if hostKeys != [] then head hostKeys else null;

  # All public keys for an agent from the keystone.keys registry
  allKeysForAgent = name: let
    registryName = "agent-${name}";
  in if keysCfg ? ${registryName} then
    let
      u = keysCfg.${registryName};
      hostKeys = mapAttrsToList (_: h: h.publicKey) u.hosts;
      hwKeys = mapAttrsToList (_: h: h.publicKey) u.hardwareKeys;
    in hostKeys ++ hwKeys
  else [];

  # TODO: Re-evaluate agent ZFS home folders. Implementation needs to be reconciled with legacy setups.
  useZfs = osCfg.storage.type == "zfs" && osCfg.storage.enable;

  # Base UID for agent users
  agentUidBase = 4000;

  # Base VNC port for auto-assignment
  vncPortBase = 5900;

  # Base Chrome debug port for auto-assignment
  chromeDebugPortBase = 9222;

  # Base Chrome MCP port for auto-assignment
  chromeMcpPortBase = 3100;

  # Agent submodule type definition
  agentSubmodule = types.submodule (
    {
      name,
      config,
      ...
    }:
    {
      options = {
        uid = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "User ID. If null, auto-assigned from the 4000+ range.";
        };

        host = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Hostname where this agent primarily runs. Controls two things:

            1. Feature filtering — desktop, mail-client, and SSH resources
               (secrets, assertions, services) are only created on the host
               whose networking.hostName matches this value.

            2. All hosts still get the agent's OS user/group and home directory
               so the agent can SSH in everywhere.

            Server-side provisioning (mail.nix, git-server.nix) is independent
            of this field — it runs wherever Stalwart/Forgejo is enabled and
            is gated by mail.provision / git.provision instead.
          '';
          example = "ncrmro-workstation";
        };

        fullName = mkOption {
          type = types.str;
          description = "Display name for the agent";
          example = "Research Agent";
        };

        email = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Email address for the agent (used for git config and mail provisioning)";
          example = "researcher@ks.systems";
        };

        terminal = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable terminal environment (zsh, starship, helix, AI tools) via home-manager.";
          };
        };

        desktop = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable headless Wayland desktop (labwc + wayvnc).";
          };

          resolution = mkOption {
            type = types.str;
            default = "1920x1080";
            description = "Desktop resolution (WxH)";
          };

          vncPort = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "VNC port. If null, auto-assigned starting from 5901.";
          };

          vncBind = mkOption {
            type = types.str;
            default = "0.0.0.0";
            description = "Address for wayvnc to bind. Use 127.0.0.1 for localhost-only.";
          };
        };

        chrome = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable Chrome remote debugging via Chromium + DevTools MCP.";
          };

          debugPort = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "Chrome remote debugging port. If null, auto-assigned starting from 9222.";
          };

          mcp = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable Chrome DevTools MCP server for this agent.";
            };

            port = mkOption {
              type = types.nullOr types.port;
              default = null;
              description = "Chrome DevTools MCP server port. If null, auto-assigned starting from 3101.";
            };
          };
        };

        mail = {
          provision = mkOption {
            type = types.bool;
            default = false;
            description = "Auto-provision Stalwart mail account on the mail server host.";
          };

          address = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Full email address. Defaults to agent-{name}@{keystone.domain}.";
            example = "agent-researcher@ks.systems";
          };

          imap.port = mkOption {
            type = types.int;
            default = 993;
            description = "IMAP port";
          };

          smtp.port = mkOption {
            type = types.int;
            default = 465;
            description = "SMTP port";
          };

          # CalDAV and CardDAV are always provisioned alongside mail
        };

        # Tailscale: each agent gets its own tailscaled instance with unique
        # state dir, socket, and TUN interface. An nftables fwmark rule routes
        # the agent's UID traffic through its dedicated TUN.
        # Requires an agenix secret at age.secrets."agent-{name}-tailscale-auth-key".

        # SSH: each agent gets ssh-agent + git signing + agenix secrets.
        # Requires agenix secrets: agent-{name}-ssh-key, agent-{name}-ssh-passphrase.
        # CRITICAL: SSH public key is now declared in keystone.keys."agent-{name}"
        # instead of here. The single host key is read from the registry.

        git = {
          provision = mkOption {
            type = types.bool;
            default = false;
            description = "Auto-provision Forgejo user, SSH key, and notes repo on the git server host.";
          };

          username = mkOption {
            type = types.str;
            default = name;
            description = "Forgejo username. Defaults to agent name.";
          };

          host = mkOption {
            type = types.str;
            default = "git.${topDomain}";
            description = "Git server hostname. Defaults to git.{keystone.domain}.";
          };

          sshPort = mkOption {
            type = types.port;
            default = 2222;
            description = "Git SSH port.";
          };

          repoName = mkOption {
            type = types.str;
            default = "agent-space";
            description = "Name of auto-created notes repository.";
          };
        };

        passwordManager = {
          provision = mkOption {
            type = types.bool;
            default = false;
            description = "Emit provisioning instructions for Vaultwarden (no API available for auto-create).";
          };
        };

        notes = {
          repo = mkOption {
            type = types.str;
            default = "ssh://forgejo@${config.git.host}:${toString config.git.sshPort}/${config.git.username}/${config.git.repoName}.git";
            description = "Git repository URL for the agent's notes. Auto-derived from git options.";
            example = "ssh://forgejo@git.example.com:2222/user/notes.git";
          };

          path = mkOption {
            type = types.str;
            default = "/home/agent-${name}/notes";
            description = "Local checkout path for the notes repo.";
          };

          syncOnCalendar = mkOption {
            type = types.str;
            default = "*:0/5";
            description = "Systemd calendar spec for notes sync timer. Default: every 5 minutes.";
          };

          taskLoop = {
            onCalendar = mkOption {
              type = types.str;
              default = "*:0/5";
              description = "Systemd calendar spec for task loop timer. Default: every 5 minutes.";
            };

            maxTasks = mkOption {
              type = types.int;
              default = 5;
              description = "Maximum number of pending tasks to execute per run.";
            };
          };

          scheduler = {
            onCalendar = mkOption {
              type = types.str;
              default = "*-*-* 05:00:00";
              description = "Systemd calendar spec for scheduler timer. Default: daily at 5 AM.";
            };
          };
        };

        mcp = {
          servers = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                command = mkOption {
                  type = types.str;
                  description = "Absolute path to the MCP server binary.";
                };
                args = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = "Arguments to pass to the MCP server.";
                };
                env = mkOption {
                  type = types.attrsOf types.str;
                  default = {};
                  description = "Environment variables for the MCP server.";
                };
              };
            });
            default = {};
            description = "Additional MCP servers to configure for this agent.";
          };
        };
      };
    }
  );

  # Sorted agent names for deterministic UID assignment
  sortedAgentNames = sort lessThan (attrNames cfg);

  # Auto-assign UIDs to agents that don't have explicit ones
  agentWithUid =
    name: agentCfg:
    let
      idx =
        findFirst (i: elemAt sortedAgentNames i == name)
          (throw "agent '${name}' not found in sortedAgentNames")
          (genList (x: x) (length sortedAgentNames));
      autoUid = agentUidBase + 1 + idx;
    in
    agentCfg
    // {
      uid = if agentCfg.uid != null then agentCfg.uid else autoUid;
    };

  agentsWithUids = mapAttrs agentWithUid cfg;

  # SECURITY: Per-agent service helper — sole sudoers target for agent-admins.
  # Without this, SETENV on direct systemctl allows LD_PRELOAD injection as the
  # agent user, exposing SSH keys and mail credentials. The helper hardcodes
  # XDG_RUNTIME_DIR internally and allowlists safe systemctl verbs only.
  agentSvcHelper = name:
    let
      resolved = agentsWithUids.${name};
      uid = toString resolved.uid;
    in
    pkgs.writeShellScript "agent-svc-${name}" ''
      set -euo pipefail
      export XDG_RUNTIME_DIR="/run/user/${uid}"
      # CRITICAL: systemctl --user via sudo cannot auto-discover the dbus
      # socket. Without this, every agentctl command fails with "Failed to
      # connect to user scope bus via local transport: No such file or directory".
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus"
      export SSH_AUTH_SOCK="/run/agent-${name}-ssh-agent/agent.sock"
      # SECURITY: Use the agent's own home-manager profile, not the caller's.
      # Without this, `agentctl <name> exec` inherits the invoking user's PATH
      # (e.g. ncrmro's), breaking all home-manager tools (himalaya, direnv, fj,
      # rbw) and devshell tools (deepwork, gh, node) for the agent.
      export PATH="/etc/profiles/per-user/agent-${name}/bin:${lib.makeBinPath [ pkgs.nix ]}:/run/current-system/sw/bin"

      if [ $# -lt 1 ]; then
        echo "Usage: agent-svc-${name} <verb> [args...]" >&2
        exit 1
      fi

      VERB="$1"; shift

      case "$VERB" in
        # Safe systemctl verbs
        status|start|stop|restart|enable|disable|list-units|list-timers|show|cat|is-active|is-enabled|is-failed|daemon-reload|reset-failed)
          exec systemctl --user "$VERB" "$@"
          ;;
        # journalctl passthrough
        journalctl)
          exec journalctl --user "$@"
          ;;
        # Run arbitrary command as this agent (for diagnostics)
        exec)
          exec "$@"
          ;;
        *)
          echo "Error: verb '$VERB' is not allowed." >&2
          echo "Allowed: status start stop restart enable disable list-units list-timers show cat is-active is-enabled is-failed daemon-reload reset-failed journalctl exec" >&2
          exit 1
          ;;
      esac
    '';

  # All defined agents get OS users, home directories, services, etc.
  # Feature-specific agent sets (desktop, mail, SSH) are filtered to only
  # agents whose `host` matches this machine, so assertions and services
  # for secrets/keys/configs don't fire on unrelated hosts.
  localAgents = filterAttrs (_: agentCfg: agentCfg.host == config.networking.hostName) cfg;

  desktopAgents = localAgents;
  hasDesktopAgents = desktopAgents != { };

  mailAgents = localAgents;
  hasMailAgents = mailAgents != { };

  sshAgents = localAgents;
  hasSshAgents = sshAgents != { };

  # Sorted desktop agent names for deterministic VNC port assignment
  sortedDesktopAgentNames = sort lessThan (attrNames desktopAgents);

  # Resolve VNC port for a desktop agent (local host perspective)
  agentVncPort =
    name: agentCfg:
    if agentCfg.desktop.vncPort != null then
      agentCfg.desktop.vncPort
    else
      let
        idx = findFirst (
          i: elemAt sortedDesktopAgentNames i == name
        ) (throw "desktop agent '${name}' not found") (genList (x: x) (length sortedDesktopAgentNames));
      in
      vncPortBase + 1 + idx;

  # Resolve VNC port for ANY agent by simulating per-host grouping.
  # agentctl needs this for remote VNC connections — the port depends on
  # how many agents share the same host, not on the local host's agent set.
  globalAgentVncPort =
    name: agentCfg:
    if agentCfg.desktop.vncPort != null then
      agentCfg.desktop.vncPort
    else
      let
        sameHostAgentNames = sort lessThan (filter (n: cfg.${n}.host == agentCfg.host) (attrNames cfg));
        idx = findFirst (
          i: elemAt sameHostAgentNames i == name
        ) (throw "agent '${name}' not found in host group") (genList (x: x) (length sameHostAgentNames));
      in
      vncPortBase + 1 + idx;

  # Chrome services run on the agent's host (alongside labwc)
  chromeAgents = localAgents;
  hasChromeAgents = chromeAgents != { };

  # Sorted chrome agent names for deterministic debug port assignment
  sortedChromeAgentNames = sort lessThan (attrNames chromeAgents);

  # Resolve Chrome debug port for a chrome agent
  agentChromeDebugPort =
    name: agentCfg:
    if agentCfg.chrome.debugPort != null then
      agentCfg.chrome.debugPort
    else
      let
        idx = findFirst (
          i: elemAt sortedChromeAgentNames i == name
        ) (throw "chrome agent '${name}' not found") (genList (x: x) (length sortedChromeAgentNames));
      in
      chromeDebugPortBase + idx;

  # Resolve Chrome debug port for ANY agent by simulating per-host grouping.
  # Used in MCP configs which are built for all agents, not just local ones.
  globalAgentChromeDebugPort =
    name: agentCfg:
    if agentCfg.chrome.debugPort != null then
      agentCfg.chrome.debugPort
    else
      let
        sameHostAgentNames = sort lessThan (filter (n: cfg.${n}.host == agentCfg.host) (attrNames cfg));
        idx = findFirst (
          i: elemAt sameHostAgentNames i == name
        ) (throw "agent '${name}' not found in host group") (genList (x: x) (length sameHostAgentNames));
      in
      chromeDebugPortBase + idx;

  # Resolve Chrome MCP port for a chrome agent
  agentChromeMcpPort =
    name: agentCfg:
    if agentCfg.chrome.mcp.port != null then
      agentCfg.chrome.mcp.port
    else
      let
        idx = findFirst (
          i: elemAt sortedChromeAgentNames i == name
        ) (throw "chrome agent '${name}' not found") (genList (x: x) (length sortedChromeAgentNames));
      in
      chromeMcpPortBase + 1 + idx;

  # TODO: Re-enable per-agent Tailscale after fixing agenix.service dependency
  tailscaleAgents = {};
  hasTailscaleAgents = false;

  # fwmark base for per-agent tailscale routing (one per agent)
  tailscaleFwmarkBase = 51820;
  sortedTailscaleAgentNames = sort lessThan (attrNames tailscaleAgents);

  # Compute fwmark for a tailscale agent
  agentFwmark =
    name:
    let
      idx = findFirst (
        i: elemAt sortedTailscaleAgentNames i == name
      ) (throw "tailscale agent '${name}' not found") (genList (x: x) (length sortedTailscaleAgentNames));
    in
    tailscaleFwmarkBase + 1 + idx;

  # Generate labwc config for an agent's home directory setup script
  labwcConfigScript =
    username: agentCfg:
    ''
        # Create labwc config directory
        mkdir -p /home/${username}/.config/labwc
        # autostart: create virtual output for headless VNC
        cat > /home/${username}/.config/labwc/autostart <<'AUTOSTART'
        # Create virtual output for headless VNC
        ${pkgs.wlr-randr}/bin/wlr-randr --output HEADLESS-1 --custom-mode ${agentCfg.desktop.resolution}
      AUTOSTART
        chmod +x /home/${username}/.config/labwc/autostart
        # rc.xml: minimal labwc config
        cat > /home/${username}/.config/labwc/rc.xml <<'RCXML'
      <?xml version="1.0"?>
      <labwc_config>
        <theme><name>default</name></theme>
      </labwc_config>
      RCXML
        chown -R ${username}:agents /home/${username}/.config
    '';

  # Task loop script: pre-fetch sources, ingest, prioritize, execute
  # Uses claude from the agent's home-manager profile PATH
  agentTaskLoopScript =
    name: agentCfg:
    let
      username = "agent-${name}";
      notesDir = agentCfg.notes.path;
      maxTasks = agentCfg.notes.taskLoop.maxTasks;
      yq = "${pkgs.yq-go}/bin/yq";
      jq = "${pkgs.jq}/bin/jq";
      date = "${pkgs.coreutils}/bin/date";
      mkdir = "${pkgs.coreutils}/bin/mkdir";
      echo = "${pkgs.coreutils}/bin/echo";
      cat = "${pkgs.coreutils}/bin/cat";
      tee = "${pkgs.coreutils}/bin/tee";
      wc = "${pkgs.coreutils}/bin/wc";
      head = "${pkgs.coreutils}/bin/head";
      seq = "${pkgs.coreutils}/bin/seq";
      find = "${pkgs.findutils}/bin/find";
      sort = "${pkgs.coreutils}/bin/sort";
      rm = "${pkgs.coreutils}/bin/rm";
      flock = "${pkgs.util-linux}/bin/flock";
      sha256sum = "${pkgs.coreutils}/bin/sha256sum";
      mcpConfigFile = agentMcpConfig name agentCfg;
    in
    pkgs.writeShellScript "agent-${name}-task-loop" ''
      set -eo pipefail

      NOTES_DIR="${notesDir}"
      LOGS_DIR="$HOME/.local/state/agent-task-loop/logs"
      TASK_LOGS_DIR="$LOGS_DIR/tasks"
      STATE_DIR="$HOME/.local/state/agent-task-loop/state"
      LOCKFILE="$STATE_DIR/task-loop.lock"

      ${mkdir} -p "$LOGS_DIR" "$TASK_LOGS_DIR" "$STATE_DIR"

      TIMESTAMP=$(${date} +%Y-%m-%d_%H%M%S)
      LOG_FILE="$LOGS_DIR/$TIMESTAMP.log"
      START_TIME=$(${date} +%s)

      CURRENT_STEP="init"
      CURRENT_TASK=""
      log() {
        local tag="[step=$CURRENT_STEP]"
        [ -n "$CURRENT_TASK" ] && tag="$tag[task=$CURRENT_TASK]"
        ${echo} "[$(${date} '+%H:%M:%S')] $tag $*" | ${tee} -a "$LOG_FILE" >&2
      }

      # Lock to prevent concurrent runs (flock auto-releases on process death, even SIGKILL)
      exec 9>"$LOCKFILE"
      if ! ${flock} -n 9; then
        ${echo} "Task loop already running, skipping" >&2
        exit 0
      fi

      if [ ! -d "$NOTES_DIR" ]; then
        ${echo} "Notes directory $NOTES_DIR does not exist yet, skipping"
        exit 0
      fi
      cd "$NOTES_DIR"
      log "Starting agent task loop for ${name}"

      # ── Step 1: Pre-fetch sources ─────────────────────────────────
      # Always runs — discovers new tasks from email, git, and custom sources.
      CURRENT_STEP="prefetch"
      log "Step 1: Pre-fetching sources..."
      SOURCES_JSON="[]"

      # Built-in source: email inbox (himalaya)
      # himalaya is installed via home-manager (keystone.terminal.mail), not the dev shell
      if command -v himalaya &>/dev/null; then
        log "  Fetching source: email"
        EMAIL_OUTPUT=$(himalaya envelope list --page-size 20 --output json 2>>"$LOG_FILE" || ${echo} "[]")
        if [ -n "$EMAIL_OUTPUT" ] && [ "$EMAIL_OUTPUT" != "[]" ]; then
          SOURCES_JSON=$(${echo} "$SOURCES_JSON" | ${jq} --argjson data "$EMAIL_OUTPUT" \
            '. + [{"source": "email", "data": $data}]')
        fi
      else
        log "  Skipping email source: himalaya not found"
      fi

      # Custom sources from PROJECTS.yaml (user-defined commands)
      if [ -f PROJECTS.yaml ]; then
        SOURCE_COUNT=$(${yq} '.sources | length' PROJECTS.yaml 2>/dev/null || ${echo} "0")

        for i in $(${seq} 0 $((SOURCE_COUNT - 1))); do
          SOURCE_NAME=$(${yq} ".sources[$i].name" PROJECTS.yaml)
          SOURCE_CMD=$(${yq} ".sources[$i].command" PROJECTS.yaml)

          if [ -n "$SOURCE_CMD" ] && [ "$SOURCE_CMD" != "null" ]; then
            log "  Fetching source: $SOURCE_NAME"
            SOURCE_OUTPUT=$(bash -c "$SOURCE_CMD" 2>>"$LOG_FILE" || ${echo} "[]")
            SOURCES_JSON=$(${echo} "$SOURCES_JSON" | ${jq} --arg name "$SOURCE_NAME" --argjson data "$SOURCE_OUTPUT" \
              '. + [{"source": $name, "data": $data}]')
          fi
        done
      fi

      log "  Collected sources: $(${echo} "$SOURCES_JSON" | ${jq} 'length') entries"

      # ── Step 2: Ingest (haiku) ────────────────────────────────────
      CURRENT_STEP="ingest"
      INGEST_RAN=false
      log "Step 2: Ingesting sources via haiku..."
      if [ "$(${echo} "$SOURCES_JSON" | ${jq} '[.[].data | length] | add // 0')" -gt 0 ]; then
        set +o pipefail
        claude --print --dangerously-skip-permissions --mcp-config "${mcpConfigFile}" --model haiku \
          "/deepwork task_loop ingest

      Source data (pre-fetched):
      $(${echo} "$SOURCES_JSON" | ${jq} '.')" 2>&1 | ${tee} -a "$LOG_FILE" >&2
        INGEST_EXIT=''${PIPESTATUS[0]}
        set -o pipefail
        if [ "$INGEST_EXIT" -ne 0 ]; then
          log "  WARNING: Ingest step failed, continuing..."
        else
          INGEST_RAN=true
        fi
      else
        log "  No source data to ingest, skipping"
      fi

      # ── Step 3: Prioritize (haiku) ───────────────────────────────
      CURRENT_STEP="prioritize"

      # Skip prioritize entirely if ingest didn't run and there are no pending tasks.
      # This avoids a wasteful haiku call when nothing has changed.
      PENDING_COUNT=0
      if [ -f TASKS.yaml ]; then
        PENDING_COUNT=$(${yq} '[.tasks[] | select(.status == "pending")] | length' TASKS.yaml 2>/dev/null || ${echo} "0")
      fi
      if [ "$INGEST_RAN" = "false" ] && [ "$PENDING_COUNT" = "0" ]; then
        log "Step 3: Skipping prioritize (no new sources, no pending tasks)"
      else

      PRIORITIZE_HASH_FILE="$STATE_DIR/prioritize-inputs.sha256"
      CURRENT_HASH=""
      if [ -f TASKS.yaml ] && [ -f PROJECTS.yaml ]; then
        CURRENT_HASH=$(${cat} TASKS.yaml PROJECTS.yaml | ${sha256sum} | ${head} -c 64)
      elif [ -f TASKS.yaml ]; then
        CURRENT_HASH=$(${cat} TASKS.yaml | ${sha256sum} | ${head} -c 64)
      fi

      PREVIOUS_HASH=""
      if [ -f "$PRIORITIZE_HASH_FILE" ]; then
        PREVIOUS_HASH=$(${cat} "$PRIORITIZE_HASH_FILE")
      fi

      if [ -n "$CURRENT_HASH" ] && [ "$CURRENT_HASH" = "$PREVIOUS_HASH" ]; then
        log "Step 3: Inputs unchanged, skipping prioritize"
      else
        log "Step 3: Prioritizing tasks via haiku..."
        set +o pipefail
        claude --print --dangerously-skip-permissions --mcp-config "${mcpConfigFile}" --model haiku \
          "/deepwork task_loop prioritize" 2>&1 | ${tee} -a "$LOG_FILE" >&2
        PRIORITIZE_EXIT=''${PIPESTATUS[0]}
        set -o pipefail
        if [ "$PRIORITIZE_EXIT" -ne 0 ]; then
          log "  WARNING: Prioritize step failed, continuing..."
        else
          # Save hash only on success so we retry on failure
          ${echo} -n "$CURRENT_HASH" > "$PRIORITIZE_HASH_FILE"
        fi
      fi
      fi # end INGEST_RAN guard

      # ── Step 4: Execute pending tasks ─────────────────────────────
      # Check for pending tasks after ingest — exit if nothing to execute
      if [ ! -f TASKS.yaml ] || \
         [ "$(${yq} '[.tasks[] | select(.status == "pending")] | length' TASKS.yaml 2>/dev/null)" = "0" ]; then
        log "No pending tasks after ingest, done"
        exit 0
      fi

      CURRENT_STEP="execute"
      log "Step 4: Executing pending tasks (max ${toString maxTasks})..."
      TASK_COUNT=0

      while [ $TASK_COUNT -lt ${toString maxTasks} ]; do
        # Read the first pending task from TASKS.yaml
        TASK_NAME=$(${yq} '[.tasks[] | select(.status == "pending")] | .[0].name' TASKS.yaml 2>/dev/null || ${echo} "null")

        if [ "$TASK_NAME" = "null" ] || [ -z "$TASK_NAME" ]; then
          log "  No more pending tasks"
          break
        fi

        TASK_DESC=$(${yq} "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].description" TASKS.yaml)
        TASK_WORKFLOW=$(${yq} "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].workflow // \"\"" TASKS.yaml)
        TASK_MODEL=$(${yq} "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].model // \"\"" TASKS.yaml)
        TASK_NEEDS=$(${yq} "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].needs // []" TASKS.yaml)

        # Check if task has unmet dependencies
        if [ "$TASK_NEEDS" != "[]" ] && [ "$TASK_NEEDS" != "null" ]; then
          NEEDS_MET=true
          for need in $(${echo} "$TASK_NEEDS" | ${jq} -r '.[]' 2>/dev/null); do
            NEED_STATUS=$(${yq} "[.tasks[] | select(.name == \"$need\")] | .[0].status // \"pending\"" TASKS.yaml)
            if [ "$NEED_STATUS" != "completed" ]; then
              NEEDS_MET=false
              break
            fi
          done
          if [ "$NEEDS_MET" = "false" ]; then
            log "  Skipping $TASK_NAME (unmet dependencies)"
            # Mark as blocked so we don't loop forever
            ${yq} -i "(.tasks[] | select(.name == \"$TASK_NAME\")).status = \"blocked\"" TASKS.yaml
            continue
          fi
        fi

        TASK_COUNT=$((TASK_COUNT + 1))
        TASK_TIMESTAMP=$(${date} +%Y-%m-%d_%H%M%S)
        TASK_LOG="$TASK_LOGS_DIR/''${TASK_TIMESTAMP}_''${TASK_NAME}.log"

        CURRENT_TASK="$TASK_NAME"
        log "  Executing task $TASK_COUNT: $TASK_NAME"

        # Build model flag
        MODEL_FLAG=""
        if [ -n "$TASK_MODEL" ] && [ "$TASK_MODEL" != "null" ]; then
          MODEL_FLAG="--model $TASK_MODEL"
        fi

        # Build prompt
        if [ -n "$TASK_WORKFLOW" ] && [ "$TASK_WORKFLOW" != "null" ] && [ "$TASK_WORKFLOW" != "" ]; then
          PROMPT="/deepwork $TASK_WORKFLOW

      Task: $TASK_NAME
      Description: $TASK_DESC"
        else
          PROMPT="Execute this task.

      Task: $TASK_NAME
      Description: $TASK_DESC"
        fi

        # Execute in a separate claude session
        set +o pipefail
        claude --print --dangerously-skip-permissions --mcp-config "${mcpConfigFile}" $MODEL_FLAG "$PROMPT" 2>&1 | ${tee} "$TASK_LOG" >&2
        TASK_EXIT=''${PIPESTATUS[0]}
        set -o pipefail

        if [ "$TASK_EXIT" -eq 0 ]; then
          ${yq} -i "(.tasks[] | select(.name == \"$TASK_NAME\")).status = \"completed\"" TASKS.yaml
          log "  Task $TASK_NAME completed (log: $TASK_LOG)"
        else
          ${yq} -i "(.tasks[] | select(.name == \"$TASK_NAME\")).status = \"error\"" TASKS.yaml
          log "  Task $TASK_NAME errored (exit $TASK_EXIT, log: $TASK_LOG)"
        fi
      done

      # ── Summary ────────────────────────────────────────────────────
      CURRENT_STEP="summary"
      CURRENT_TASK=""
      END_TIME=$(${date} +%s)
      DURATION=$((END_TIME - START_TIME))
      log "Task loop finished: executed $TASK_COUNT tasks in ''${DURATION}s"

      # ── Rotate old logs (keep last 20) ─────────────────────────────
      for ext in log; do
        ${find} "$LOGS_DIR" -maxdepth 1 -name "*.$ext" -type f | ${sort} -r | while IFS= read -r file; do
          COUNT=$((''${COUNT:-0} + 1))
          if [ $COUNT -gt 20 ]; then
            ${rm} -f "$file"
          fi
        done
      done
    '';

  # Scheduler script: reads SCHEDULES.yaml, creates due tasks, triggers task loop
  # Pure bash, no LLM
  agentSchedulerScript =
    name: agentCfg:
    let
      username = "agent-${name}";
      notesDir = agentCfg.notes.path;
      yq = "${pkgs.yq-go}/bin/yq";
      date = "${pkgs.coreutils}/bin/date";
      mkdir = "${pkgs.coreutils}/bin/mkdir";
      echo = "${pkgs.coreutils}/bin/echo";
      tee = "${pkgs.coreutils}/bin/tee";
      grep = "${pkgs.gnugrep}/bin/grep";
      tr = "${pkgs.coreutils}/bin/tr";
      seq = "${pkgs.coreutils}/bin/seq";
    in
    pkgs.writeShellScript "agent-${name}-scheduler" ''
      set -eo pipefail

      NOTES_DIR="${notesDir}"
      LOGS_DIR="$HOME/.local/state/agent-scheduler/logs"

      ${mkdir} -p "$LOGS_DIR"

      TIMESTAMP=$(${date} +%Y-%m-%d_%H%M%S)
      LOG_FILE="$LOGS_DIR/$TIMESTAMP.log"
      TODAY=$(${date} +%Y-%m-%d)
      DOW=$(${date} +%A | ${tr} '[:upper:]' '[:lower:]')
      DOM=$(${date} +%-d)

      log() {
        ${echo} "[$(${date} '+%H:%M:%S')] $*" | ${tee} -a "$LOG_FILE" >&2
      }

      if [ ! -d "$NOTES_DIR" ]; then
        ${echo} "Notes directory $NOTES_DIR does not exist yet, skipping"
        exit 0
      fi
      cd "$NOTES_DIR"
      log "Starting scheduler for ${name} (date: $TODAY, dow: $DOW, dom: $DOM)"

      if [ ! -f SCHEDULES.yaml ]; then
        log "No SCHEDULES.yaml found, exiting"
        exit 0
      fi

      if [ ! -f TASKS.yaml ]; then
        log "No TASKS.yaml found, creating empty one"
        ${echo} "tasks: []" > TASKS.yaml
      fi

      SCHEDULE_COUNT=$(${yq} '.schedules | length' SCHEDULES.yaml 2>/dev/null || ${echo} "0")
      CREATED=0

      for i in $(${seq} 0 $((SCHEDULE_COUNT - 1))); do
        SCHED_NAME=$(${yq} ".schedules[$i].name" SCHEDULES.yaml)
        SCHED_DESC=$(${yq} ".schedules[$i].description" SCHEDULES.yaml)
        SCHED_SCHEDULE=$(${yq} ".schedules[$i].schedule" SCHEDULES.yaml)
        SCHED_WORKFLOW=$(${yq} ".schedules[$i].workflow" SCHEDULES.yaml)

        # Check if schedule is due today
        IS_DUE=false

        case "$SCHED_SCHEDULE" in
          daily)
            IS_DUE=true
            ;;
          weekly:*)
            TARGET_DAY="''${SCHED_SCHEDULE#weekly:}"
            if [ "$DOW" = "$TARGET_DAY" ]; then
              IS_DUE=true
            fi
            ;;
          monthly:*)
            TARGET_DOM="''${SCHED_SCHEDULE#monthly:}"
            if [ "$DOM" = "$TARGET_DOM" ]; then
              IS_DUE=true
            fi
            ;;
          *)
            log "  Unknown schedule format: $SCHED_SCHEDULE for $SCHED_NAME"
            ;;
        esac

        if [ "$IS_DUE" = "false" ]; then
          continue
        fi

        # Build source_ref for deduplication
        SOURCE_REF="schedule-''${SCHED_NAME}-''${TODAY}"

        # Check if task already exists
        EXISTING=$(${yq} "[.tasks[] | select(.source_ref == \"$SOURCE_REF\")] | length" TASKS.yaml 2>/dev/null || ${echo} "0")

        if [ "$EXISTING" -gt 0 ]; then
          log "  Skipping $SCHED_NAME (already exists: $SOURCE_REF)"
          continue
        fi

        # Append new task to TASKS.yaml
        log "  Creating task: ''${SCHED_NAME}-''${TODAY}"
        ${yq} -i ".tasks += [{
          \"name\": \"''${SCHED_NAME}-$(${date} +%Y-%m-%d)\",
          \"description\": \"$SCHED_DESC\",
          \"status\": \"pending\",
          \"source\": \"schedule\",
          \"source_ref\": \"$SOURCE_REF\",
          \"workflow\": \"$SCHED_WORKFLOW\"
        }]" TASKS.yaml

        CREATED=$((CREATED + 1))
      done

      log "Scheduler finished: created $CREATED tasks"

      # Trigger task loop if we created any tasks
      if [ $CREATED -gt 0 ]; then
        log "Triggering agent-${name}-task-loop.service..."
        systemctl --user start "agent-${name}-task-loop.service" || {
          log "  WARNING: Failed to trigger task loop"
        }
      fi
    '';

  # Build per-agent MCP config JSON with absolute Nix store paths.
  # This ensures MCP servers start reliably regardless of PATH — they use
  # full store paths baked in at build time.
  agentMcpConfig = name: agentCfg:
    let
      mcpJson = builtins.toJSON {
        mcpServers = {
          deepwork = {
            command = "${pkgs.keystone.deepwork}/bin/deepwork";
            args = [ "serve" "--path" "." "--external-runner" "claude" "--platform" "claude" ];
          };
        } // optionalAttrs (agentCfg.chrome.enable && agentCfg.chrome.mcp.enable) {
          chrome-devtools = {
            command = "${pkgs.keystone.chrome-devtools-mcp}/bin/chrome-devtools-mcp";
            args = [ "--browserUrl" "http://127.0.0.1:${toString (globalAgentChromeDebugPort name agentCfg)}" ];
          };
        } // mapAttrs (_: srv: {
          inherit (srv) command args;
        } // optionalAttrs (srv.env != {}) {
          env = srv.env;
        }) agentCfg.mcp.servers;
      };
    in
    pkgs.writeText "agent-${name}-mcp.json" mcpJson;
in
{
  options.keystone.os.agents = mkOption {
    type = types.attrsOf agentSubmodule;
    default = { };
    description = ''
      Agent users with automatic NixOS user creation and home directory isolation.
      Agents are non-interactive users (no password login, no sudo) designed for
      LLM-driven autonomous operation.
    '';
    example = literalExpression ''
      {
        researcher = {
          fullName = "Research Agent";
          email = "researcher@ks.systems";
          # SSH public key declared in keystone.keys."agent-researcher"
        };
      }
    '';
  };

  config = mkMerge [
    (mkIf (osCfg.enable && cfg != { }) (mkMerge [
    # Base agent configuration
    {
      assertions = [
        # All agent UIDs must be unique
        {
          assertion =
            let
              uids = mapAttrsToList (_: a: a.uid) agentsWithUids;
              uniqueUids = unique uids;
            in
            length uids == length uniqueUids;
          message = "All agent UIDs must be unique";
        }
        # Agent UIDs must not collide with human user UIDs
        {
          assertion =
            let
              agentUids = mapAttrsToList (_: a: a.uid) agentsWithUids;
              humanUids = filter (u: u != null) (mapAttrsToList (_: u: u.uid) osCfg.users);
            in
            all (aUid: !elem aUid humanUids) agentUids;
          message = "Agent UIDs must not collide with human user UIDs";
        }
      ];

      # Create the agents group (agents belong here) and agent-admins (human users who manage agents)
      users.groups.agents = { };
      users.groups.agent-admins = { };

      # Allow agent-admins to access agent user dbus sockets for systemctl --user -M
      # systemd-logind creates /run/user/<uid> as 0700; we add an ACL so agent-admins
      # can traverse the directory and connect to the bus socket.
      # For all defined agents.
      systemd.tmpfiles.rules = concatLists (mapAttrsToList (name: _:
        let
          username = "agent-${name}";
          resolved = agentsWithUids.${name};
        in [
          "a /run/user/${toString resolved.uid} - - - - g:agent-admins:x"
          "a /run/user/${toString resolved.uid}/bus - - - - g:agent-admins:rw"
        ]
      ) cfg);

      # SECURITY: The helper script is the sole sudoers target. SETENV is NOT
      # granted — the script hardcodes XDG_RUNTIME_DIR internally. This prevents
      # LD_PRELOAD injection that SETENV would allow. The helper's verb allowlist
      # prevents dangerous systemctl verbs (edit, set-environment, import-environment).
      security.sudo.extraRules = mapAttrsToList (name: _: {
        groups = [ "agent-admins" ];
        runAs = "agent-${name}";
        commands = [
          { command = "${agentSvcHelper name}"; options = [ "NOPASSWD" ]; }
        ];
      }) cfg;

      # agentctl: unified CLI for managing agent services and mail.
      # Dispatches to the per-agent Nix store helper via sudo (no SETENV needed).
      # All defined agents are manageable via agentctl.
      environment.systemPackages = let
        # Nix-generated static lookup: agent name -> helper store path
        agentHelperCases = concatStringsSep "\n" (mapAttrsToList (name: _:
          "          ${name}) HELPER=\"${agentSvcHelper name}\" ;;"
        ) cfg);
        # Nix-generated static lookup: agent name -> notes directory path
        agentNotesCases = concatStringsSep "\n" (mapAttrsToList (name: agentCfg:
          "          ${name}) NOTES_DIR=\"${agentCfg.notes.path}\" ;;"
        ) cfg);
        # Nix-generated static lookup: agent name -> VNC port (all agents, for remote VNC)
        agentVncCases = concatStringsSep "\n" (mapAttrsToList (name: agentCfg:
          "          ${name}) VNC_PORT=\"${toString (globalAgentVncPort name agentCfg)}\" ;;"
        ) cfg);
        # Nix-generated static lookup: agent name -> host (for remote dispatch)
        agentHostCases = concatStringsSep "\n" (mapAttrsToList (name: agentCfg:
          "          ${name}) AGENT_HOST=\"${toString agentCfg.host}\" ;;"
        ) cfg);
        # Nix-generated static lookup: agent name -> provision metadata
        # Bakes agent host, mail.provision flag, and mail server host into the script.
        mailHost = if config.keystone.services.mail.host != null then config.keystone.services.mail.host else "";
        agentProvisionCases = concatStringsSep "\n" (mapAttrsToList (name: agentCfg:
          "          ${name}) PROVISION_AGENT_HOST=\"${toString agentCfg.host}\"; MAIL_PROVISION=${boolToString agentCfg.mail.provision} ;;"
        ) cfg);
        # Nix-generated static lookup: agent name -> MCP config file (absolute Nix store path)
        agentMcpCases = concatStringsSep "\n" (mapAttrsToList (name: agentCfg:
          "          ${name}) MCP_CONFIG=\"${agentMcpConfig name agentCfg}\" ;;"
        ) cfg);
        knownAgents = concatStringsSep ", " (attrNames cfg);

        # Render TASKS.yaml as a sorted table (pending/in_progress first, completed last)
        tasksFormatter = pkgs.writeText "agentctl-tasks-formatter.py" ''
          import sys, re

          lines = sys.stdin.read()

          tasks = []
          current = {}
          in_tasks = False
          for line in lines.splitlines():
              if line.strip() == "tasks:":
                  in_tasks = True
                  continue
              if not in_tasks:
                  continue
              m = re.match(r"^\s+-\s+([\w_]+):\s*(.*)", line)
              if m:
                  if current:
                      tasks.append(current)
                  current = {m.group(1): m.group(2).strip().strip('"').strip("'")}
                  continue
              m = re.match(r"^\s+([\w_]+):\s*(.*)", line)
              if m:
                  current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
          if current:
              tasks.append(current)

          if not tasks:
              print("No tasks found.")
              sys.exit(0)

          # Active tasks first, then completed in reverse order (latest first)
          order = {"in_progress": 0, "pending": 1, "blocked": 2, "error": 3, "completed": 4}
          for i, t in enumerate(tasks):
              t["_orig_idx"] = i
          tasks.sort(key=lambda t: (order.get(t.get("status", ""), 5), -t["_orig_idx"]))

          icons = {"completed": "done", "in_progress": "run ", "pending": "wait", "blocked": "blkd", "error": "err "}

          hdr = ["#", "STATUS", "NAME", "PROJECT", "SOURCE", "MODEL", "DESCRIPTION"]
          rows = []
          for i, t in enumerate(tasks):
              rows.append([
                  str(i + 1),
                  icons.get(t.get("status", ""), t.get("status", "")[:4]),
                  t.get("name", "")[:30],
                  t.get("project", "-")[:15],
                  t.get("source", "-")[:10],
                  t.get("model", "-")[:6],
                  t.get("description", "")[:50],
              ])

          widths = [len(h) for h in hdr]
          for row in rows:
              for j, cell in enumerate(row):
                  widths[j] = max(widths[j], len(cell))

          def fmt(row):
              return "  ".join(cell.ljust(widths[j]) for j, cell in enumerate(row))

          print(fmt(hdr))
          print("  ".join("-" * w for w in widths))
          for row in rows:
              print(fmt(row))
        '';

        agentctl = pkgs.writeShellScriptBin "agentctl" ''
          if [ $# -lt 2 ]; then
            echo "Usage: agentctl <agent-name> <command> [args...]" >&2
            echo "" >&2
            echo "Commands:" >&2
            echo "  <systemctl-verb>  Run systemctl --user as the agent (status, start, stop, ...)" >&2
            echo "  logs              Run journalctl --user as the agent" >&2
            echo "  cron              List the agent's scheduled timers" >&2
            echo "  exec              Run an arbitrary command as the agent" >&2
            echo "  tasks             Show agent tasks in a table (pending/in_progress first)" >&2
            echo "  email             Show the agent's inbox (recent envelopes)" >&2
            echo "  shell             Open interactive shell as the agent (with SSH agent)" >&2
            echo "  claude            Start interactive Claude session in agent notes directory" >&2
            echo "  gemini            Start interactive Gemini session in agent notes directory" >&2
            echo "  codex             Start interactive Codex session in agent notes directory" >&2
            echo "  opencode          Start interactive OpenCode session in agent notes directory" >&2
            echo "  mail              Send structured email to the agent (via agent-mail)" >&2
            echo "  vnc               Open remote-viewer to the agent's VNC desktop" >&2
            echo "  provision         Generate SSH keypair, mail password, and agenix secrets" >&2
            echo "" >&2
            echo "Flags:" >&2
            echo "  -r, --role <mode>      Compose role-specific prompt via .agents/compose.sh (claude)" >&2
            echo "" >&2
            echo "Examples:" >&2
            echo "  agentctl drago status agent-drago-task-loop" >&2
            echo "  agentctl drago logs -u agent-drago-task-loop -n 20" >&2
            echo "  agentctl drago cron" >&2
            echo "  agentctl drago tasks" >&2
            echo "  agentctl drago email" >&2
            echo "  agentctl drago shell" >&2
            echo "  agentctl drago claude" >&2
            echo "  agentctl drago claude -r code-review" >&2
            echo "  agentctl drago gemini" >&2
            echo "  agentctl drago codex" >&2
            echo "  agentctl drago opencode" >&2
            echo "  agentctl drago vnc" >&2
            echo "  agentctl drago mail task --subject \"Fix CI pipeline\"" >&2
            echo "  agentctl drago provision                     # full flow incl. hwrekey" >&2
            echo "  agentctl drago provision --skip-rekey        # skip hwrekey at end" >&2
            exit 1
          fi
          AGENT_NAME="$1"; shift

          # Static lookup — no runtime id(1) call needed
          case "$AGENT_NAME" in
  ${agentHelperCases}
            *)
              echo "Error: unknown agent '$AGENT_NAME'" >&2
              echo "Known agents: ${knownAgents}" >&2
              exit 1
              ;;
          esac

          # Static lookup — agent name -> notes directory
          case "$AGENT_NAME" in
  ${agentNotesCases}
          esac

          # Static lookup — agent name -> VNC port (desktop agents only)
          VNC_PORT=""
          case "$AGENT_NAME" in
  ${agentVncCases}
          esac

          # Resolve agent's host for remote dispatch
          AGENT_HOST=""
          case "$AGENT_NAME" in
  ${agentHostCases}
          esac

          # Static lookup — agent name -> MCP config file (Nix store path)
          MCP_CONFIG=""
          case "$AGENT_NAME" in
  ${agentMcpCases}
          esac

          THIS_HOST="$(cat /etc/hostname)"

          # Remote dispatch: forward non-local commands via SSH over Tailscale.
          # VNC is excluded — it runs locally and connects to the remote host directly.
          # Provision is excluded — it modifies the local agenix-secrets repo.
          if [ -n "$AGENT_HOST" ] && [ "$AGENT_HOST" != "$THIS_HOST" ]; then
            if [ "$1" != "vnc" ] && [ "$1" != "provision" ]; then
              exec ${pkgs.openssh}/bin/ssh -t "$AGENT_HOST" agentctl "$AGENT_NAME" "$@"
            fi
          fi

          CMD="$1"; shift

          # Parse agentctl-level flags (consumed here, not passed to harness)
          ROLE=""
          REMAINING_ARGS=()
          while [[ $# -gt 0 ]]; do
            case "$1" in
              -r|--role) ROLE="$2"; shift 2 ;;
              *) REMAINING_ARGS+=("$1"); shift ;;
            esac
          done
          set -- "''${REMAINING_ARGS[@]}"

          case "$CMD" in
            tasks)
              TASKS_YAML=$(sudo -u "agent-''${AGENT_NAME}" "$HELPER" exec cat "$NOTES_DIR/TASKS.yaml" 2>/dev/null)
              if [ -z "$TASKS_YAML" ]; then
                echo "No TASKS.yaml found in $NOTES_DIR" >&2
                exit 1
              fi
              echo "$TASKS_YAML" | ${pkgs.python3}/bin/python3 ${tasksFormatter}
              ;;
            email)
              exec sudo -u "agent-''${AGENT_NAME}" "$HELPER" exec himalaya envelope list "$@"
              ;;
            shell)
              exec sudo -u "agent-''${AGENT_NAME}" "$HELPER" exec bash -c "cd $NOTES_DIR && exec bash -l"
              ;;
            claude|gemini|codex|opencode)
              # Run directly as the agent, entering devshell if available.
              # For sandboxed runs, use: agentctl <name> exec podman-agent claude
              exec sudo -u "agent-''${AGENT_NAME}" "$HELPER" exec bash -c '
                cd "'"$NOTES_DIR"'"

                # Resolve auto-approve flags per tool
                TOOL_FLAGS=""
                case "'"$CMD"'" in
                  claude) TOOL_FLAGS="--dangerously-skip-permissions --mcp-config '"$MCP_CONFIG"'" ;;
                  gemini) TOOL_FLAGS="--yolo" ;;
                  codex) TOOL_FLAGS="--full-auto" ;;
                esac

                # Claude: compose system prompt from AGENTS.md + optional role
                SP_FLAGS=""
                if [ "'"$CMD"'" = "claude" ]; then
                  SP=""
                  if [ -f AGENTS.md ]; then
                    SP="$(cat AGENTS.md)"
                  fi

                  ROLE="'"$ROLE"'"
                  if [ -n "$ROLE" ]; then
                    if [ -x .agents/compose.sh ] && [ -f manifests/modes.yaml ]; then
                      ROLE_PROMPT="$(PATH="${pkgs.yq-go}/bin:$PATH" .agents/compose.sh manifests/modes.yaml "$ROLE")"
                      if [ -n "$SP" ]; then
                        SP="$SP

$ROLE_PROMPT"
                      else
                        SP="$ROLE_PROMPT"
                      fi
                    else
                      echo "Warning: -r $ROLE requested but .agents/compose.sh or manifests/modes.yaml not found" >&2
                    fi
                  fi

                  if [ -n "$SP" ]; then
                    SP_FLAGS="--append-system-prompt $SP"
                  fi
                fi

                if [ -f flake.nix ]; then
                  # Use git+file with submodules=1 so nix can see git submodules
                  FLAKE_REF="."
                  if [ -f .gitmodules ]; then
                    FLAKE_REF="git+file:.?submodules=1"
                  fi
                  exec nix develop "$FLAKE_REF" --no-update-lock-file --accept-flake-config \
                    --command "'"$CMD"'" $TOOL_FLAGS $SP_FLAGS '"$*"'
                else
                  exec "'"$CMD"'" $TOOL_FLAGS $SP_FLAGS '"$*"'
                fi
              '
              ;;
            mail)
              exec agent-mail "$@" --to "''${AGENT_NAME}@${topDomain}"
              ;;
            provision)
              # Resolve provision metadata (compiled-in)
              PROVISION_AGENT_HOST=""
              MAIL_PROVISION=false
              case "$AGENT_NAME" in
  ${agentProvisionCases}
              esac
              MAIL_HOST="${mailHost}"

              # Parse flags
              SKIP_REKEY=false
              for arg in "$@"; do
                case "$arg" in
                  --skip-rekey) SKIP_REKEY=true ;;
                  *) echo "Error: unknown provision flag '$arg'" >&2; exit 1 ;;
                esac
              done

              USERNAME="agent-''${AGENT_NAME}"

              # Find secrets directory (same convention as hwrekey)
              NIXOS_CONFIG_DIR="''${NIXOS_CONFIG_DIR:-$HOME/nixos-config}"
              SECRETS_DIR="$NIXOS_CONFIG_DIR/agenix-secrets"
              if [ ! -d "$SECRETS_DIR" ]; then
                echo "Error: secrets directory not found: $SECRETS_DIR" >&2
                echo "Set NIXOS_CONFIG_DIR to your nixos-config checkout." >&2
                exit 1
              fi

              TMPDIR=$(${pkgs.coreutils}/bin/mktemp -d)
              trap '${pkgs.coreutils}/bin/rm -rf "$TMPDIR"' EXIT

              echo "==> Provisioning secrets for $USERNAME"

              # --- Step 1: Generate SSH keypair ---
              SSH_KEY="$TMPDIR/ssh-key"
              SSH_PASSPHRASE=$(${pkgs.openssl}/bin/openssl rand -base64 32)
              echo -n "$SSH_PASSPHRASE" > "$TMPDIR/ssh-passphrase"
              ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -C "$USERNAME" \
                -f "$SSH_KEY" -N "$SSH_PASSPHRASE" -q
              echo "==> Generated SSH keypair"
              echo "    Public key: $(cat "$SSH_KEY.pub")"

              # --- Step 2: Generate mail password (if mail.provision) ---
              if [ "$MAIL_PROVISION" = "true" ]; then
                MAIL_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -base64 24)
                echo -n "$MAIL_PASSWORD" > "$TMPDIR/mail-password"
                echo "==> Generated mail password"
              fi

              # --- Step 2b: Generate Bitwarden/Vaultwarden password ---
              BW_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -base64 24)
              echo -n "$BW_PASSWORD" > "$TMPDIR/bitwarden-password"
              echo "==> Generated Bitwarden password"

              # --- Step 3: Insert entries into secrets.nix ---
              SECRETS_NIX="$SECRETS_DIR/secrets.nix"
              if [ ! -f "$SECRETS_NIX" ]; then
                echo "Error: $SECRETS_NIX not found" >&2
                exit 1
              fi

              # Helper: add entry before the final closing brace if not already present
              add_secret() {
                local SECRET_NAME="$1"
                local RECIPIENTS="$2"
                if ${pkgs.gnugrep}/bin/grep -q "\"$SECRET_NAME\"" "$SECRETS_NIX"; then
                  echo "    $SECRET_NAME already exists in secrets.nix, skipping"
                else
                  # Insert before the last closing brace
                  ${pkgs.gnused}/bin/sed -i "/^}$/i\\\\  \"$SECRET_NAME\".publicKeys = $RECIPIENTS;" "$SECRETS_NIX"
                  echo "    Added $SECRET_NAME to secrets.nix"
                fi
              }

              # Determine recipient expression pieces
              # Agent host system key (for himalaya client / ssh-agent)
              AGENT_HOST_EXPR="systems.''${PROVISION_AGENT_HOST}"
              # Mail server host system key (for Stalwart provisioning)
              MAIL_HOST_EXPR=""
              if [ -n "$MAIL_HOST" ] && [ "$MAIL_HOST" != "$PROVISION_AGENT_HOST" ]; then
                MAIL_HOST_EXPR="systems.''${MAIL_HOST}"
              fi

              # SSH key secret: needs admin keys + agent's host
              add_secret "secrets/$USERNAME-ssh-key.age" \
                "adminKeys ++ [ $AGENT_HOST_EXPR ]"

              # SSH passphrase: same recipients as SSH key
              add_secret "secrets/$USERNAME-ssh-passphrase.age" \
                "adminKeys ++ [ $AGENT_HOST_EXPR ]"

              # Mail password: needs admin keys + agent's host + mail server host
              if [ "$MAIL_PROVISION" = "true" ]; then
                if [ -n "$MAIL_HOST_EXPR" ]; then
                  add_secret "secrets/$USERNAME-mail-password.age" \
                    "adminKeys ++ [ $AGENT_HOST_EXPR $MAIL_HOST_EXPR ]"
                else
                  add_secret "secrets/$USERNAME-mail-password.age" \
                    "adminKeys ++ [ $AGENT_HOST_EXPR ]"
                fi
              fi

              # Bitwarden password: needs admin keys + agent's host
              add_secret "secrets/$USERNAME-bitwarden-password.age" \
                "adminKeys ++ [ $AGENT_HOST_EXPR ]"

              # --- Step 4: Validate secrets.nix ---
              echo "==> Validating secrets.nix..."
              if ! ${pkgs.nix}/bin/nix eval --file "$SECRETS_NIX" --json > /dev/null 2>&1; then
                echo "Error: secrets.nix is invalid after modification!" >&2
                echo "Please fix manually: $SECRETS_NIX" >&2
                exit 1
              fi
              echo "    secrets.nix is valid"

              # --- Step 5: Create .age files ---
              echo "==> Creating .age secret files..."
              cd "$SECRETS_DIR"

              create_age_secret() {
                local SECRET_PATH="$1"
                local VALUE_FILE="$2"
                if [ -f "$SECRET_PATH" ]; then
                  echo "    $SECRET_PATH already exists, skipping"
                else
                  EDITOR="cp $VALUE_FILE" agenix -e "$SECRET_PATH"
                  echo "    Created $SECRET_PATH"
                fi
              }

              create_age_secret "secrets/$USERNAME-ssh-key.age" "$SSH_KEY"
              create_age_secret "secrets/$USERNAME-ssh-passphrase.age" "$TMPDIR/ssh-passphrase"
              if [ "$MAIL_PROVISION" = "true" ]; then
                create_age_secret "secrets/$USERNAME-mail-password.age" "$TMPDIR/mail-password"
              fi
              create_age_secret "secrets/$USERNAME-bitwarden-password.age" "$TMPDIR/bitwarden-password"

              # --- Step 6: Print snippets for nixos-config ---
              echo ""
              echo "==> SSH public key (add to keystone.keys in modules/keystone.nix):"
              echo "    keystone.keys.\"$USERNAME\".hosts.<hostname>.publicKey = \"$(cat "$SSH_KEY.pub")\";"
              echo ""
              echo "==> Agenix declarations (add to host config):"
              echo "    age.secrets.$USERNAME-ssh-key = {"
              echo "      file = \"\''${inputs.agenix-secrets}/secrets/$USERNAME-ssh-key.age\";"
              echo "      owner = \"$USERNAME\";"
              echo "      mode = \"0400\";"
              echo "    };"
              echo "    age.secrets.$USERNAME-ssh-passphrase = {"
              echo "      file = \"\''${inputs.agenix-secrets}/secrets/$USERNAME-ssh-passphrase.age\";"
              echo "      owner = \"$USERNAME\";"
              echo "      mode = \"0400\";"
              echo "    };"
              if [ "$MAIL_PROVISION" = "true" ]; then
                echo "    age.secrets.$USERNAME-mail-password = {"
                echo "      file = \"\''${inputs.agenix-secrets}/secrets/$USERNAME-mail-password.age\";"
                echo "      owner = \"$USERNAME\";"
                echo "      mode = \"0400\";"
                echo "    };"
              fi
              echo "    age.secrets.$USERNAME-bitwarden-password = {"
              echo "      file = \"\''${inputs.agenix-secrets}/secrets/$USERNAME-bitwarden-password.age\";"
              echo "      owner = \"$USERNAME\";"
              echo "      mode = \"0400\";"
              echo "    };"

              # --- Step 7: hwrekey (unless --skip-rekey) ---
              if [ "$SKIP_REKEY" = "true" ]; then
                echo ""
                echo "==> Skipping hwrekey (--skip-rekey). Run manually:"
                echo "    hwrekey -m \"provision: create $USERNAME secrets\""
              else
                echo ""
                echo "==> Running hwrekey..."
                hwrekey -m "provision: create $USERNAME secrets"
              fi

              echo ""
              echo "==> Provisioning complete for $USERNAME"
              ;;
            vnc)
              if [ -z "$VNC_PORT" ]; then
                echo "Error: agent '$AGENT_NAME' has no desktop (VNC not available)" >&2
                exit 1
              fi
              # Use agent's host for remote agents, localhost for local ones
              VNC_HOST="localhost"
              if [ -n "$AGENT_HOST" ] && [ "$AGENT_HOST" != "$THIS_HOST" ]; then
                VNC_HOST="$AGENT_HOST"
              fi
              exec ${pkgs.virt-viewer}/bin/remote-viewer "vnc://$VNC_HOST:$VNC_PORT" "$@"
              ;;
            logs|journalctl)
              exec sudo -u "agent-''${AGENT_NAME}" "$HELPER" journalctl -e "$@"
              ;;
            cron)
              exec sudo -u "agent-''${AGENT_NAME}" "$HELPER" list-timers "$@"
              ;;
            *)
              exec sudo -u "agent-''${AGENT_NAME}" "$HELPER" "$CMD" "$@"
              ;;
          esac
        '';
        # Per-agent wrapper scripts: `drago claude` = `agentctl drago claude`
        agentAliases = mapAttrsToList (name: _:
          pkgs.writeShellScriptBin name ''
            exec agentctl "${name}" "$@"
          ''
        ) cfg;
      in [ agentctl ] ++ agentAliases;

      # Discoverable MCP config files for each agent.
      # Human users can reference these to connect to an agent's MCP servers
      # (e.g., an agent's Chrome DevTools instance from their own Claude session).
      environment.etc = mapAttrs' (name: agentCfg:
        nameValuePair "keystone/agent-mcp/${name}.json" {
          source = agentMcpConfig name agentCfg;
          mode = "0444";
        }
      ) cfg;

      # Add all keystone.os.users to agent-admins so they can read agent home dirs
      users.users = mkMerge [
        (mapAttrs (_: _: {
          extraGroups = [ "agent-admins" ];
        }) config.keystone.os.users)

        # Generate NixOS users for all defined agents
        (mapAttrs' (
        name: agentCfg:
        let
          username = "agent-${name}";
          resolved = agentsWithUids.${name};
        in
        nameValuePair username {
          isNormalUser = true;
          uid = resolved.uid;
          description = agentCfg.fullName;
          home = "/home/${username}";
          createHome = !useZfs;
          homeMode = "2770";
          group = "agents";
          extraGroups = optionals useZfs [ "zfs" ];
          shell = pkgs.zsh;
          linger = true;
          openssh.authorizedKeys.keys = allKeysForAgent name;
          # No password -- agents are non-interactive
        }
      ) cfg)
      ];

      # Fix agent home ownership after NixOS user creation (activation runs after useradd)
      # useradd sets group to "agents" (the user's primary group), but we need "agent-admins"
      # so human administrators can read agent home directories.
      # setgid (2xxx) ensures new files inherit agent-admins group.
      # Default ACL ensures new files get group write regardless of umask.
      # For all defined agents.
      system.activationScripts.agent-home-permissions = {
        deps = [ "users" "groups" ];
        text = ''
          ${concatStringsSep "\n" (
            mapAttrsToList (
              name: _:
              let
                username = "agent-${name}";
              in
              ''
                if [ -d /home/${username} ]; then
                  chown ${username}:agent-admins /home/${username}
                  chmod 2770 /home/${username}
                  ${pkgs.acl}/bin/setfacl -d -m g::rwx /home/${username}
                fi
              ''
            ) cfg
          )}
        '';
      };

      # Home directory creation for ext4
      systemd.services.agent-homes = mkIf (!useZfs) {
        description = "Create and configure agent home directories";

        wantedBy = [ "multi-user.target" ];
        before = [ "systemd-user-sessions.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          ${concatStringsSep "\n" (
            mapAttrsToList (
              name: agentCfg:
              let
                username = "agent-${name}";
              in
              ''
                if [ ! -d /home/${username} ]; then
                  mkdir -p /home/${username}
                fi
                chown ${username}:agent-admins /home/${username}
                chmod 2770 /home/${username}
                ${pkgs.acl}/bin/setfacl -d -m g::rwx /home/${username}

                ${labwcConfigScript username agentCfg}
              ''
            ) cfg
          )}
        '';
      };

      /*
      # ZFS dataset creation for agent homes
      # TODO: Re-evaluate ZFS home folder management for agents before re-enabling.
      systemd.services.zfs-agent-datasets = mkIf useZfs {
        description = "Create ZFS datasets for agent home directories";

        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-mount.service" ];
        before = [ "systemd-user-sessions.service" ];
        requires = [ "zfs-mount.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        path = [ config.boot.zfs.package ];

        script = ''
          set -euo pipefail

          # Create parent home dataset if needed
          if ! zfs list -H -o name rpool/crypt/home > /dev/null 2>&1; then
            zfs create -o mountpoint=/home rpool/crypt/home
          fi

          ${concatStringsSep "\n" (
            mapAttrsToList (
              name: agentCfg:
              let
                username = "agent-${name}";
              in
              ''
                zfs create -p -o mountpoint=/home/${username} rpool/crypt/home/${username} 2>/dev/null || true
                zfs set compression=lz4 rpool/crypt/home/${username}
                chown ${username}:agent-admins /home/${username}
                chmod 2770 /home/${username}
                ${pkgs.acl}/bin/setfacl -d -m g::rwx /home/${username}

                ${labwcConfigScript username agentCfg}
              ''
            ) cfg
          )}
        '';
      };
      */
    }

    # Desktop agent configuration (labwc + wayvnc)
    (mkIf hasDesktopAgents {
      assertions = [
        # All VNC ports must be unique
        {
          assertion =
            let
              ports = mapAttrsToList (name: a: agentVncPort name a) desktopAgents;
              uniquePorts = unique ports;
            in
            length ports == length uniquePorts;
          message = "All agent VNC ports must be unique";
        }
      ];

      # Enable labwc system-wide
      programs.labwc.enable = true;

      # System packages for desktop agents
      environment.systemPackages = [
        pkgs.wayvnc
        pkgs.wlr-randr
      ];

      # Systemd target grouping all agent desktop services
      systemd.targets.agent-desktops = {
        description = "All agent headless desktop services";
        wantedBy = [ "multi-user.target" ];
      };

      # labwc + wayvnc services per desktop agent
      systemd.services = mkMerge (
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
            resolved = agentsWithUids.${name};
            uid = resolved.uid;
            port = agentVncPort name agentCfg;
            xdgRuntimeDir = "/run/user/${toString uid}";
          in
          {
            # labwc headless compositor
            "agent-${name}-labwc" = {
              description = "Headless Wayland desktop for agent-${name}";

              wantedBy = [ "agent-desktops.target" ];
              after = [
                (if useZfs then "zfs-agent-datasets.service" else "agent-homes.service")
              ];
              requires = [
                (if useZfs then "zfs-agent-datasets.service" else "agent-homes.service")
              ];

              environment = {
                WLR_BACKENDS = "headless";
                WLR_RENDERER = "pixman";
                WLR_HEADLESS_OUTPUTS = "1";
                WLR_LIBINPUT_NO_DEVICES = "1";
                XDG_RUNTIME_DIR = xdgRuntimeDir;
                XDG_CONFIG_HOME = "/home/${username}/.config";
              };

              serviceConfig = {
                Type = "simple";
                User = username;
                Group = "agents";
                RuntimeDirectory = "user/${toString uid}";
                RuntimeDirectoryMode = "0700";
                ExecStart = "${pkgs.labwc}/bin/labwc";
                Restart = "always";
                RestartSec = 5;
              };
            };

            # wayvnc remote viewing (localhost only -- see module header for security notes)
            "agent-${name}-wayvnc" = {
              description = "VNC server for agent-${name} desktop";

              wantedBy = [ "agent-desktops.target" ];
              after = [ "agent-${name}-labwc.service" ];
              requires = [ "agent-${name}-labwc.service" ];

              environment = {
                WAYLAND_DISPLAY = "wayland-0";
                XDG_RUNTIME_DIR = xdgRuntimeDir;
              };

              serviceConfig = {
                Type = "simple";
                User = username;
                Group = "agents";
                # Poll for Wayland socket instead of fixed sleep — labwc startup
                # time varies; this waits up to 10s with 100ms intervals
                ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 100); do [ -S \"${xdgRuntimeDir}/wayland-0\" ] && exit 0; sleep 0.1; done; echo \"Timed out waiting for Wayland socket\" >&2; exit 1'";
                ExecStart = "${pkgs.wayvnc}/bin/wayvnc ${agentCfg.desktop.vncBind} ${toString port}";
                Restart = "always";
                RestartSec = 5;
              };
            };
          }
        ) desktopAgents
      );
    })

    # Chrome browser configuration (Chromium with remote debugging)
    (mkIf hasChromeAgents {
      assertions = [
        # All Chrome debug ports must be unique
        {
          assertion =
            let
              ports = mapAttrsToList (name: a: agentChromeDebugPort name a) chromeAgents;
              uniquePorts = unique ports;
            in
            length ports == length uniquePorts;
          message = "All agent Chrome debug ports must be unique";
        }
      ];

      # Chromium package available system-wide for chrome agents
      environment.systemPackages = [
        pkgs.chromium
      ];

      # Chromium as system services per chrome agent
      #
      # Why system services and not systemd.user.services:
      # 1. NixOS switch-to-configuration does not manage user services — it only
      #    reloads the user daemon (daemon-reload) but won't start/restart units
      #    added to default.target.wants after the target is already reached.
      # 2. system.activationScripts with `systemctl --user -M user@` fails with
      #    "Transport endpoint is not connected" — machinectl can't reach the
      #    user's D-Bus from PID 1 context during activation.
      # 3. A system-level helper using `runuser` can connect to the user bus, but
      #    the chromium user service's ExecStartPre (Wayland socket poll) times
      #    out because the environment isn't fully forwarded through runuser.
      #
      # System services with User=/Group= work reliably: switch-to-configuration
      # manages restarts, and After=/Requires= on labwc ensures proper ordering.
      systemd.services = mkMerge (
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
            resolved = agentsWithUids.${name};
            uid = resolved.uid;
            debugPort = agentChromeDebugPort name agentCfg;
            xdgRuntimeDir = "/run/user/${toString uid}";
            profileDir = "/home/${username}/.config/chromium-agent";
          in
          {
            "agent-${name}-chromium" = {
              description = "Chromium browser for ${username}";
              after = [ "agent-${name}-labwc.service" ];
              requires = [ "agent-${name}-labwc.service" ];
              wantedBy = [ "agent-desktops.target" ];
              environment = {
                WAYLAND_DISPLAY = "wayland-0";
                XDG_RUNTIME_DIR = xdgRuntimeDir;
                XDG_CONFIG_HOME = "/home/${username}/.config";
              };
              serviceConfig = {
                Type = "simple";
                User = username;
                Group = "agents";
                # Poll for Wayland socket before starting Chromium
                ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 100); do [ -S \"${xdgRuntimeDir}/wayland-0\" ] && exit 0; sleep 0.1; done; echo \"Timed out waiting for Wayland socket\" >&2; exit 1'";
                ExecStart = builtins.concatStringsSep " " [
                  "${pkgs.chromium}/bin/chromium"
                  "--user-data-dir=${profileDir}"
                  "--remote-debugging-port=${toString debugPort}"
                  "--remote-debugging-address=127.0.0.1"
                  "--no-first-run"
                  "--no-default-browser-check"
                  "--disable-gpu"
                  "--enable-features=UseOzonePlatform"
                  "--ozone-platform=wayland"
                ];
                Restart = "always";
                RestartSec = 5;
              };
            };
          }
        ) chromeAgents
      );
    })

    # D-Bus socket race condition fix
    #
    # When nixos-rebuild switch restarts user@UID.service, the old systemd user
    # instance's cleanup ("Closed D-Bus User Message Bus Socket") races with the
    # new instance's setup ("Listening on D-Bus User Message Bus Socket"). Both
    # happen within the same second, and the old instance can delete the socket
    # file the new one just created. This leaves the new instance with a stale
    # file descriptor and no socket at /run/user/UID/bus.
    #
    # Cascading effects: Home Manager activation sees "User systemd daemon not
    # running. Skipping reload." Chromium spams D-Bus errors. agentctl commands
    # all fail with "Failed to connect to user scope bus".
    #
    # This system-level oneshot runs after user@UID.service, waits for the race
    # window to close, and restarts the user service if the socket is missing.
    {
      systemd.services = mkMerge (
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
            resolved = agentsWithUids.${name};
            uid = resolved.uid;
            socket = "/run/user/${toString uid}/bus";
          in
          {
            "agent-${name}-ensure-dbus" = {
              description = "Ensure D-Bus socket exists for ${username}";
              after = [ "user@${toString uid}.service" ];
              requires = [ "user@${toString uid}.service" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                set -euo pipefail

                # Brief wait for the old instance's cleanup to finish (the race window)
                sleep 2

                if [ -S "${socket}" ]; then
                  echo "${username}: D-Bus socket OK"
                  exit 0
                fi

                echo "${username}: D-Bus socket missing at ${socket}, restarting user@${toString uid}.service"
                systemctl restart "user@${toString uid}.service"

                # Wait for socket to appear (max 10s)
                for i in $(seq 1 20); do
                  [ -S "${socket}" ] && { echo "${username}: D-Bus socket restored"; exit 0; }
                  sleep 0.5
                done

                echo "WARNING: ${username}: D-Bus socket still missing after restart" >&2
                exit 1
              '';
            };
          }
        ) cfg
      );
    }

    # Mail configuration (Stalwart account + himalaya CLI)
    (mkIf hasMailAgents {
      assertions = [
        {
          assertion = topDomain != null;
          message = "keystone.domain must be set when agents are defined (mail derives from it)";
        }
      ] ++ (mapAttrsToList (name: agentCfg: let
        mailAddr =
          if agentCfg.mail.address != null then agentCfg.mail.address
          else "agent-${name}@${topDomain}";
      in {
        assertion = config.age.secrets ? "agent-${name}-mail-password";
        message = ''
          Agent '${name}' requires agenix secret "agent-${name}-mail-password".

          1. Create the Stalwart mail account (run on ocean):
             curl -s -u admin:"$(cat /run/agenix/stalwart-admin-password)" \
               http://127.0.0.1:8082/api/principal \
               -H "Content-Type: application/json" \
               -d '{"type":"individual","name":"agent-${name}","secrets":["PASSWORD"],"emails":["${mailAddr}"]}'
             curl -s -u admin:"$(cat /run/agenix/stalwart-admin-password)" \
               http://127.0.0.1:8082/api/principal/agent-${name} -X PATCH \
               -H "Content-Type: application/json" \
               -d '[{"action":"set","field":"roles","value":["user"]}]'

          2. Add to agenix-secrets/secrets.nix:
             "secrets/agent-${name}-mail-password.age".publicKeys = adminKeys ++ [ systems.workstation ];

          3. Create the secret (use the SAME password as step 1):
             cd agenix-secrets && agenix -e secrets/agent-${name}-mail-password.age

          4. Declare in host config:
             age.secrets.agent-${name}-mail-password = {
               file = "${"$"}{inputs.agenix-secrets}/secrets/agent-${name}-mail-password.age";
               owner = "agent-${name}";
               mode = "0400";
             };
        '';
      }) mailAgents);

      # Install himalaya CLI system-wide for mail-enabled agents
      environment.systemPackages = [
        pkgs.keystone.himalaya
      ];
    })

    # Per-agent Tailscale instances
    (mkIf hasTailscaleAgents {
      assertions = mapAttrsToList (name: _: {
        assertion = config.age.secrets ? "agent-${name}-tailscale-auth-key";
        message = ''
          Agent '${name}' requires agenix secret "agent-${name}-tailscale-auth-key".

          1. Create a headscale pre-auth key (run on mercury):
             headscale preauthkeys create --user ${name} --reusable --expiration 87600h
             # Copy the generated key

          2. Add to agenix-secrets/secrets.nix:
             "secrets/agent-${name}-tailscale-auth-key.age".publicKeys = adminKeys ++ [ systems.workstation ];

          3. Create the secret (paste the pre-auth key from step 1):
             cd agenix-secrets && agenix -e secrets/agent-${name}-tailscale-auth-key.age

          4. Declare in host config:
             age.secrets.agent-${name}-tailscale-auth-key = {
               file = "${"$"}{inputs.agenix-secrets}/secrets/agent-${name}-tailscale-auth-key.age";
               owner = "agent-${name}";
               mode = "0400";
             };
        '';
      }) tailscaleAgents;

      # Systemd target grouping all agent tailscale services
      systemd.targets.agent-tailscale = {
        description = "All per-agent tailscaled services";
        wantedBy = [ "multi-user.target" ];
      };

      # Per-agent tailscaled services + wrapper installer
      systemd.services = mkMerge ((
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
            resolved = agentsWithUids.${name};
            uid = resolved.uid;
            fwmark = agentFwmark name;
            stateDir = "/var/lib/tailscale/agent-${name}-tailscaled.state";
            socketPath = "/run/tailscale/agent-${name}-tailscaled.socket";
            tunName = "tailscale-agent-${name}";
            authKeyPath = "/run/agenix/agent-${name}-tailscale-auth-key";
          in
          {
            "agent-${name}-tailscaled" = {
              description = "Tailscale daemon for agent-${name}";

              wantedBy = [ "agent-tailscale.target" ];
              after = [
                "network-online.target"
                "agenix.service"
              ];
              wants = [ "network-online.target" ];
              requires = [ "agenix.service" ];

              serviceConfig = {
                Type = "notify";
                RuntimeDirectory = "tailscale";
                RuntimeDirectoryPreserve = "yes";
                StateDirectory = "tailscale";
                ExecStart = "${pkgs.tailscale}/bin/tailscaled --state=${stateDir} --socket=${socketPath} --tun=${tunName}";
                ExecStartPost = "${pkgs.tailscale}/bin/tailscale --socket=${socketPath} up --auth-key=file:${authKeyPath} --hostname=agent-${name}";
                Restart = "on-failure";
                RestartSec = 5;
              };
            };

            # nftables fwmark rule: route agent UID traffic through its TUN
            "agent-${name}-nftables" = {
              description = "nftables fwmark routing for agent-${name} via ${tunName}";

              wantedBy = [ "agent-tailscale.target" ];
              after = [ "agent-${name}-tailscaled.service" ];
              requires = [ "agent-${name}-tailscaled.service" ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "agent-${name}-nftables-up" ''
                  set -euo pipefail
                  # Create nftables table and chain for agent UID routing
                  ${pkgs.nftables}/bin/nft add table inet agent-${name} 2>/dev/null || true
                  ${pkgs.nftables}/bin/nft add chain inet agent-${name} output "{ type route hook output priority mangle; }" 2>/dev/null || true
                  ${pkgs.nftables}/bin/nft add rule inet agent-${name} output meta skuid ${toString uid} meta mark set ${toString fwmark}

                  # Add ip rule to route fwmarked traffic through the agent's TUN
                  ${pkgs.iproute2}/bin/ip rule add fwmark ${toString fwmark} table ${toString fwmark} priority ${toString fwmark} 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip route add default dev ${tunName} table ${toString fwmark} 2>/dev/null || true
                '';
                ExecStop = pkgs.writeShellScript "agent-${name}-nftables-down" ''
                  ${pkgs.nftables}/bin/nft delete table inet agent-${name} 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip rule del fwmark ${toString fwmark} table ${toString fwmark} 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip route del default dev ${tunName} table ${toString fwmark} 2>/dev/null || true
                '';
              };
            };
          }
        ) tailscaleAgents
      ) ++ [{
        # Install the wrapper into each agent's PATH via /home/agent-{name}/bin
        agent-tailscale-wrappers = {
        description = "Install tailscale CLI wrappers into agent home directories";

        wantedBy = [ "agent-tailscale.target" ];
        after = [
          (if useZfs then "zfs-agent-datasets.service" else "agent-homes.service")
        ];
        requires = [
          (if useZfs then "zfs-agent-datasets.service" else "agent-homes.service")
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          ${concatStringsSep "\n" (
            mapAttrsToList (
              name: agentCfg:
              let
                username = "agent-${name}";
                socketPath = "/run/tailscale/agent-${name}-tailscaled.socket";
              in
              ''
                mkdir -p /home/${username}/bin
                cat > /home/${username}/bin/tailscale <<'WRAPPER'
                #!/bin/sh
                exec ${pkgs.tailscale}/bin/tailscale --socket=${socketPath} "$@"
                WRAPPER
                chmod +x /home/${username}/bin/tailscale
                chown -R ${username}:agents /home/${username}/bin
              ''
            ) tailscaleAgents
          )}
        '';
        };
      }]);
    })

    # SSH agent configuration (ssh-agent + git signing + agenix secrets)
    (mkIf hasSshAgents {
      # Only assert agenix secrets on the agent's host — other hosts (e.g. ocean)
      # import agent-identities for provisioning but don't need SSH key secrets.
      assertions = concatLists (mapAttrsToList (name: agentCfg: let
        username = "agent-${name}";
        isAgentHost = agentCfg.host == config.networking.hostName;
      in optionals isAgentHost [
        {
          assertion = config.age.secrets ? "${username}-ssh-key";
          message = ''
            Agent '${name}' requires agenix secret "${username}-ssh-key".

            1. Generate an SSH key pair for the agent:
               ssh-keygen -t ed25519 -C "${username}" -f /tmp/${username}-ssh-key
               # Enter a passphrase when prompted (you'll need it for the passphrase secret too)

            2. Add the PUBLIC key to the keys registry:
               keystone.keys."${username}".hosts.<hostname>.publicKey = "$(cat /tmp/${username}-ssh-key.pub)";

            3. Add to agenix-secrets/secrets.nix:
               "secrets/${username}-ssh-key.age".publicKeys = adminKeys ++ [ systems.workstation ];

            4. Enroll the PRIVATE key as an agenix secret:
               cd agenix-secrets && cp /tmp/${username}-ssh-key secrets/${username}-ssh-key.age.plain
               agenix -e secrets/${username}-ssh-key.age  # paste the private key contents
               rm /tmp/${username}-ssh-key /tmp/${username}-ssh-key.pub secrets/${username}-ssh-key.age.plain

            5. Declare in host config:
               age.secrets.${username}-ssh-key = {
                 file = "${"$"}{inputs.agenix-secrets}/secrets/${username}-ssh-key.age";
                 owner = "${username}";
                 mode = "0400";
               };
          '';
        }
        {
          assertion = config.age.secrets ? "${username}-ssh-passphrase";
          message = ''
            Agent '${name}' requires agenix secret "${username}-ssh-passphrase".

            1. Add to agenix-secrets/secrets.nix:
               "secrets/${username}-ssh-passphrase.age".publicKeys = adminKeys ++ [ systems.workstation ];

            2. Create the secret (use the SAME passphrase from ssh-keygen):
               cd agenix-secrets && agenix -e secrets/${username}-ssh-passphrase.age

            3. Declare in host config:
               age.secrets.${username}-ssh-passphrase = {
                 file = "${"$"}{inputs.agenix-secrets}/secrets/${username}-ssh-passphrase.age";
                 owner = "${username}";
                 mode = "0400";
               };
          '';
        }
        # Bitwarden/Vaultwarden password — rbw pinentry reads from
        # /run/agenix/agent-{name}-bitwarden-password at runtime. Without
        # this assertion, the build succeeds but rbw silently fails.
        {
          assertion = config.age.secrets ? "${username}-bitwarden-password";
          message = ''
            Agent '${name}' requires agenix secret "${username}-bitwarden-password".

            1. Add to agenix-secrets/secrets.nix:
               "secrets/${username}-bitwarden-password.age".publicKeys = adminKeys ++ [ systems.${agentCfg.host} ];

            2. Create the secret:
               cd agenix-secrets && agenix -e secrets/${username}-bitwarden-password.age

            3. Declare in host config:
               age.secrets.${username}-bitwarden-password = {
                 file = "${"$"}{inputs.agenix-secrets}/secrets/${username}-bitwarden-password.age";
                 owner = "${username}";
                 mode = "0400";
               };

            4. Create a Vaultwarden account for ${username} at
               https://vaultwarden.${if topDomain != null then topDomain else "example.com"}
               using the SAME password as the agenix secret.
          '';
        }
      ]) sshAgents);

      # Enable OpenSSH
      services.openssh.enable = true;

      # ssh-agent + git-config systemd services per SSH-enabled agent
      systemd.services = mkMerge (
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
            resolved = agentsWithUids.${name};
            uid = resolved.uid;
            sshKeyPath = "/run/agenix/${username}-ssh-key";
            sshPassphrasePath = "/run/agenix/${username}-ssh-passphrase";
            homesService =
              if useZfs then "zfs-agent-datasets.service" else "agent-homes.service";
            # Script that outputs the passphrase for SSH_ASKPASS
            askpassScript = pkgs.writeShellScript "ssh-askpass-${username}" ''
              ${pkgs.coreutils}/bin/cat ${sshPassphrasePath}
            '';
            # Script to add the key to the running ssh-agent
            addKeyScript = pkgs.writeShellScript "ssh-add-key-${username}" ''
              # Wait for the ssh-agent socket to be ready
              for i in $(seq 1 50); do
                [ -S "/run/agent-${name}-ssh-agent/agent.sock" ] && break
                sleep 0.1
              done
              export SSH_AUTH_SOCK="/run/agent-${name}-ssh-agent/agent.sock"
              export SSH_ASKPASS="${askpassScript}"
              export SSH_ASKPASS_REQUIRE="force"
              export DISPLAY="none"
              ${pkgs.openssh}/bin/ssh-add ${sshKeyPath}
            '';
          in
          {
            # ssh-agent daemon (foreground mode with -D)
            "agent-${name}-ssh-agent" = {
              description = "SSH agent for ${username}";

              wantedBy = [ "multi-user.target" ];
              after = [ homesService ];
              requires = [ homesService ];

              environment = {
                SSH_AUTH_SOCK = "/run/agent-${name}-ssh-agent/agent.sock";
              };

              serviceConfig = {
                Type = "simple";
                User = username;
                Group = "agents";
                RuntimeDirectory = "agent-${name}-ssh-agent";
                RuntimeDirectoryMode = "0700";
                ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a /run/agent-${name}-ssh-agent/agent.sock";
                ExecStartPost = "${addKeyScript}";
                Restart = "always";
                RestartSec = 5;
              };
            };

            # Git SSH signing is now handled by keystone.terminal via home-manager
            # (git.signingKey + allowed_signers). No separate systemd service needed.
          }
        ) sshAgents
      );
    })

    # Forgejo account + notes repo reminder (warnings, not assertions — Forgejo isn't
    # strictly required for the agent to boot, but notes sync will fail without it)
    # TODO: Re-enable once a `provisioned` option exists to suppress for existing agents.
    /*
    {
      warnings = concatLists (mapAttrsToList (name: agentCfg:
        let
          agentEmail =
            if agentCfg.email != null then agentCfg.email
            else "agent-${name}@${topDomain}";
          pubKey = let pk = agentPublicKey name;
            in if pk != null then pk else "SSH_PUBLIC_KEY";
          repoUrl = agentCfg.notes.repo;
        in
        (optional (agentPublicKey name != null && topDomain != null) ''
          Agent '${name}': Remember to create a Forgejo account at git.${topDomain}.

          Via API (run on ocean):
            TOKEN="$(cat /run/agenix/forgejo-admin-token)"
            curl -s -H "Authorization: token $TOKEN" \
              http://localhost:3001/api/v1/admin/users \
              -H "Content-Type: application/json" \
              -d '{"username":"${name}","email":"${agentEmail}","password":"RANDOM_PASSWORD","must_change_password":false}'

          Then add the agent's SSH key via Forgejo UI or API:
            curl -s -H "Authorization: token $TOKEN" \
              http://localhost:3001/api/v1/admin/users/${name}/keys \
              -H "Content-Type: application/json" \
              -d '{"title":"agent-${name}","key":"${pubKey}"}'
        '')
        ++ (optional (topDomain != null) ''
          Agent '${name}': Remember to create the notes repo for agent-${name}-notes-sync.
          Configured repo URL: ${repoUrl}

          Via API (run on ocean):
            TOKEN="$(cat /run/agenix/forgejo-admin-token)"

            # Create the repo under the agent's Forgejo user:
            curl -s -H "Authorization: token $TOKEN" \
              http://localhost:3001/api/v1/admin/users/${name}/repos \
              -H "Content-Type: application/json" \
              -d '{"name":"agent-space","description":"Notes and task workspace for agent-${name}","private":true,"auto_init":true}'

          Or create manually in Forgejo UI at git.${topDomain}.

          The agent-${name}-notes-sync service will fail until this repo exists and
          the agent's SSH key has push access.
        '')
      ) cfg);
    }
    */

    # Agent notes: sync, task loop, scheduler as systemd.user.services with linger
    {
      # Notes sync via repo-sync (user services for all agents)
      systemd.user.services = mkMerge (
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
          in
          {
            "agent-${name}-notes-sync" = {
              description = "Sync notes repo for ${username}";
              unitConfig.ConditionUser = username;
              serviceConfig = {
                Type = "oneshot";
                SyslogIdentifier = "agent-${name}-notes-sync";
                ExecStart = builtins.concatStringsSep " " [
                  "${pkgs.keystone.repo-sync}/bin/repo-sync"
                  "--repo ${escapeShellArg agentCfg.notes.repo}"
                  "--path ${escapeShellArg agentCfg.notes.path}"
                  "--commit-prefix \"vault sync\""
                  "--log-dir /home/${username}/.local/state/notes-sync/logs"
                ];
              };
              environment = {
                SSH_AUTH_SOCK = "/run/agent-${name}-ssh-agent/agent.sock";
                GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=accept-new";
              };
            };

            "agent-${name}-task-loop" = {
              description = "Autonomous task loop for ${username}";
              unitConfig.ConditionUser = username;
              # Use the agent's full home-manager profile instead of cherry-picking
              # packages. /etc/profiles/per-user/ includes everything from keystone.terminal
              # (himalaya, gh, git, openssh, coreutils, bash, etc.). Nix is added
              # explicitly since it's a system tool not in the home-manager profile.
              environment = {
                PATH = lib.mkForce "/etc/profiles/per-user/${username}/bin:${lib.makeBinPath [ pkgs.nix ]}";
                SSH_AUTH_SOCK = "/run/agent-${name}-ssh-agent/agent.sock";
                GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=accept-new";
              };
              serviceConfig = {
                Type = "oneshot";
                # Agent tasks (e.g. Claude) can run for extended periods; the
                # default 90s timeout would SIGKILL mid-execution, and flock
                # handles concurrency so the timer safely skips overlapping runs.
                TimeoutStartSec = "1h";
                SyslogIdentifier = "agent-${name}-task-loop";
                LogRateLimitIntervalSec = 0;
              };
              script = ''
                exec ${agentTaskLoopScript name agentCfg}
              '';
            };

            "agent-${name}-scheduler" = {
              description = "Daily scheduler for ${username}";
              unitConfig.ConditionUser = username;
              environment.PATH = lib.mkForce "/etc/profiles/per-user/${username}/bin:${lib.makeBinPath [ pkgs.nix ]}";
              serviceConfig = {
                Type = "oneshot";
                SyslogIdentifier = "agent-${name}-scheduler";
              };
              script = ''
                exec ${agentSchedulerScript name agentCfg}
              '';
            };
          }
        ) cfg
      );

      systemd.user.timers = mkMerge (
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
          in
          {
            "agent-${name}-notes-sync" = {
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = username;
              timerConfig = {
                OnCalendar = agentCfg.notes.syncOnCalendar;
                Persistent = true;
              };
            };

            "agent-${name}-task-loop" = {
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = username;
              timerConfig = {
                OnCalendar = agentCfg.notes.taskLoop.onCalendar;
                Persistent = true;
              };
            };

            "agent-${name}-scheduler" = {
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = username;
              timerConfig = {
                OnCalendar = agentCfg.notes.scheduler.onCalendar;
                Persistent = true;
              };
            };
          }
        ) cfg
      );
    }
  ]))

    # Configure home-manager for agents with terminal enabled
    # This requires home-manager to be imported in the system configuration
    # NOTE: This must be a separate mkMerge entry, not merged with // into the
    # mkIf block above. Using // on a mkIf value silently drops the merged keys
    # because the module system only reads the mkIf's `content` attribute.
    (optionalAttrs (options ? home-manager) {
      home-manager = mkIf (osCfg.enable && cfg != {} && any (a: a.terminal.enable) (attrValues cfg)) {
        users = mapAttrs' (name: agentCfg:
          let
            username = "agent-${name}";
          in
          nameValuePair username ({ pkgs, ... }: {
            imports = [ ../terminal/default.nix ];

            # Provide empty keystoneInputs — editor.nix uses it for optional
            # unstable helix and kinda-nvim theme, both degrade gracefully to
            # stable defaults when the attrs are absent.
            _module.args.keystoneInputs = {};

            keystone.terminal = mkIf agentCfg.terminal.enable {
              enable = mkDefault true;
              git = let
                pubKey = agentPublicKey name;
              in {
                userName = mkDefault agentCfg.fullName;
                userEmail = mkDefault (if agentCfg.email != null
                  then agentCfg.email
                  else "${username}@${if topDomain != null then topDomain else "localhost"}");
                # Bridge SSH keys from keystone.keys for allowed_signers + signing
                sshPublicKeys = mkDefault (allKeysForAgent name);
                signingKey = mkDefault (
                  if pubKey != null then "key::${pubKey}" else "~/.ssh/id_ed25519"
                );
                forgejo = {
                  enable = mkDefault (config.keystone.services.git.host != null);
                  domain = mkDefault config.keystone.services.git.domain;
                  sshPort = mkDefault config.keystone.services.git.sshPort;
                  # Use agent's Forgejo username, not the system username
                  username = mkDefault agentCfg.git.username;
                };
              };
              mail = {
                enable = mkDefault true;
                accountName = mkDefault name;
                email = mkDefault (if agentCfg.mail.address != null
                  then agentCfg.mail.address
                  else "${username}@${if topDomain != null then topDomain else "localhost"}");
                displayName = mkDefault agentCfg.fullName;
                login = mkDefault username;
                host = mkDefault (if topDomain != null then "mail.${topDomain}" else "");
                # CRITICAL: agenix secrets and most editors add a trailing newline.
                # Stalwart rejects passwords with trailing whitespace, so we must
                # strip it. Without this, IMAP/SMTP auth fails.
                # tr is available via the agent's home-manager profile PATH (coreutils).
                passwordCommand = mkDefault "tr -d '\\n' < /run/agenix/agent-${name}-mail-password";
                imap.port = mkDefault agentCfg.mail.imap.port;
                smtp.port = mkDefault agentCfg.mail.smtp.port;
              };
              calendar = {
                enable = mkDefault true;
                # All credentials auto-derived from mail config above
              };
              contacts = {
                enable = mkDefault true;
                # All credentials auto-derived from mail config above
              };
              secrets = {
                enable = mkDefault true;
                email = mkDefault (if agentCfg.email != null
                  then agentCfg.email
                  else "${username}@${if topDomain != null then topDomain else "localhost"}");
                baseUrl = mkDefault (if topDomain != null then "https://vaultwarden.${topDomain}" else "");
                # Agents are unattended — use a custom pinentry that reads the master
                # password from the agenix secret instead of prompting interactively.
                pinentry = pkgs.writeShellScriptBin "rbw-pinentry-agenix" ''
                  echo "OK Pleased to meet you"
                  while IFS= read -r line; do
                    case "$line" in
                      GETPIN)
                        printf "D %s\n" "$(tr -d '\n' < /run/agenix/agent-${name}-bitwarden-password)"
                        echo "OK"
                        ;;
                      BYE)
                        echo "OK closing connection"
                        exit 0
                        ;;
                      *)
                        echo "OK"
                        ;;
                    esac
                  done
                '';
              };
            };

            home.stateVersion = config.system.stateVersion;
          })
        ) (filterAttrs (_: a: a.terminal.enable) cfg);
      };
    })
  ];
}
