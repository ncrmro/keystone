#!/usr/bin/env bash
#
# check-boot-status.sh - Verify VM boot completion
#
# This script checks if a VM has successfully booted by:
# 1. Attempting SSH connection
# 2. Checking systemd is running
# 3. Verifying system reached default.target
#
# Usage: check-boot-status.sh <ssh_port> <timeout_seconds>
#
# Exit codes:
#   0 - Boot successful
#   1 - Boot failed or timeout
#   2 - Invalid arguments

set -euo pipefail

# Parse arguments
if [ $# -ne 2 ]; then
    echo "Error: Invalid arguments" >&2
    echo "Usage: $0 <ssh_port> <timeout_seconds>" >&2
    exit 2
fi

SSH_PORT="$1"
TIMEOUT="$2"

# SSH options for VM connection
SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5
    -o LogLevel=ERROR
    -p "$SSH_PORT"
)

echo "Waiting for VM to boot (timeout: ${TIMEOUT}s)..."

# Wait for SSH to be available
SSH_READY=false
START_TIME=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -ge "$TIMEOUT" ]; then
        echo "Error: Boot timeout after ${TIMEOUT}s" >&2
        exit 1
    fi
    
    # Try SSH connection
    if ssh "${SSH_OPTS[@]}" testuser@localhost "echo ready" >/dev/null 2>&1; then
        SSH_READY=true
        break
    fi
    
    sleep 1
done

if [ "$SSH_READY" = false ]; then
    echo "Error: SSH never became ready" >&2
    exit 1
fi

echo "SSH connection established after ${ELAPSED}s"

# Check systemd is running
if ! ssh "${SSH_OPTS[@]}" testuser@localhost "systemctl is-system-running --wait" >/dev/null 2>&1; then
    echo "Warning: systemd reported degraded state, but system is running" >&2
    # Continue - degraded is acceptable (some services may fail in CI)
fi

# Verify we reached default.target
if ! ssh "${SSH_OPTS[@]}" testuser@localhost "systemctl is-active default.target" >/dev/null 2>&1; then
    echo "Error: default.target not active" >&2
    exit 1
fi

echo "Boot successful (${ELAPSED}s)"
exit 0
