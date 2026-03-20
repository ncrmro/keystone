#!/usr/bin/env bash
# agentctl: unified CLI for managing agent services and mail.
# Dispatches to the per-agent Nix store helper via sudo (no SETENV needed).
# All defined agents are manageable via agentctl.

# Paths substituted by NixOS module via pkgs.replaceVars
PYTHON3="@python3@"
TASKS_FORMATTER="@tasksFormatter@"
OPENSSH="@openssh@"
VIRT_VIEWER="@virtViewer@"
YQ_BIN="@yqBin@"
TOP_DOMAIN="@topDomain@"
MAIL_HOST="@mailHost@"
OPENSSL="@openssl@"
COREUTILS="@coreutils@"
GNUGREP="@gnugrep@"
GNUSED="@gnused@"
NIX="@nix@"
ZELLIJ="@zellij@"
PODMAN_AGENT="@podmanAgent@"

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
  echo "  claude            Start interactive Claude session (supports --project, --role, --roles)" >&2
  echo "  gemini            Start interactive Gemini session (supports --project, --role, --roles)" >&2
  echo "  codex             Start interactive Codex session (supports --project, --role, --roles)" >&2
  echo "  opencode          Start interactive OpenCode session (supports --project, --role, --roles)" >&2
  echo "  mail              Send structured email to the agent (via agent-mail)" >&2
  echo "  vnc               Open remote-viewer to the agent's VNC desktop" >&2
  echo "  provision         Generate SSH keypair, mail password, and agenix secrets" >&2
  echo "" >&2
  echo "Flags:" >&2
  echo "  -r, --role <mode>      Compose role-specific prompt via .agents/compose.sh" >&2
  echo "  --roles <role1,...>    Comma-separated extra roles appended after mode roles" >&2
  echo "  -p, --project <slug>   Run in project context with zellij session" >&2
  echo "  --nosandbox            Disable Podman sandbox; run AI tool directly (current host behavior)" >&2
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
  echo "  agentctl drago claude --roles software-engineer,code-reviewer" >&2
  echo "  agentctl drago claude -r implementation --roles software-engineer" >&2
  echo "  agentctl drago claude --project nixos-config fix-auth" >&2
  echo "  agentctl drago claude --project nixos-config              # list sessions" >&2
  echo "  agentctl drago gemini -r code-review" >&2
  echo "  agentctl drago gemini --project nixos-config fix-auth" >&2
  echo "  agentctl drago codex --project nixos-config fix-auth" >&2
  echo "  agentctl drago opencode --project nixos-config fix-auth" >&2
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
@agentHelperCases@
  *)
    echo "Error: unknown agent '$AGENT_NAME'" >&2
    echo "Known agents: @knownAgents@" >&2
    exit 1
    ;;
esac

# Static lookup — agent name -> notes directory
case "$AGENT_NAME" in
@agentNotesCases@
esac

# Static lookup — agent name -> VNC port (desktop agents only)
VNC_PORT=""
case "$AGENT_NAME" in
@agentVncCases@
esac

# Resolve agent's host for remote dispatch
AGENT_HOST=""
case "$AGENT_NAME" in
@agentHostCases@
esac

THIS_HOST="$(cat /etc/hostname)"

# Remote dispatch: forward non-local commands via SSH over Tailscale.
# VNC is excluded — it runs locally and connects to the remote host directly.
# Provision is excluded — it modifies the local agenix-secrets repo.
if [ -n "$AGENT_HOST" ] && [ "$AGENT_HOST" != "$THIS_HOST" ]; then
  if [ "$1" != "vnc" ] && [ "$1" != "provision" ]; then
    exec "$OPENSSH"/bin/ssh -t "$AGENT_HOST" agentctl "$AGENT_NAME" "$@"
  fi
fi

CMD="$1"; shift

