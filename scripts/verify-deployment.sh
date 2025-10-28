#!/usr/bin/env bash
#
# Keystone Deployment Verification Script
#
# Usage: ./scripts/verify-deployment.sh <hostname> <target-ip>
#
# This script verifies that a Keystone server deployment is correctly configured
# by checking SSH access, services, encryption, and security settings.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASS_COUNT=0
FAIL_COUNT=0

# Usage information
usage() {
    echo "Usage: $0 <hostname> <target-ip>"
    echo ""
    echo "Arguments:"
    echo "  hostname   - Expected hostname of the deployed server"
    echo "  target-ip  - IP address or hostname to connect to"
    echo ""
    echo "Example:"
    echo "  $0 test-server 192.168.122.50"
    echo "  $0 test-server test-server.local"
    exit 1
}

# Check arguments
if [ $# -ne 2 ]; then
    usage
fi

EXPECTED_HOSTNAME="$1"
TARGET="$2"

echo "=========================================="
echo "Keystone Deployment Verification"
echo "=========================================="
echo "Target: $TARGET"
echo "Expected hostname: $EXPECTED_HOSTNAME"
echo ""

# Helper function for running SSH commands
ssh_cmd() {
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$TARGET" "$@" 2>/dev/null
}

# Helper function for pass/fail output
check_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASS_COUNT++))
}

check_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAIL_COUNT++))
}

#
# Check 1: SSH Connectivity
#
echo "[1/5] SSH Connectivity..."
if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$TARGET" "echo 'SSH OK'" &>/dev/null; then
    check_pass "SSH connection successful"
else
    check_fail "Cannot connect via SSH to root@$TARGET"
    echo ""
    echo "Verification cannot continue without SSH access."
    exit 2
fi

#
# Check 2: Hostname Verification
#
echo "[2/5] Hostname Verification..."
ACTUAL_HOSTNAME=$(ssh_cmd "hostname" || echo "UNKNOWN")
if [ "$ACTUAL_HOSTNAME" = "$EXPECTED_HOSTNAME" ]; then
    check_pass "Hostname matches: $ACTUAL_HOSTNAME"
else
    check_fail "Hostname mismatch: expected '$EXPECTED_HOSTNAME', got '$ACTUAL_HOSTNAME'"
fi

#
# Check 3: Firewall Rules
#
echo "[3/5] Firewall Configuration..."
# Check if firewall is enabled
if ssh_cmd "systemctl is-active firewall.service" &>/dev/null; then
    check_pass "Firewall is active"

    # Check SSH port is allowed
    if ssh_cmd "nft list ruleset" | grep -q "tcp dport 22 accept" 2>/dev/null; then
        check_pass "SSH port 22 is allowed"
    else
        check_fail "SSH port 22 rule not found in firewall"
    fi
else
    check_fail "Firewall service is not active"
fi

#
# Check 4: ZFS Pool Status
#
echo "[4/5] ZFS Pool Status..."
POOL_STATUS=$(ssh_cmd "zpool status rpool" 2>&1 || echo "ERROR")
if echo "$POOL_STATUS" | grep -q "state: ONLINE"; then
    check_pass "ZFS pool 'rpool' is ONLINE and healthy"

    # Check if pool is imported
    if echo "$POOL_STATUS" | grep -q "rpool"; then
        check_pass "ZFS pool 'rpool' is imported"
    fi
else
    check_fail "ZFS pool 'rpool' is not healthy or not found"
fi

#
# Check 5: Encryption Status
#
echo "[5/5] Encryption Verification..."
# Check for encrypted datasets under rpool/crypt
ENCRYPTED_DATASETS=$(ssh_cmd "zfs list -H -o name,encryption rpool/crypt 2>/dev/null" || echo "")
if echo "$ENCRYPTED_DATASETS" | grep -q "aes-256-gcm"; then
    check_pass "ZFS encryption is enabled (aes-256-gcm)"

    # Count encrypted datasets
    DATASET_COUNT=$(echo "$ENCRYPTED_DATASETS" | grep "aes-256-gcm" | wc -l)
    check_pass "Found $DATASET_COUNT encrypted dataset(s)"
else
    check_fail "ZFS encryption not properly configured"
fi

#
# Summary Report
#
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo -e "Passed checks: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed checks: ${RED}$FAIL_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Deployment verified successfully.${NC}"
    exit 0
else
    echo -e "${RED}✗ Some checks failed. Please review the output above.${NC}"
    exit 1
fi
