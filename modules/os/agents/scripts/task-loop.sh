#!/usr/bin/env bash
# Agent task loop: pre-fetch sources, ingest, prioritize, execute.
# Uses claude from the agent's home-manager profile PATH.
set -eo pipefail

# Paths substituted by NixOS module via pkgs.replaceVars
YQ="@yq@"
JQ="@jq@"
DATE="@date@"
MKDIR="@mkdir@"
ECHO="@echo@"
CAT="@cat@"
TEE="@tee@"
# WC not currently used but reserved for future use
HEAD="@head@"
SEQ="@seq@"
FIND="@find@"
SORT="@sort@"
RM="@rm@"
FLOCK="@flock@"
SHA256SUM="@sha256sum@"
NOTES_DIR="@notesDir@"
MAX_TASKS="@maxTasks@"
AGENT_NAME="@agentName@"

LOGS_DIR="$HOME/.local/state/agent-task-loop/logs"
TASK_LOGS_DIR="$LOGS_DIR/tasks"
STATE_DIR="$HOME/.local/state/agent-task-loop/state"
LOCKFILE="$STATE_DIR/task-loop.lock"

$MKDIR -p "$LOGS_DIR" "$TASK_LOGS_DIR" "$STATE_DIR"

TIMESTAMP=$($DATE +%Y-%m-%d_%H%M%S)
LOG_FILE="$LOGS_DIR/$TIMESTAMP.log"
START_TIME=$($DATE +%s)

CURRENT_STEP="init"
CURRENT_TASK=""
log() {
  local tag="[step=$CURRENT_STEP]"
  [ -n "$CURRENT_TASK" ] && tag="${tag}[task=$CURRENT_TASK]"
  $ECHO "[$($DATE '+%H:%M:%S')] $tag $*" | $TEE -a "$LOG_FILE" >&2
}

# Lock to prevent concurrent runs (flock auto-releases on process death, even SIGKILL)
exec 9>"$LOCKFILE"
if ! $FLOCK -n 9; then
  $ECHO "Task loop already running, skipping" >&2
  exit 0
fi

if [ ! -d "$NOTES_DIR" ]; then
  $ECHO "Notes directory $NOTES_DIR does not exist yet, skipping"
  exit 0
fi
cd "$NOTES_DIR"
log "Starting agent task loop for $AGENT_NAME"

# -- Step 1: Pre-fetch sources -----------------------------------------------
# Always runs - discovers new tasks from email, git, and custom sources.
CURRENT_STEP="prefetch"
log "Step 1: Pre-fetching sources..."
SOURCES_JSON="[]"

# Built-in source: email inbox (himalaya)
# himalaya is installed via home-manager (keystone.terminal.mail), not the dev shell
if command -v himalaya &>/dev/null; then
  log "  Fetching source: email"
  EMAIL_OUTPUT=$(himalaya envelope list --page-size 20 --output json 2>>"$LOG_FILE" || $ECHO "[]")
  if [ -n "$EMAIL_OUTPUT" ] && [ "$EMAIL_OUTPUT" != "[]" ]; then
    SOURCES_JSON=$($ECHO "$SOURCES_JSON" | $JQ --argjson data "$EMAIL_OUTPUT" \
      '. + [{"source": "email", "data": $data}]')
  fi
else
  log "  Skipping email source: himalaya not found"
fi

# Custom sources from PROJECTS.yaml (user-defined commands)
if [ -f PROJECTS.yaml ]; then
  SOURCE_COUNT=$($YQ '.sources | length' PROJECTS.yaml 2>/dev/null || $ECHO "0")

  for i in $($SEQ 0 $((SOURCE_COUNT - 1))); do
    SOURCE_NAME=$($YQ ".sources[$i].name" PROJECTS.yaml)
    SOURCE_CMD=$($YQ ".sources[$i].command" PROJECTS.yaml)

    if [ -n "$SOURCE_CMD" ] && [ "$SOURCE_CMD" != "null" ]; then
      log "  Fetching source: $SOURCE_NAME"
      SOURCE_OUTPUT=$(bash -c "$SOURCE_CMD" 2>>"$LOG_FILE" || $ECHO "[]")
      SOURCES_JSON=$($ECHO "$SOURCES_JSON" | $JQ --arg name "$SOURCE_NAME" --argjson data "$SOURCE_OUTPUT" \
        '. + [{"source": $name, "data": $data}]')
    fi
  done
