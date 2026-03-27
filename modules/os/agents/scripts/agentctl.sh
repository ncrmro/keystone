#!/usr/bin/env bash
# agentctl: unified CLI for managing agent services and mail.
# Dispatches to the per-agent Nix store helper via sudo (no SETENV needed).
# All defined agents are manageable via agentctl.

AGENTCTL_ENV_FILE="${AGENTCTL_ENV_FILE:-$HOME/.config/keystone/agentctl.env}"
if [ ! -f "$AGENTCTL_ENV_FILE" ]; then
  echo "Error: agentctl env file not found: $AGENTCTL_ENV_FILE" >&2
  echo "Rebuild the system or activate the development profile that provides it." >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$AGENTCTL_ENV_FILE"

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
  echo "  --local [model]        Use the configured Ollama server for claude/opencode" >&2
  echo "  --sandbox              Opt into Podman sandbox for this session (default: direct execution)" >&2
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
  echo "  agentctl drago claude --local" >&2
  echo "  agentctl drago claude --local qwen3:32b" >&2
  echo "  agentctl drago claude --roles software-engineer,code-reviewer" >&2
  echo "  agentctl drago claude -r implementation --roles software-engineer" >&2
  echo "  agentctl drago claude --project nixos-config fix-auth" >&2
  echo "  agentctl drago claude --project nixos-config              # list sessions" >&2
  echo "  agentctl drago gemini -r code-review" >&2
  echo "  agentctl drago gemini --project nixos-config fix-auth" >&2
  echo "  agentctl drago codex --project nixos-config fix-auth" >&2
  echo "  agentctl drago opencode --project nixos-config fix-auth" >&2
  echo "  agentctl drago opencode --local" >&2
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

if ! set_agent_helper "$AGENT_NAME"; then
  exit 1
fi
set_agent_notes_dir "$AGENT_NAME"

# Static lookup — agent name -> VNC port (desktop agents only)
VNC_PORT=""
set_agent_vnc_port "$AGENT_NAME"

# Resolve agent's host for remote dispatch
AGENT_HOST=""
set_agent_host "$AGENT_NAME"

OLLAMA_ENABLED="false"
OLLAMA_HOST="http://localhost:11434"
OLLAMA_DEFAULT_MODEL=""
set_agent_ollama "$AGENT_NAME"

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
SANDBOX=""
LOCAL_MODEL=""
REMAINING_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role) ROLE="$2"; shift 2 ;;
    --roles) EXTRA_ROLES="$2"; shift 2 ;;
    -p|--project) PROJECT="$2"; shift 2 ;;
    --local)
      shift
      if [[ $# -gt 0 && "${1:0:1}" != "-" ]]; then
        LOCAL_MODEL="$1"; shift
      else
        LOCAL_MODEL="default"
      fi
      ;;
    --sandbox) SANDBOX=1; shift ;;
    *) REMAINING_ARGS+=("$1"); shift ;;
  esac
done
set -- "${REMAINING_ARGS[@]}"

normalize_repo_url() {
  "$PROJECT_INDEX_HELPER" normalize-repo "$1"
}

resolve_repo_path() {
  local repo_id="$1"
  local keystone_path="$HOME/.keystone/repos/$repo_id"
  local code_path="$HOME/code/$repo_id"

  if [[ -d "$keystone_path" ]]; then
    printf '%s\n' "$keystone_path"
  elif [[ -d "$code_path" ]]; then
    printf '%s\n' "$code_path"
  fi
}

LOCAL_FLAG_ARGS=()
if [[ -n "$LOCAL_MODEL" ]]; then
  LOCAL_FLAG_ARGS+=(--local)
  if [[ "$LOCAL_MODEL" != "default" ]]; then
    LOCAL_FLAG_ARGS+=("$LOCAL_MODEL")
  fi