# Parse agentctl-level flags (consumed here, not passed to harness)
ROLE=""
EXTRA_ROLES=""
PROJECT=""
NOSANDBOX=""
REMAINING_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role) ROLE="$2"; shift 2 ;;
    --roles) EXTRA_ROLES="$2"; shift 2 ;;
    -p|--project) PROJECT="$2"; shift 2 ;;
    --nosandbox) NOSANDBOX=1; shift ;;
    *) REMAINING_ARGS+=("$1"); shift ;;
  esac
done
set -- "${REMAINING_ARGS[@]}"

case "$CMD" in
  tasks)
    TASKS_YAML=$(sudo -u "agent-${AGENT_NAME}" "$HELPER" exec cat "$NOTES_DIR/TASKS.yaml" 2>/dev/null)
    if [ -z "$TASKS_YAML" ]; then
      echo "No TASKS.yaml found in $NOTES_DIR" >&2
      exit 1
    fi
    echo "$TASKS_YAML" | "$PYTHON3" "$TASKS_FORMATTER"
    ;;
  email)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" exec himalaya envelope list "$@"
    ;;
  shell)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" exec bash -c "cd $NOTES_DIR && exec bash -l"
    ;;
  claude|gemini|codex|opencode)
    # --- Project + zellij session wrapping (all AI tools) ---
    if [ -n "$PROJECT" ]; then
      # Session slug is the first positional argument
      SESSION_SLUG="${1:-}"
      if [ -z "$SESSION_SLUG" ]; then
        echo "Usage: agentctl $AGENT_NAME $CMD --project <slug> <session-slug>" >&2
        echo "" >&2
        echo "Existing sessions for '$PROJECT':" >&2
        "$ZELLIJ" list-sessions -n 2>/dev/null | "$GNUGREP"/bin/grep "^${PROJECT}-" || echo "  (none)" >&2
        exit 1
      fi
      shift  # consume session slug

      # Lookup project in PROJECTS.yaml
      PROJECT_PATH=$(sudo -u "agent-${AGENT_NAME}" "$HELPER" exec "$YQ_BIN" e \
        ".projects[] | select(.slug == \"$PROJECT\") | .path" "$NOTES_DIR/PROJECTS.yaml" 2>/dev/null)
      PROJECT_NAME=$(sudo -u "agent-${AGENT_NAME}" "$HELPER" exec "$YQ_BIN" e \
        ".projects[] | select(.slug == \"$PROJECT\") | .name" "$NOTES_DIR/PROJECTS.yaml" 2>/dev/null)
      PROJECT_DESC=$(sudo -u "agent-${AGENT_NAME}" "$HELPER" exec "$YQ_BIN" e \
        ".projects[] | select(.slug == \"$PROJECT\") | .description" "$NOTES_DIR/PROJECTS.yaml" 2>/dev/null)

      if [ -z "$PROJECT_PATH" ] || [ "$PROJECT_PATH" = "null" ]; then
        echo "Error: project '$PROJECT' not found in PROJECTS.yaml" >&2
        echo "" >&2
        echo "Available projects:" >&2
        sudo -u "agent-${AGENT_NAME}" "$HELPER" exec "$YQ_BIN" e \
          '.projects[].slug' "$NOTES_DIR/PROJECTS.yaml" 2>/dev/null | "$GNUSED"/bin/sed 's/^/  /' >&2
        exit 1
      fi

      # Validate project path exists
      if ! sudo -u "agent-${AGENT_NAME}" "$HELPER" exec test -d "$PROJECT_PATH"; then
        echo "Error: project path does not exist: $PROJECT_PATH" >&2
        exit 1
      fi

      SESSION_NAME="${PROJECT}-${SESSION_SLUG}"

      # Check if zellij session already exists → attach
      if "$ZELLIJ" list-sessions -s -n 2>/dev/null | "$GNUGREP"/bin/grep -q "^${SESSION_NAME}$"; then
        exec "$ZELLIJ" attach "$SESSION_NAME"
      fi

      # Create new zellij session, re-invoking self with env vars.
      # Env vars carry project context through zellij but are consumed before
      # sudo (no SETENV), so they're interpolated into the inner bash -c string.
      exec "$ZELLIJ" -s "$SESSION_NAME" -- \
        "$COREUTILS"/bin/env \
            "_AGENTCTL_PROJECT_PATH=$PROJECT_PATH" \
            "_AGENTCTL_PROJECT_NAME=$PROJECT_NAME" \
            "_AGENTCTL_PROJECT_DESC=$PROJECT_DESC" \
        agentctl "$AGENT_NAME" "$CMD" ${ROLE:+-r "$ROLE"} ${EXTRA_ROLES:+--roles "$EXTRA_ROLES"} "$@"
    fi

    # Determine working directory and project context (from zellij re-entry)
    WORK_DIR="$NOTES_DIR"
    PROJECT_CONTEXT=""
    if [ -n "${_AGENTCTL_PROJECT_PATH:-}" ]; then
      WORK_DIR="$_AGENTCTL_PROJECT_PATH"
      PROJECT_CONTEXT="
