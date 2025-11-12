#!/usr/bin/env bash
#
# validate-services.sh - Check critical services are running
#
# This script validates that essential system services are running in the VM.
# It returns a list of running and failed services in a structured format.
#
# Usage: validate-services.sh <ssh_port>
#
# Output format (to stdout):
#   RUNNING: service1 service2 service3
#   FAILED: service4 service5
#
# Exit codes:
#   0 - All critical services running
#   1 - One or more critical services failed
#   2 - Invalid arguments or connection error

set -euo pipefail

# Parse arguments
if [ $# -ne 1 ]; then
    echo "Error: Invalid arguments" >&2
    echo "Usage: $0 <ssh_port>" >&2
    exit 2
fi

SSH_PORT="$1"

# SSH options for VM connection
SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5
    -o LogLevel=ERROR
    -p "$SSH_PORT"
)

# Critical services that must be running
# These are the minimum set for a functional NixOS system
CRITICAL_SERVICES=(
    "sshd.service"
    "systemd-journald.service"
)

# Optional services to check (won't cause failure if not running)
OPTIONAL_SERVICES=(
    "NetworkManager.service"
    "dbus.service"
)

# Arrays to track results
RUNNING_SERVICES=()
FAILED_SERVICES=()

echo "Checking critical services..." >&2

# Check critical services
for service in "${CRITICAL_SERVICES[@]}"; do
    if ssh "${SSH_OPTS[@]}" testuser@localhost "systemctl is-active $service" >/dev/null 2>&1; then
        RUNNING_SERVICES+=("$service")
        echo "  ✓ $service: running" >&2
    else
        FAILED_SERVICES+=("$service")
        echo "  ✗ $service: failed" >&2
    fi
done

# Check optional services (for informational purposes)
echo "Checking optional services..." >&2
for service in "${OPTIONAL_SERVICES[@]}"; do
    if ssh "${SSH_OPTS[@]}" testuser@localhost "systemctl is-active $service" >/dev/null 2>&1; then
        RUNNING_SERVICES+=("$service")
        echo "  ✓ $service: running" >&2
    else
        echo "  ℹ $service: not running (optional)" >&2
    fi
done

# Output structured results
echo "RUNNING: ${RUNNING_SERVICES[*]}"
echo "FAILED: ${FAILED_SERVICES[*]}"

# Exit with failure if any critical service failed
if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo "Error: ${#FAILED_SERVICES[@]} critical service(s) failed" >&2
    exit 1
fi

echo "All critical services running" >&2
exit 0