fi

log "  Collected sources: $($ECHO "$SOURCES_JSON" | $JQ 'length') entries"

# -- Step 2: Ingest (haiku) --------------------------------------------------
CURRENT_STEP="ingest"
INGEST_RAN=false
log "Step 2: Ingesting sources via haiku..."
if [ "$($ECHO "$SOURCES_JSON" | $JQ '[.[].data | length] | add // 0')" -gt 0 ]; then
  set +o pipefail
  claude --print --dangerously-skip-permissions --model haiku \
    "/deepwork task_loop ingest

Source data (pre-fetched):
$($ECHO "$SOURCES_JSON" | $JQ '.')" 2>&1 | $TEE -a "$LOG_FILE" >&2
  INGEST_EXIT=${PIPESTATUS[0]}
  set -o pipefail
  if [ "$INGEST_EXIT" -ne 0 ]; then
    log "  WARNING: Ingest step failed, continuing..."
  else
    INGEST_RAN=true
  fi

  if ! $YQ '.' TASKS.yaml >/dev/null 2>&1; then
    log "  ERROR: TASKS.yaml corrupted during ingest. Reverting..."
    git checkout TASKS.yaml || git restore TASKS.yaml || true
    INGEST_RAN=false
  fi
else
  log "  No source data to ingest, skipping"
fi

# -- Step 3: Prioritize (haiku) ----------------------------------------------
CURRENT_STEP="prioritize"

# Skip prioritize entirely if ingest didn't run and there are no pending tasks.
# This avoids a wasteful haiku call when nothing has changed.
PENDING_COUNT=0
if [ -f TASKS.yaml ]; then
  PENDING_COUNT=$($YQ '[.tasks[] | select(.status == "pending")] | length' TASKS.yaml 2>/dev/null || $ECHO "0")
fi
if [ "$INGEST_RAN" = "false" ] && [ "$PENDING_COUNT" = "0" ]; then
  log "Step 3: Skipping prioritize (no new sources, no pending tasks)"
else

PRIORITIZE_HASH_FILE="$STATE_DIR/prioritize-inputs.sha256"
CURRENT_HASH=""
if [ -f TASKS.yaml ] && [ -f PROJECTS.yaml ]; then
  CURRENT_HASH=$($CAT TASKS.yaml PROJECTS.yaml | $SHA256SUM | $HEAD -c 64)
elif [ -f TASKS.yaml ]; then
  CURRENT_HASH=$($CAT TASKS.yaml | $SHA256SUM | $HEAD -c 64)
fi

PREVIOUS_HASH=""
if [ -f "$PRIORITIZE_HASH_FILE" ]; then
  PREVIOUS_HASH=$($CAT "$PRIORITIZE_HASH_FILE")
fi

if [ -n "$CURRENT_HASH" ] && [ "$CURRENT_HASH" = "$PREVIOUS_HASH" ]; then
  log "Step 3: Inputs unchanged, skipping prioritize"
else
  log "Step 3: Prioritizing tasks via haiku..."
  set +o pipefail
  claude --print --dangerously-skip-permissions --model haiku \
    "/deepwork task_loop prioritize" 2>&1 | $TEE -a "$LOG_FILE" >&2
  PRIORITIZE_EXIT=${PIPESTATUS[0]}
  set -o pipefail
  if [ "$PRIORITIZE_EXIT" -ne 0 ]; then
    log "  WARNING: Prioritize step failed, continuing..."
  else
    if ! $YQ '.' TASKS.yaml >/dev/null 2>&1; then
      log "  ERROR: TASKS.yaml corrupted during prioritize. Reverting..."
      git checkout TASKS.yaml || git restore TASKS.yaml || true
    else
      # Save hash only on success so we retry on failure
      $ECHO -n "$CURRENT_HASH" > "$PRIORITIZE_HASH_FILE"
    fi
  fi
fi
fi # end INGEST_RAN guard