# Project Context
**Project:** ${_AGENTCTL_PROJECT_NAME}
**Description:** ${_AGENTCTL_PROJECT_DESC}
**Working Directory:** ${_AGENTCTL_PROJECT_PATH}"
    fi

    # Run as the agent, sandboxed inside Podman by default.
    # --nosandbox preserves the original direct-exec behavior.
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" exec bash -c '
      cd "'"$WORK_DIR"'"

      # Export project context as standard environment variables for all tools
      if [ -n "'"${_AGENTCTL_PROJECT_PATH:-}"'" ]; then
        export PROJECT_NAME="'"${_AGENTCTL_PROJECT_NAME:-}"'"
        export PROJECT_PATH="'"${_AGENTCTL_PROJECT_PATH:-}"'"
      fi

      # Resolve auto-approve flags per tool
      # CRITICAL: Claude gets --dangerously-skip-permissions only,
      # Gemini gets --yolo only. These are mutually exclusive per-tool.
      TOOL_FLAGS=""
      case "'"$CMD"'" in
        claude) TOOL_FLAGS="--dangerously-skip-permissions" ;;
        gemini) TOOL_FLAGS="--yolo" ;;
        codex) TOOL_FLAGS="--full-auto" ;;
      esac

      # Compose system prompt from AGENTS.md layers + role + project context
      # (applies to all AI tools; injection mechanism is per-tool below)
      # Loading order (REQ-017.6):
      #   1. System-wide conventions — loaded natively by each tool from its
      #      instruction file (~/.claude/CLAUDE.md, ~/.gemini/GEMINI.md, etc.)
      #      Generated by conventions.nix. NOT injected via SP_FLAGS.
      #   2. Notes-dir AGENTS.md (agent identity: SOUL.md, TEAM.md, SERVICES.md)
      #   3. Project AGENTS.md (project-specific context)
      #   4. Role composition via --role/--roles (appended)
      SP=""

      # 2. Agent identity from notes directory
      NOTES_AGENTS_MD="'"$NOTES_DIR"'/AGENTS.md"
      if [ -f "$NOTES_AGENTS_MD" ]; then
        if [ -n "$SP" ]; then
          SP="$SP

$(cat "$NOTES_AGENTS_MD")"
        else
          SP="$(cat "$NOTES_AGENTS_MD")"
        fi
      fi

      # 3. Project-local AGENTS.md (if working in a project directory)
      if [ "'"$WORK_DIR"'" != "'"$NOTES_DIR"'" ] && [ -f AGENTS.md ]; then
        if [ -n "$SP" ]; then
          SP="$SP