fi

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
    if [[ -n "$LOCAL_MODEL" ]]; then
      case "$CMD" in
        claude|opencode) ;;
        *)
          echo "Error: --local is only supported for 'claude' and 'opencode'." >&2
          echo "Received: $CMD" >&2
          exit 1
          ;;
      esac

      if [[ "$OLLAMA_ENABLED" != "true" ]]; then
        echo "Error: local model support is not enabled for agent '$AGENT_NAME'." >&2
        echo "Set keystone.terminal.ai.ollama.enable = true to use --local." >&2
        exit 1
      fi
    fi

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

      PROJECT_JSON=$(sudo -u "agent-${AGENT_NAME}" "$HELPER" exec \
        "$COREUTILS"/bin/env "NOTES_DIR=$NOTES_DIR" "$PROJECT_INDEX_HELPER" get "$PROJECT" 2>/dev/null || true)

      if [ -z "$PROJECT_JSON" ]; then
        echo "Error: project '$PROJECT' not found in zk project index" >&2
        echo "" >&2
        echo "Available projects:" >&2
        sudo -u "agent-${AGENT_NAME}" "$HELPER" exec \
          "$COREUTILS"/bin/env "NOTES_DIR=$NOTES_DIR" "$PROJECT_INDEX_HELPER" list 2>/dev/null \
          | jq -r '.projects[].slug' | "$GNUSED"/bin/sed 's/^/  /' >&2
        exit 1
      fi

      PROJECT_NAME=$(printf '%s\n' "$PROJECT_JSON" | jq -r '.name // .slug')
      PROJECT_DESC=$(printf '%s\n' "$PROJECT_JSON" | jq -r '.description // ""')
      PROJECT_PATH="$NOTES_DIR"

      REPO_COUNT=$(printf '%s\n' "$PROJECT_JSON" | jq -r '.repos | length')
      if [[ "$REPO_COUNT" == "1" ]]; then
        REPO_URL=$(printf '%s\n' "$PROJECT_JSON" | jq -r '.repos[0]')
        REPO_ID=$(normalize_repo_url "$REPO_URL" 2>/dev/null || true)
        if [[ -n "$REPO_ID" ]]; then
          RESOLVED_REPO_PATH=$(resolve_repo_path "$REPO_ID" || true)
          if [[ -n "$RESOLVED_REPO_PATH" ]]; then
            PROJECT_PATH="$RESOLVED_REPO_PATH"
          fi
        fi
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
        agentctl "$AGENT_NAME" "$CMD" "${LOCAL_FLAG_ARGS[@]}" ${ROLE:+-r "$ROLE"} ${EXTRA_ROLES:+--roles "$EXTRA_ROLES"} "$@"
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

    # Run as the agent, direct execution by default (REQ-013 sandbox scope).
    # --sandbox opts into Podman containerization.
    exec sudo -u "agent-${AGENT_NAME}" "$HELPER" exec bash -c '
      cd "'"$WORK_DIR"'"

      # Export project context as standard environment variables for all tools
      if [ -n "'"${_AGENTCTL_PROJECT_PATH:-}"'" ]; then
        export PROJECT_NAME="'"${_AGENTCTL_PROJECT_NAME:-}"'"
        export PROJECT_PATH="'"${_AGENTCTL_PROJECT_PATH:-}"'"
      fi

      # Resolve default execution flags per tool.
      # Respect explicit codex approval/sandbox flags provided by the caller.
      TOOL_FLAGS=""
      case "'"$CMD"'" in
        claude) TOOL_FLAGS="--dangerously-skip-permissions" ;;
        gemini) TOOL_FLAGS="--yolo" ;;
        codex)
          CODEX_HAS_EXECUTION_MODE=0
          for arg in "$@"; do
            case "$arg" in
              --full-auto|--dangerously-bypass-approvals-and-sandbox|--ask-for-approval|--ask-for-approval=*|--sandbox|--sandbox=*)
                CODEX_HAS_EXECUTION_MODE=1
                break
                ;;
            esac
          done
          if [ "$CODEX_HAS_EXECUTION_MODE" -eq 0 ]; then
            TOOL_FLAGS="--full-auto"
          fi
          ;;
      esac

      LOCAL_MODEL="'"$LOCAL_MODEL"'"
      OLLAMA_ENABLED="'"$OLLAMA_ENABLED"'"
      OLLAMA_HOST="'"$OLLAMA_HOST"'"
      OLLAMA_DEFAULT_MODEL="'"$OLLAMA_DEFAULT_MODEL"'"
      RESOLVED_LOCAL_MODEL=""
      if [ -n "$LOCAL_MODEL" ]; then
        if [ "$OLLAMA_ENABLED" != "true" ]; then
          echo "Error: local model support is not enabled for agent '"$AGENT_NAME"'." >&2
          exit 1
        fi
        if [ -n "$LOCAL_MODEL" ] && [ "$LOCAL_MODEL" != "default" ]; then
          RESOLVED_LOCAL_MODEL="$LOCAL_MODEL"
        elif [ -n "$OLLAMA_DEFAULT_MODEL" ]; then
          RESOLVED_LOCAL_MODEL="$OLLAMA_DEFAULT_MODEL"
        else
          echo "Error: no local model was provided and no default model is configured for agent '"$AGENT_NAME"'." >&2
          exit 1
        fi
      fi

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
      CODEX_MODEL_INSTRUCTIONS_FILE=""
      if [ -n "$SP" ]; then
        case "'"$CMD"'" in
          claude)
            SP_FLAGS=("--append-system-prompt" "$SP")
            ;;
          codex)
            # Codex CLI does not accept --instructions. Feed the composed
            # prompt through its supported model_instructions_file config key.
            CODEX_MODEL_INSTRUCTIONS_FILE="$(mktemp)"
            printf "%s\n" "$SP" > "$CODEX_MODEL_INSTRUCTIONS_FILE"
            SP_FLAGS=("-c" "model_instructions_file=\"$CODEX_MODEL_INSTRUCTIONS_FILE\"")
            ;;
          opencode)
            # opencode reads AGENTS.md natively from the working directory
            ;;
        esac
      fi

      if [ -n "$LOCAL_MODEL" ]; then
        case "'"$CMD"'" in
          claude)
            export ANTHROPIC_BASE_URL="$OLLAMA_HOST"
            export ANTHROPIC_AUTH_TOKEN="ollama"
            TOOL_FLAGS="$TOOL_FLAGS --model $RESOLVED_LOCAL_MODEL"
            ;;
          opencode)
            export OPENCODE_PROVIDER="ollama"
            export OPENCODE_MODEL="$RESOLVED_LOCAL_MODEL"
            export OLLAMA_HOST="$OLLAMA_HOST"
            ;;
        esac
      fi

      if [ -n "'"$SANDBOX"'" ]; then
        # --sandbox: opt-in Podman sandboxing for interactive sessions.
        # podman-agent adds auto-approve flags and handles mounts, SSH, cache volumes.
        if [ "'"$CMD"'" = "codex" ] && [ -n "$CODEX_MODEL_INSTRUCTIONS_FILE" ]; then
          "'"$PODMAN_AGENT"'" "'"$CMD"'" "${SP_FLAGS[@]}" "$@"
          status=$?
          rm -f "$CODEX_MODEL_INSTRUCTIONS_FILE"
          exit $status
        fi
        exec "'"$PODMAN_AGENT"'" "'"$CMD"'" "${SP_FLAGS[@]}" "$@"
      else
        # Default: direct execution as the agent user (REQ-013 sandbox scope).
        # Interactive agentctl sessions run without Podman since the human
        # operator is present and agents have OS-level user isolation.
        if [ -f flake.nix ]; then
          FLAKE_REF="."
          if [ -f .gitmodules ]; then
            FLAKE_REF="git+file:.?submodules=1"
          fi
          if [ "'"$CMD"'" = "codex" ] && [ -n "$CODEX_MODEL_INSTRUCTIONS_FILE" ]; then
            nix develop "$FLAKE_REF" --no-update-lock-file --accept-flake-config \
              --command "'"$CMD"'" $TOOL_FLAGS "${SP_FLAGS[@]}" "$@"
            status=$?
            rm -f "$CODEX_MODEL_INSTRUCTIONS_FILE"
            exit $status
          fi
          exec nix develop "$FLAKE_REF" --no-update-lock-file --accept-flake-config \
            --command "'"$CMD"'" $TOOL_FLAGS "${SP_FLAGS[@]}" "$@"
        else
          if [ "'"$CMD"'" = "codex" ] && [ -n "$CODEX_MODEL_INSTRUCTIONS_FILE" ]; then
            "'"$CMD"'" $TOOL_FLAGS "${SP_FLAGS[@]}" "$@"
            status=$?
            rm -f "$CODEX_MODEL_INSTRUCTIONS_FILE"
            exit $status
          fi
          exec "'"$CMD"'" $TOOL_FLAGS "${SP_FLAGS[@]}" "$@"
        fi
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
    set_agent_provision "$AGENT_NAME"

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