# -- Step 4: Execute pending tasks -------------------------------------------
# Check for pending tasks after ingest - exit if nothing to execute
if [ ! -f TASKS.yaml ] || \
   [ "$($YQ '[.tasks[] | select(.status == "pending")] | length' TASKS.yaml 2>/dev/null)" = "0" ]; then
  log "No pending tasks after ingest, done"
  exit 0
fi

CURRENT_STEP="execute"
log "Step 4: Executing pending tasks (max $MAX_TASKS)..."
TASK_COUNT=0
ATTEMPTED_TASKS=":"

while [ $TASK_COUNT -lt "$MAX_TASKS" ]; do
  # Read the first pending task from TASKS.yaml
  TASK_NAME=$($YQ '[.tasks[] | select(.status == "pending")] | .[0].name' TASKS.yaml 2>/dev/null || $ECHO "null")

  if [ "$TASK_NAME" = "null" ] || [ -z "$TASK_NAME" ]; then
    log "  No more pending tasks"
    break
  fi

  if [[ "$ATTEMPTED_TASKS" == *":$TASK_NAME:"* ]]; then
    log "  Task $TASK_NAME already attempted in this run but still pending. Breaking to prevent infinite loop."
    break
  fi
  ATTEMPTED_TASKS="${ATTEMPTED_TASKS}${TASK_NAME}:"

  TASK_DESC=$($YQ "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].description" TASKS.yaml)
  TASK_WORKFLOW=$($YQ "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].workflow // \"\"" TASKS.yaml)
  TASK_MODEL=$($YQ "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].model // \"\"" TASKS.yaml)
  TASK_NEEDS=$($YQ "[.tasks[] | select(.name == \"$TASK_NAME\")] | .[0].needs // []" TASKS.yaml)

  # Check if task has unmet dependencies
  if [ "$TASK_NEEDS" != "[]" ] && [ "$TASK_NEEDS" != "null" ]; then
    NEEDS_MET=true
    for need in $($ECHO "$TASK_NEEDS" | $JQ -r '.[]' 2>/dev/null); do
      NEED_STATUS=$($YQ "[.tasks[] | select(.name == \"$need\")] | .[0].status // \"pending\"" TASKS.yaml)
      if [ "$NEED_STATUS" != "completed" ]; then
        NEEDS_MET=false
        break
      fi
    done
    if [ "$NEEDS_MET" = "false" ]; then
      log "  Skipping $TASK_NAME (unmet dependencies)"
      # Mark as blocked so we don't loop forever
      $YQ -i "(.tasks[] | select(.name == \"$TASK_NAME\")).status = \"blocked\"" TASKS.yaml
      continue
    fi
  fi

  TASK_COUNT=$((TASK_COUNT + 1))
  TASK_TIMESTAMP=$($DATE +%Y-%m-%d_%H%M%S)
  TASK_LOG="$TASK_LOGS_DIR/${TASK_TIMESTAMP}_${TASK_NAME}.log"

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
  claude --print --dangerously-skip-permissions $MODEL_FLAG "$PROMPT" 2>&1 | $TEE "$TASK_LOG" >&2
  TASK_EXIT=${PIPESTATUS[0]}
  set -o pipefail

  if [ "$TASK_EXIT" -eq 0 ]; then
    $YQ -i "(.tasks[] | select(.name == \"$TASK_NAME\")).status = \"completed\"" TASKS.yaml
    log "  Task $TASK_NAME completed (log: $TASK_LOG)"
  else
    $YQ -i "(.tasks[] | select(.name == \"$TASK_NAME\")).status = \"error\"" TASKS.yaml
    log "  Task $TASK_NAME errored (exit $TASK_EXIT, log: $TASK_LOG)"
  fi
done

# -- Summary ------------------------------------------------------------------
CURRENT_STEP="summary"
CURRENT_TASK=""
END_TIME=$($DATE +%s)
DURATION=$((END_TIME - START_TIME))
log "Task loop finished: executed $TASK_COUNT tasks in ${DURATION}s"

# -- Rotate old logs (keep last 20) -------------------------------------------
for ext in log; do
  $FIND "$LOGS_DIR" -maxdepth 1 -name "*.$ext" -type f | $SORT -r | while IFS= read -r file; do
    COUNT=$((${COUNT:-0} + 1))
    if [ $COUNT -gt 20 ]; then
      $RM -f "$file"
    fi
  done
done