$(cat AGENTS.md)"
        else
          SP="$(cat AGENTS.md)"
        fi
      fi

      # Append project context
      PROJECT_CTX="'"$PROJECT_CONTEXT"'"
      if [ -n "$PROJECT_CTX" ]; then
        if [ -n "$SP" ]; then
          SP="$SP$PROJECT_CTX"
        else
          SP="$PROJECT_CTX"
        fi
      fi

      ROLE="'"$ROLE"'"
      EXTRA_ROLES="'"$EXTRA_ROLES"'"
      if [ -n "$ROLE" ] || [ -n "$EXTRA_ROLES" ]; then
        if [ -x .agents/compose.sh ] && [ -f manifests/modes.yaml ]; then
          COMPOSE_EXTRA=""
          if [ -n "$EXTRA_ROLES" ]; then
            COMPOSE_EXTRA="--roles $EXTRA_ROLES"
          fi
          ROLE_PROMPT="$(PATH="'"$YQ_BIN"':$PATH" .agents/compose.sh manifests/modes.yaml "$ROLE" $COMPOSE_EXTRA)"
          if [ -n "$SP" ]; then
            SP="$SP

$ROLE_PROMPT"
          else
            SP="$ROLE_PROMPT"
          fi
        else
          echo "Warning: role/--roles requested but .agents/compose.sh or manifests/modes.yaml not found" >&2
        fi
      fi

      # Per-tool prompt injection using each tool'\''s native mechanism
      SP_FLAGS=()
      if [ -n "$SP" ]; then
        case "'"$CMD"'" in
          claude)
            SP_FLAGS=("--append-system-prompt" "$SP")
            ;;
          gemini)
            SP_FLAGS=("--prompt-interactive" "$SP")
            ;;
          codex)
            SP_FLAGS=("--instructions" "$SP")
            ;;
          opencode)
            # opencode reads AGENTS.md natively from the working directory
            ;;
        esac
      fi

      if [ -n "'"$NOSANDBOX"'" ]; then
        # --nosandbox: direct-exec behavior (original path)
        if [ -f flake.nix ]; then
          # Use git+file with submodules=1 so nix can see git submodules
          FLAKE_REF="."
          if [ -f .gitmodules ]; then
            FLAKE_REF="git+file:.?submodules=1"
          fi
          exec nix develop "$FLAKE_REF" --no-update-lock-file --accept-flake-config \
            --command "'"$CMD"'" $TOOL_FLAGS "${SP_FLAGS[@]}" "$@"
        else
          exec "'"$CMD"'" $TOOL_FLAGS "${SP_FLAGS[@]}" "$@"
        fi
      else
        # Sandboxed default: run via podman-agent.
        # podman-agent adds auto-approve flags and handles mounts, SSH, cache volumes.
        # SP_FLAGS and user args are forwarded so the agent receives the full system prompt.
        exec "'"$PODMAN_AGENT"'" "'"$CMD"'" "${SP_FLAGS[@]}" "$@"
      fi
    ' -- "$@"
    ;;
  mail)
    exec agent-mail "$@" --to "${AGENT_NAME}@${TOP_DOMAIN}"
    ;;
  provision)
    # Resolve provision metadata (compiled-in)
    PROVISION_AGENT_HOST=""
    MAIL_PROVISION=false
    case "$AGENT_NAME" in
