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
#     ssh.publicKey = "ssh-ed25519 AAAAC3...";
#   };
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
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.agents;
  topDomain = config.keystone.domain;

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

        desktop = {
          enable = mkEnableOption "Headless Wayland desktop";

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
          enable = mkEnableOption "Chrome remote debugging";

          debugPort = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "Chrome remote debugging port. If null, auto-assigned starting from 9222.";
          };

          mcp = {
            port = mkOption {
              type = types.nullOr types.port;
              default = null;
              description = "Chrome DevTools MCP server port. If null, auto-assigned starting from 3101.";
            };
          };
        };

        mail = {
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

        bitwarden = {
          collection = mkOption {
            type = types.str;
            default = "agent-${name}";
            description = "Bitwarden collection name scoped to this agent";
          };
        };

        # Tailscale: each agent gets its own tailscaled instance with unique
        # state dir, socket, and TUN interface. An nftables fwmark rule routes
        # the agent's UID traffic through its dedicated TUN.
        # Requires an agenix secret at age.secrets."agent-{name}-tailscale-auth-key".

        # SSH: each agent gets ssh-agent + git signing + agenix secrets.
        # Requires agenix secrets: agent-{name}-ssh-key, agent-{name}-ssh-passphrase.
        ssh = {
          publicKey = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              SSH public key for this agent. Added to the agent's
              ~/.ssh/authorized_keys for sandbox access. Also used as
              the git signing key.
            '';
            example = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... agent-researcher";
          };
        };

        notes = {
          repo = mkOption {
            type = types.str;
            description = "Git repository URL for the agent's notes. Cloned to /home/agent-{name}/notes/.";
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

  # All agents get desktop (labwc + wayvnc)
  desktopAgents = cfg;
  hasDesktopAgents = cfg != { };

  # All agents get mail, bitwarden, and SSH
  mailAgents = cfg;
  hasMailAgents = cfg != { };

  bitwardenAgents = cfg;
  hasBitwardenAgents = cfg != { };

  sshAgents = cfg;
  hasSshAgents = cfg != { };

  # Sorted desktop agent names for deterministic VNC port assignment
  sortedDesktopAgentNames = sort lessThan (attrNames desktopAgents);

  # Resolve VNC port for a desktop agent
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

  # All agents get Chrome with remote debugging
  chromeAgents = cfg;
  hasChromeAgents = cfg != { };

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

  # Generate himalaya config.toml for a mail-enabled agent
  himalayaConfig =
    name: agentCfg:
    let
      username = "agent-${name}";
      mailAddr =
        if agentCfg.mail.address != null then agentCfg.mail.address
        else "agent-${name}@${topDomain}";
      mailHost = "mail.${topDomain}";
      imapPort = agentCfg.mail.imap.port;
      smtpPort = agentCfg.mail.smtp.port;
      secretPath = "/run/agenix/agent-${name}-mail-password";
    in
    pkgs.writeText "himalaya-config-agent-${name}.toml" ''
      [accounts.${name}]
      email = "${mailAddr}"
      display-name = "${agentCfg.fullName}"
      default = true

      backend.type = "imap"
      backend.host = "${mailHost}"
      backend.port = ${toString imapPort}
      backend.encryption.type = "tls"
      backend.login = "${username}"
      backend.auth.type = "password"
      backend.auth.command = "cat ${secretPath}"

      message.send.backend.type = "smtp"
      message.send.backend.host = "${mailHost}"
      message.send.backend.port = ${toString smtpPort}
      message.send.backend.encryption.type = "tls"
      message.send.backend.login = "${username}"
      message.send.backend.auth.type = "password"
      message.send.backend.auth.command = "cat ${secretPath}"

      # Stalwart folder names (differ from Himalaya defaults)
      folder.aliases.sent = "Sent Items"
      folder.aliases.drafts = "Drafts"
      folder.aliases.trash = "Deleted Items"
    '';

  # Generate himalaya config setup script for home directory creation
  himalayaConfigScript =
    username: agentCfg: name:
    ''
      # Create himalaya config directory
      mkdir -p /home/${username}/.config/himalaya
      cp ${himalayaConfig name agentCfg} /home/${username}/.config/himalaya/config.toml
      chmod 600 /home/${username}/.config/himalaya/config.toml
      chown -R ${username}:agents /home/${username}/.config/himalaya
    '';

  # Task loop script: pre-fetch sources, ingest, prioritize, execute
  # Runs inside nix develop --command to get the agent's dev shell
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
    in
    pkgs.writeShellScript "agent-task-loop-${name}" ''
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

      log() {
        ${echo} "[$(${date} '+%H:%M:%S')] $*" | ${tee} -a "$LOG_FILE"
      }

      # Lock to prevent concurrent runs
      if ${mkdir} "$LOCKFILE" 2>/dev/null; then
        ${echo} $$ > "$LOCKFILE/pid"
        trap '${rm} -rf "$LOCKFILE"' EXIT
      else
        ${echo} "Task loop already running (lockfile exists), skipping"
        exit 0
      fi

      if [ ! -d "$NOTES_DIR" ]; then
        ${echo} "Notes directory $NOTES_DIR does not exist yet, skipping"
        exit 0
      fi
      cd "$NOTES_DIR"
      log "Starting agent task loop for ${name}"

      # ── Step 1: Pre-fetch sources ─────────────────────────────────
      log "Step 1: Pre-fetching sources from PROJECTS.yaml..."
      SOURCES_JSON="[]"

      if [ -f PROJECTS.yaml ]; then
        SOURCE_COUNT=$(${yq} '.sources | length' PROJECTS.yaml 2>/dev/null || ${echo} "0")

        for i in $(${seq} 0 $((SOURCE_COUNT - 1))); do
          SOURCE_NAME=$(${yq} ".sources[$i].name" PROJECTS.yaml)
          SOURCE_CMD=$(${yq} ".sources[$i].command" PROJECTS.yaml)

          if [ -n "$SOURCE_CMD" ] && [ "$SOURCE_CMD" != "null" ]; then
            log "  Fetching source: $SOURCE_NAME"
            # Run via nix develop to get dev shell tools (himalaya, gh, etc.)
            SOURCE_OUTPUT=$(nix develop --command bash -c "$SOURCE_CMD" 2>>"$LOG_FILE" || ${echo} "[]")
            SOURCES_JSON=$(${echo} "$SOURCES_JSON" | ${jq} --arg name "$SOURCE_NAME" --argjson data "$SOURCE_OUTPUT" \
              '. + [{"source": $name, "data": $data}]')
          fi
        done
      fi

      log "  Collected sources: $(${echo} "$SOURCES_JSON" | ${jq} 'length') entries"

      # ── Step 2: Ingest (haiku) ────────────────────────────────────
      log "Step 2: Ingesting sources via haiku..."
      if [ "$(${echo} "$SOURCES_JSON" | ${jq} '[.[].data | length] | add // 0')" -gt 0 ]; then
        nix develop --command claude --print --model haiku \
          "/deepwork task_loop ingest

      Source data (pre-fetched):
      $(${echo} "$SOURCES_JSON" | ${jq} '.')" >> "$LOG_FILE" 2>&1 || {
          log "  WARNING: Ingest step failed, continuing..."
        }
      else
        log "  No source data to ingest, skipping"
      fi

      # ── Step 3: Prioritize (haiku) ───────────────────────────────
      log "Step 3: Prioritizing tasks via haiku..."
      nix develop --command claude --print --model haiku \
        "/deepwork task_loop prioritize" >> "$LOG_FILE" 2>&1 || {
        log "  WARNING: Prioritize step failed, continuing..."
      }

      # ── Step 4: Execute pending tasks ─────────────────────────────
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
          PROMPT="Execute this task and update its status in TASKS.yaml when done.

      Task: $TASK_NAME
      Description: $TASK_DESC"
        fi

        # Execute in a separate claude session
        nix develop --command claude --print $MODEL_FLAG "$PROMPT" > "$TASK_LOG" 2>&1 || {
          log "  WARNING: Task $TASK_NAME execution failed (see $TASK_LOG)"
        }

        log "  Task $TASK_NAME finished (log: $TASK_LOG)"
      done

      # ── Summary ────────────────────────────────────────────────────
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
    pkgs.writeShellScript "agent-scheduler-${name}" ''
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
        ${echo} "[$(${date} '+%H:%M:%S')] $*" | ${tee} -a "$LOG_FILE"
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
        log "Triggering agent-task-loop-${name}.service..."
        systemctl --user start "agent-task-loop-${name}.service" || {
          log "  WARNING: Failed to trigger task loop"
        }
      fi
    '';
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
          ssh.publicKey = "ssh-ed25519 AAAAC3...";
        };
      }
    '';
  };

  config = mkIf (osCfg.enable && cfg != { }) (mkMerge [
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

      # Add all keystone.os.users to agent-admins so they can read agent home dirs
      users.users = mkMerge [
        (mapAttrs (_: _: {
          extraGroups = [ "agent-admins" ];
        }) config.keystone.os.users)

        # Generate NixOS users for agents
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
          homeMode = "750";
          group = "agents";
          extraGroups = optionals useZfs [ "zfs" ];
          shell = pkgs.zsh;
          linger = true;
          openssh.authorizedKeys.keys =
            optional (agentCfg.ssh.publicKey != null) agentCfg.ssh.publicKey;
          # No password -- agents are non-interactive
        }
      ) cfg)
      ];

      # Fix agent home ownership after NixOS user creation (activation runs after useradd)
      # useradd sets group to "agents" (the user's primary group), but we need "agent-admins"
      # so human administrators can read agent home directories.
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
                  chmod 750 /home/${username}
                fi
              ''
            ) cfg
          )}
        '';
      };

      # Home directory creation for ext4
      systemd.services.create-agent-homes = mkIf (!useZfs) {
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
                chmod 750 /home/${username}

                ${labwcConfigScript username agentCfg}
                ${himalayaConfigScript username agentCfg name}
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
                chmod 750 /home/${username}

                ${labwcConfigScript username agentCfg}
                ${himalayaConfigScript username agentCfg name}
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
            "labwc-agent-${name}" = {
              description = "Headless Wayland desktop for agent-${name}";

              wantedBy = [ "agent-desktops.target" ];
              after = [
                (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
              ];
              requires = [
                (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
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
            "wayvnc-agent-${name}" = {
              description = "VNC server for agent-${name} desktop";

              wantedBy = [ "agent-desktops.target" ];
              after = [ "labwc-agent-${name}.service" ];
              requires = [ "labwc-agent-${name}.service" ];

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
            "chromium-agent-${name}" = {
              description = "Chromium browser for ${username}";
              after = [ "labwc-agent-${name}.service" ];
              requires = [ "labwc-agent-${name}.service" ];
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

    # Mail configuration (Stalwart account + himalaya CLI)
    (mkIf hasMailAgents {
      assertions = [
        {
          assertion = topDomain != null;
          message = "keystone.domain must be set when agents are defined (mail derives from it)";
        }
      ] ++ (mapAttrsToList (name: _: {
        assertion = config.age.secrets ? "agent-${name}-mail-password";
        message = "Agent '${name}' requires age.secrets.\"agent-${name}-mail-password\" to be declared";
      }) mailAgents);

      # Install himalaya CLI system-wide for mail-enabled agents
      environment.systemPackages = [
        pkgs.keystone.himalaya
      ];
    })

    # Bitwarden/Vaultwarden agent configuration
    (mkIf hasBitwardenAgents {
      assertions = [
        {
          assertion = topDomain != null;
          message = "keystone.domain must be set when agents are defined (bitwarden derives from it)";
        }
      ] ++ (mapAttrsToList (name: _: {
        assertion = config.age.secrets ? "agent-${name}-bitwarden-password";
        message = "Agent '${name}' requires age.secrets.\"agent-${name}-bitwarden-password\" to be declared";
      }) bitwardenAgents);

      # Install bitwarden-cli for agents with bitwarden enabled
      environment.systemPackages = [
        pkgs.bitwarden-cli
      ];

      # Configure bw CLI server URL per bitwarden-enabled agent
      systemd.services = mkMerge (
        mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
          in
          {
            "bitwarden-config-agent-${name}" = {
              description = "Configure Bitwarden CLI for agent-${name}";

              wantedBy = [ "multi-user.target" ];
              after = [
                (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
              ];
              requires = [
                (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
              ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = username;
                Group = "agents";
              };

              script = ''
                # Configure bw CLI to use the Vaultwarden server
                ${pkgs.bitwarden-cli}/bin/bw config server https://vault.${topDomain}
              '';
            };
          }
        ) bitwardenAgents
      );
    })

    # Per-agent Tailscale instances
    (mkIf hasTailscaleAgents {
      assertions = mapAttrsToList (name: _: {
        assertion = config.age.secrets ? "agent-${name}-tailscale-auth-key";
        message = "Agent '${name}' requires age.secrets.\"agent-${name}-tailscale-auth-key\" to be declared";
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
            stateDir = "/var/lib/tailscale/tailscaled-agent-${name}.state";
            socketPath = "/run/tailscale/tailscaled-agent-${name}.socket";
            tunName = "tailscale-agent-${name}";
            authKeyPath = "/run/agenix/agent-${name}-tailscale-auth-key";
          in
          {
            "tailscaled-agent-${name}" = {
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
            "nftables-agent-${name}" = {
              description = "nftables fwmark routing for agent-${name} via ${tunName}";

              wantedBy = [ "agent-tailscale.target" ];
              after = [ "tailscaled-agent-${name}.service" ];
              requires = [ "tailscaled-agent-${name}.service" ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "nftables-agent-${name}-up" ''
                  set -euo pipefail
                  # Create nftables table and chain for agent UID routing
                  ${pkgs.nftables}/bin/nft add table inet agent-${name} 2>/dev/null || true
                  ${pkgs.nftables}/bin/nft add chain inet agent-${name} output "{ type route hook output priority mangle; }" 2>/dev/null || true
                  ${pkgs.nftables}/bin/nft add rule inet agent-${name} output meta skuid ${toString uid} meta mark set ${toString fwmark}

                  # Add ip rule to route fwmarked traffic through the agent's TUN
                  ${pkgs.iproute2}/bin/ip rule add fwmark ${toString fwmark} table ${toString fwmark} priority ${toString fwmark} 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip route add default dev ${tunName} table ${toString fwmark} 2>/dev/null || true
                '';
                ExecStop = pkgs.writeShellScript "nftables-agent-${name}-down" ''
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
          (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
        ];
        requires = [
          (if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service")
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
                socketPath = "/run/tailscale/tailscaled-agent-${name}.socket";
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
      assertions = concatLists (mapAttrsToList (name: _: let
        username = "agent-${name}";
      in [
        {
          assertion = config.age.secrets ? "${username}-ssh-key";
          message = "Agent '${name}' requires age.secrets.\"${username}-ssh-key\" to be declared";
        }
        {
          assertion = config.age.secrets ? "${username}-ssh-passphrase";
          message = "Agent '${name}' requires age.secrets.\"${username}-ssh-passphrase\" to be declared";
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
              if useZfs then "zfs-agent-datasets.service" else "create-agent-homes.service";
            # Script that outputs the passphrase for SSH_ASKPASS
            askpassScript = pkgs.writeShellScript "ssh-askpass-${username}" ''
              ${pkgs.coreutils}/bin/cat ${sshPassphrasePath}
            '';
            # Script to add the key to the running ssh-agent
            addKeyScript = pkgs.writeShellScript "ssh-add-key-${username}" ''
              # Wait for the ssh-agent socket to be ready
              for i in $(seq 1 50); do
                [ -S "/run/ssh-agent-${username}/agent.sock" ] && break
                sleep 0.1
              done
              export SSH_AUTH_SOCK="/run/ssh-agent-${username}/agent.sock"
              export SSH_ASKPASS="${askpassScript}"
              export SSH_ASKPASS_REQUIRE="force"
              export DISPLAY="none"
              ${pkgs.openssh}/bin/ssh-add ${sshKeyPath}
            '';
          in
          {
            # ssh-agent daemon (foreground mode with -D)
            "ssh-agent-${username}" = {
              description = "SSH agent for ${username}";

              wantedBy = [ "multi-user.target" ];
              after = [ homesService ];
              requires = [ homesService ];

              environment = {
                SSH_AUTH_SOCK = "/run/ssh-agent-${username}/agent.sock";
              };

              serviceConfig = {
                Type = "simple";
                User = username;
                Group = "agents";
                RuntimeDirectory = "ssh-agent-${username}";
                RuntimeDirectoryMode = "0700";
                ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a /run/ssh-agent-${username}/agent.sock";
                ExecStartPost = "${addKeyScript}";
                Restart = "always";
                RestartSec = 5;
              };
            };

            # Git SSH signing configuration
            "git-config-${username}" = {
              description = "Configure git SSH signing for ${username}";

              wantedBy = [ "multi-user.target" ];
              after = [ homesService ];
              requires = [ homesService ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = username;
                Group = "agents";
              };

              script = ''
                ${pkgs.git}/bin/git config --global gpg.format ssh
                ${pkgs.git}/bin/git config --global user.signingkey "${sshKeyPath}"
                ${pkgs.git}/bin/git config --global commit.gpgsign true
                ${pkgs.git}/bin/git config --global tag.gpgsign true
                ${pkgs.git}/bin/git config --global user.name "${agentCfg.fullName}"
                ${optionalString (agentCfg.email != null) ''
                  ${pkgs.git}/bin/git config --global user.email "${agentCfg.email}"
                ''}
              '';
            };
          }
        ) sshAgents
      );
    })

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
            "sync-agent-notes-${name}" = {
              description = "Sync notes repo for ${username}";
              unitConfig.ConditionUser = username;
              serviceConfig = {
                Type = "oneshot";
                ExecStart = builtins.concatStringsSep " " [
                  "${pkgs.keystone.repo-sync}/bin/repo-sync"
                  "--repo ${escapeShellArg agentCfg.notes.repo}"
                  "--path ${escapeShellArg agentCfg.notes.path}"
                  "--commit-prefix \"vault sync\""
                  "--log-dir /home/${username}/.local/state/notes-sync/logs"
                ];
              };
              environment = {
                SSH_AUTH_SOCK = "/run/ssh-agent-${username}/agent.sock";
              };
            };

            "agent-task-loop-${name}" = {
              description = "Autonomous task loop for ${username}";
              unitConfig.ConditionUser = username;
              path = [ pkgs.openssh pkgs.nix pkgs.git ];
              environment = {
                SSH_AUTH_SOCK = "/run/ssh-agent-${username}/agent.sock";
                GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=accept-new";
              };
              serviceConfig = {
                Type = "oneshot";
                TimeoutStartSec = "30min";
              };
              script = ''
                exec ${agentTaskLoopScript name agentCfg}
              '';
            };

            "agent-scheduler-${name}" = {
              description = "Daily scheduler for ${username}";
              unitConfig.ConditionUser = username;
              path = [ pkgs.yq-go pkgs.coreutils pkgs.gnugrep ];
              serviceConfig = {
                Type = "oneshot";
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
            "sync-agent-notes-${name}" = {
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = username;
              timerConfig = {
                OnCalendar = agentCfg.notes.syncOnCalendar;
                Persistent = true;
              };
            };

            "agent-task-loop-${name}" = {
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = username;
              timerConfig = {
                OnCalendar = agentCfg.notes.taskLoop.onCalendar;
                Persistent = true;
              };
            };

            "agent-scheduler-${name}" = {
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
  ]);
}
