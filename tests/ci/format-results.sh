#!/usr/bin/env bash
#
# format-results.sh - Format test results as JSON
#
# This script generates a JSON file conforming to test-result-schema.json
# from the test execution data collected during the workflow.
#
# Usage: format-results.sh \
#          --status <success|failure> \
#          --phase <build|boot|runtime|services> \
#          --duration <seconds> \
#          --workflow-run-id <id> \
#          --commit-sha <sha> \
#          [--error-message <message>] \
#          [--error-phase <phase>] \
#          [--error-logs <logs>] \
#          [--build-success <true|false>] \
#          [--build-duration <seconds>] \
#          [--build-outputs <path1,path2,...>] \
#          [--boot-success <true|false>] \
#          [--boot-duration <seconds>] \
#          [--boot-time <seconds>] \
#          [--services-success <true|false>] \
#          [--services-running <service1,service2,...>] \
#          [--services-failed <service1,service2,...>] \
#          --output <output-file>
#
# Exit codes:
#   0 - JSON generated successfully
#   1 - Invalid arguments or generation failed

set -euo pipefail

# Default values
STATUS=""
PHASE=""
DURATION=""
WORKFLOW_RUN_ID=""
COMMIT_SHA=""
ERROR_MESSAGE=""
ERROR_PHASE=""
ERROR_LOGS=""
BUILD_SUCCESS=""
BUILD_DURATION=""
BUILD_OUTPUTS=""
BOOT_SUCCESS=""
BOOT_DURATION=""
BOOT_TIME=""
SERVICES_SUCCESS=""
SERVICES_RUNNING=""
SERVICES_FAILED=""
OUTPUT_FILE=""

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --status)
            STATUS="$2"
            shift 2
            ;;
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --workflow-run-id)
            WORKFLOW_RUN_ID="$2"
            shift 2
            ;;
        --commit-sha)
            COMMIT_SHA="$2"
            shift 2
            ;;
        --error-message)
            ERROR_MESSAGE="$2"
            shift 2
            ;;
        --error-phase)
            ERROR_PHASE="$2"
            shift 2
            ;;
        --error-logs)
            ERROR_LOGS="$2"
            shift 2
            ;;
        --build-success)
            BUILD_SUCCESS="$2"
            shift 2
            ;;
        --build-duration)
            BUILD_DURATION="$2"
            shift 2
            ;;
        --build-outputs)
            BUILD_OUTPUTS="$2"
            shift 2
            ;;
        --boot-success)
            BOOT_SUCCESS="$2"
            shift 2
            ;;
        --boot-duration)
            BOOT_DURATION="$2"
            shift 2
            ;;
        --boot-time)
            BOOT_TIME="$2"
            shift 2
            ;;
        --services-success)
            SERVICES_SUCCESS="$2"
            shift 2
            ;;
        --services-running)
            SERVICES_RUNNING="$2"
            shift 2
            ;;
        --services-failed)
            SERVICES_FAILED="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$STATUS" ] || [ -z "$PHASE" ] || [ -z "$DURATION" ] || \
   [ -z "$WORKFLOW_RUN_ID" ] || [ -z "$COMMIT_SHA" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Error: Missing required arguments" >&2
    echo "Required: --status, --phase, --duration, --workflow-run-id, --commit-sha, --output" >&2
    exit 1
fi

# Generate ISO 8601 timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Helper function to escape JSON strings
escape_json() {
    local str="$1"
    # Escape backslashes, quotes, and newlines
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

# Helper function to convert comma-separated list to JSON array
csv_to_json_array() {
    local csv="$1"
    if [ -z "$csv" ]; then
        echo "[]"
        return
    fi
    
    # Split by comma and build JSON array
    local array="["
    local first=true
    IFS=',' read -ra items <<< "$csv"
    for item in "${items[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            array+=","
        fi
        array+="\"$(escape_json "$item")\""
    done
    array+="]"
    echo "$array"
}

# Start building JSON
cat > "$OUTPUT_FILE" <<EOF
{
  "status": "$STATUS",
  "phase": "$PHASE",
  "timestamp": "$TIMESTAMP",
  "duration_seconds": $DURATION,
  "workflow_run_id": "$WORKFLOW_RUN_ID",
  "commit_sha": "$COMMIT_SHA",
EOF

# Add error object if this is a failure
if [ "$STATUS" = "failure" ]; then
    cat >> "$OUTPUT_FILE" <<EOF
  "error": {
    "message": "$(escape_json "$ERROR_MESSAGE")",
    "phase": "$ERROR_PHASE",
    "logs": "$(escape_json "$ERROR_LOGS")"
  },
EOF
else
    cat >> "$OUTPUT_FILE" <<EOF
  "error": null,
EOF
fi

# Start results object
cat >> "$OUTPUT_FILE" <<EOF
  "results": {
EOF

# Build phase results (always present)
if [ -n "$BUILD_SUCCESS" ]; then
    OUTPUTS_ARRAY=$(csv_to_json_array "$BUILD_OUTPUTS")
    cat >> "$OUTPUT_FILE" <<EOF
    "build": {
      "success": $BUILD_SUCCESS,
      "duration_seconds": ${BUILD_DURATION:-0},
      "outputs": $OUTPUTS_ARRAY
    }
EOF
else
    # Default build result if not provided
    cat >> "$OUTPUT_FILE" <<EOF
    "build": {
      "success": false,
      "duration_seconds": 0,
      "outputs": []
    }
EOF
fi

# Boot phase results (if present)
if [ -n "$BOOT_SUCCESS" ]; then
    cat >> "$OUTPUT_FILE" <<EOF
,
    "boot": {
      "success": $BOOT_SUCCESS,
      "duration_seconds": ${BOOT_DURATION:-0}
EOF
    if [ "$BOOT_SUCCESS" = "true" ] && [ -n "$BOOT_TIME" ]; then
        cat >> "$OUTPUT_FILE" <<EOF
,
      "boot_time_seconds": $BOOT_TIME
EOF
    fi
    cat >> "$OUTPUT_FILE" <<EOF

    }
EOF
fi

# Services phase results (if present)
if [ -n "$SERVICES_SUCCESS" ]; then
    RUNNING_ARRAY=$(csv_to_json_array "$SERVICES_RUNNING")
    FAILED_ARRAY=$(csv_to_json_array "$SERVICES_FAILED")
    cat >> "$OUTPUT_FILE" <<EOF
,
    "services": {
      "success": $SERVICES_SUCCESS,
      "running": $RUNNING_ARRAY,
      "failed": $FAILED_ARRAY
    }
EOF
fi

# Close results and root objects
cat >> "$OUTPUT_FILE" <<EOF

  }
}
EOF

echo "JSON results written to $OUTPUT_FILE" >&2
exit 0