@agentProvisionCases@
    esac

    # Parse flags
    SKIP_REKEY=false
    for arg in "$@"; do
      case "$arg" in
        --skip-rekey) SKIP_REKEY=true ;;
        *) echo "Error: unknown provision flag '$arg'" >&2; exit 1 ;;
      esac
    done

    USERNAME="agent-${AGENT_NAME}"

    # Find secrets directory (same convention as hwrekey)
    NIXOS_CONFIG_DIR="${NIXOS_CONFIG_DIR:-$HOME/nixos-config}"
    SECRETS_DIR="$NIXOS_CONFIG_DIR/agenix-secrets"
    if [ ! -d "$SECRETS_DIR" ]; then
      echo "Error: secrets directory not found: $SECRETS_DIR" >&2
      echo "Set NIXOS_CONFIG_DIR to your nixos-config checkout." >&2
      exit 1
    fi

    TMPDIR=$("$COREUTILS"/bin/mktemp -d)
    trap '"$COREUTILS"/bin/rm -rf "$TMPDIR"' EXIT

    echo "==> Provisioning secrets for $USERNAME"

    # --- Step 1: Generate SSH keypair ---
    SSH_KEY="$TMPDIR/ssh-key"
    SSH_PASSPHRASE=$("$OPENSSL"/bin/openssl rand -base64 32)
    echo -n "$SSH_PASSPHRASE" > "$TMPDIR/ssh-passphrase"
    "$OPENSSH"/bin/ssh-keygen -t ed25519 -C "$USERNAME" \
      -f "$SSH_KEY" -N "$SSH_PASSPHRASE" -q
    echo "==> Generated SSH keypair"
    echo "    Public key: $(cat "$SSH_KEY.pub")"

    # --- Step 2: Generate mail password (if mail.provision) ---
    if [ "$MAIL_PROVISION" = "true" ]; then
      MAIL_PASSWORD=$("$OPENSSL"/bin/openssl rand -base64 24)
      echo -n "$MAIL_PASSWORD" > "$TMPDIR/mail-password"
      echo "==> Generated mail password"
    fi

    # --- Step 2b: Generate Bitwarden/Vaultwarden password ---
    BW_PASSWORD=$("$OPENSSL"/bin/openssl rand -base64 24)
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
      if "$GNUGREP"/bin/grep -q "\"$SECRET_NAME\"" "$SECRETS_NIX"; then
        echo "    $SECRET_NAME already exists in secrets.nix, skipping"
      else
        # Insert before the last closing brace
        "$GNUSED"/bin/sed -i "/^}$/i\\\\  \"$SECRET_NAME\".publicKeys = $RECIPIENTS;" "$SECRETS_NIX"
        echo "    Added $SECRET_NAME to secrets.nix"
      fi
    }

    # Determine recipient expression pieces
    # Agent host system key (for himalaya client / ssh-agent)
    AGENT_HOST_EXPR="systems.${PROVISION_AGENT_HOST}"
    # Mail server host system key (for Stalwart provisioning)
    MAIL_HOST_EXPR=""
    if [ -n "$MAIL_HOST" ] && [ "$MAIL_HOST" != "$PROVISION_AGENT_HOST" ]; then
      MAIL_HOST_EXPR="systems.${MAIL_HOST}"
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
    if ! "$NIX"/bin/nix eval --file "$SECRETS_NIX" --json > /dev/null 2>&1; then
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
    echo "      file = \"\${inputs.agenix-secrets}/secrets/$USERNAME-ssh-key.age\";"
    echo "      owner = \"$USERNAME\";"
    echo "      mode = \"0400\";"
    echo "    };"
    echo "    age.secrets.$USERNAME-ssh-passphrase = {"
    echo "      file = \"\${inputs.agenix-secrets}/secrets/$USERNAME-ssh-passphrase.age\";"
    echo "      owner = \"$USERNAME\";"
    echo "      mode = \"0400\";"
    echo "    };"
    if [ "$MAIL_PROVISION" = "true" ]; then
      echo "    age.secrets.$USERNAME-mail-password = {"
      echo "      file = \"\${inputs.agenix-secrets}/secrets/$USERNAME-mail-password.age\";"
      echo "      owner = \"$USERNAME\";"
      echo "      mode = \"0400\";"
      echo "    };"
    fi
    echo "    age.secrets.$USERNAME-bitwarden-password = {"
    echo "      file = \"\${inputs.agenix-secrets}/secrets/$USERNAME-bitwarden-password.age\";"
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
    exec "$VIRT_VIEWER"/bin/remote-viewer "vnc://$VNC_HOST:$VNC_PORT" "$@"
    ;;
  logs|journalctl)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" journalctl -e "$@"
    ;;
  cron)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" list-timers "$@"
    ;;
  *)
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" "$CMD" "$@"
    ;;
esac
