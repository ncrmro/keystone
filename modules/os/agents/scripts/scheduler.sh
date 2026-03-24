#!/usr/bin/env bash
# Agent scheduler: reads SCHEDULES.yaml, creates due tasks, triggers task loop.
# All tools come from the agent's home-manager profile PATH set in notes.nix.
# Pure bash, no LLM.
set -eo pipefail

# Sanity check: Ensure required system utilities are available
for cmd in bash tr systemctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command '$cmd' not found in PATH" >&2
    exit 1
  fi
done

# Config values substituted by NixOS module via pkgs.replaceVars
NOTES_DIR="@notesDir@"
AGENT_NAME="@agentName@"

LOGS_DIR="$HOME/.local/state/agent-scheduler/logs"

mkdir -p "$LOGS_DIR"

TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
LOG_FILE="$LOGS_DIR/$TIMESTAMP.log"
TODAY=$(date +%Y-%m-%d)
DOW=$(date +%A | tr '[:upper:]' '[:lower:]')
DOM=$(date +%-d)

log() {
  echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2
}

if [ ! -d "$NOTES_DIR" ]; then
  echo "Notes directory $NOTES_DIR does not exist yet, skipping"
  exit 0
fi
cd "$NOTES_DIR"
log "Starting scheduler for $AGENT_NAME (date: $TODAY, dow: $DOW, dom: $DOM)"

if [ ! -f SCHEDULES.yaml ]; then
  log "No SCHEDULES.yaml found, exiting"
  exit 0
fi

if [ ! -f TASKS.yaml ]; then
  log "No TASKS.yaml found, creating empty one"
  echo "tasks: []" > TASKS.yaml
fi

SCHEDULE_COUNT=$(yq '.schedules | length' SCHEDULES.yaml 2>/dev/null || echo "0")
CREATED=0

for i in $(seq 0 $((SCHEDULE_COUNT - 1))); do
  SCHED_NAME=$(yq ".schedules[$i].name" SCHEDULES.yaml)
  SCHED_DESC=$(yq ".schedules[$i].description" SCHEDULES.yaml)
  SCHED_SCHEDULE=$(yq ".schedules[$i].schedule" SCHEDULES.yaml)
  SCHED_WORKFLOW=$(yq ".schedules[$i].workflow" SCHEDULES.yaml)

  # Check if schedule is due today
  IS_DUE=false

  case "$SCHED_SCHEDULE" in
    daily)
      IS_DUE=true
      ;;
    weekly:*)
      TARGET_DAY="${SCHED_SCHEDULE#weekly:}"
      if [ "$DOW" = "$TARGET_DAY" ]; then
        IS_DUE=true
      fi
      ;;
    monthly:*)
      TARGET_DOM="${SCHED_SCHEDULE#monthly:}"
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
  SOURCE_REF="schedule-${SCHED_NAME}-${TODAY}"

  # Check if task already exists
  EXISTING=$(yq "[.tasks[] | select(.source_ref == \"$SOURCE_REF\")] | length" TASKS.yaml 2>/dev/null || echo "0")

  if [ "$EXISTING" -gt 0 ]; then
    log "  Skipping $SCHED_NAME (already exists: $SOURCE_REF)"
    continue
  fi

  # Append new task to TASKS.yaml
  log "  Creating task: ${SCHED_NAME}-${TODAY}"
  TASK_CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  yq -i ".tasks += [{
    \"name\": \"${SCHED_NAME}-$(date +%Y-%m-%d)\",
    \"description\": \"$SCHED_DESC\",
    \"status\": \"pending\",
    \"source\": \"schedule\",
    \"source_ref\": \"$SOURCE_REF\",
    \"workflow\": \"$SCHED_WORKFLOW\",
    \"created_at\": \"$TASK_CREATED_AT\"
  }]" TASKS.yaml

  CREATED=$((CREATED + 1))
done

log "Scheduler: $CREATED tasks from SCHEDULES.yaml"

# -- CalDAV calendar events ---------------------------------------------------
# Read upcoming events from the agent's CalDAV calendar via calendula.
# Events with [Team] or [AgentName] prefixes become tasks.
# Gracefully skips if calendula is not available.
if command -v calendula &>/dev/null; then
  log "Reading CalDAV calendar events..."
  CAL_EVENTS=$(calendula event list --output json 2>>"$LOG_FILE" || echo "[]")

  if [ "$CAL_EVENTS" != "[]" ] && [ -n "$CAL_EVENTS" ]; then
    CAL_COUNT=$(echo "$CAL_EVENTS" | jq 'length' 2>/dev/null || echo "0")
    log "  Found $CAL_COUNT calendar events"

    if [ "$CAL_COUNT" -gt 0 ]; then
    for j in $(seq 0 $((CAL_COUNT - 1))); do
      CAL_UID=$(echo "$CAL_EVENTS" | jq -r ".[$j].uid // empty" 2>/dev/null || true)
      CAL_SUMMARY=$(echo "$CAL_EVENTS" | jq -r ".[$j].summary // empty" 2>/dev/null || true)
      CAL_DESCRIPTION=$(echo "$CAL_EVENTS" | jq -r ".[$j].description // .[$j].summary // empty" 2>/dev/null || true)
      CAL_START=$(echo "$CAL_EVENTS" | jq -r ".[$j].start // empty" 2>/dev/null || true)

      # Skip events without a UID or summary
      if [ -z "$CAL_UID" ] || [ -z "$CAL_SUMMARY" ]; then
        continue
      fi

      # Only create tasks for events whose summary starts with [Team] or [AgentName]
      if [[ ! "$CAL_SUMMARY" == "\[Team\]"* && ! "$CAL_SUMMARY" == "\[$AGENT_NAME\]"* ]]; then
        continue
      fi

      # Use event start date for deduplication when available, fall back to today
      CAL_DATE="${TODAY}"
      if [ -n "$CAL_START" ]; then
        # Extract date portion (YYYY-MM-DD) from start timestamp without relying on grep -P
        CAL_DATE_PARSED=${CAL_START:0:10}
        case "$CAL_DATE_PARSED" in
          ????-??-??) CAL_DATE="$CAL_DATE_PARSED" ;;
        esac
      fi

      # Build source_ref for deduplication: calendar-<uid>-<date>
      CAL_SOURCE_REF="calendar-${CAL_UID}-${CAL_DATE}"

      # Check if task already exists
      EXISTING=$(yq "[.tasks[] | select(.source_ref == \"$CAL_SOURCE_REF\")] | length" TASKS.yaml 2>/dev/null || echo "0")
      if [ "$EXISTING" -gt 0 ]; then
        log "  Skipping calendar event (already exists: $CAL_SOURCE_REF)"
        continue
      fi

      # Create task from calendar event — use yq env() to safely handle special chars
      CAL_TASK_NAME="calendar-$(echo "$CAL_SUMMARY" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')-${CAL_DATE}"
      TASK_CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      log "  Creating task from calendar: $CAL_TASK_NAME"
      export CAL_TASK_NAME CAL_DESCRIPTION CAL_SOURCE_REF TASK_CREATED_AT
      yq -i '.tasks += [{
        "name": env(CAL_TASK_NAME),
        "description": env(CAL_DESCRIPTION),
        "status": "pending",
        "source": "calendar",
        "source_ref": env(CAL_SOURCE_REF),
        "created_at": env(TASK_CREATED_AT)
      }]' TASKS.yaml

      CREATED=$((CREATED + 1))
    done
    fi # CAL_COUNT > 0
  else
    log "  No calendar events found"
  fi
else
  log "Skipping CalDAV events: calendula not found"
fi

log "Scheduler finished: created $CREATED total tasks"

# Trigger task loop if we created any tasks
if [ $CREATED -gt 0 ]; then
  log "Triggering agent-${AGENT_NAME}-task-loop.service..."
  systemctl --user start "agent-${AGENT_NAME}-task-loop.service" || {
    log "  WARNING: Failed to trigger task loop"
  }
fi
