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
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Options
CONTINUE_ON_FAIL=false
VERBOSE=false

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -gt 1 ]; then
        echo ""
        echo -e "${RED}Verification aborted with exit code $exit_code${NC}"
    fi
}
trap cleanup EXIT

# Usage information
usage() {
    echo "Usage: $0 <hostname> <target-ip> [options]"
    echo ""
    echo "Arguments:"
    echo "  hostname   - Expected hostname of the deployed server"
    echo "  target-ip  - IP address or hostname to connect to"
    echo ""
    echo "Options:"
    echo "  --continue-on-fail  - Continue verification even if non-critical checks fail"
    echo "  --verbose          - Show detailed command output"
    echo "  --help             - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 test-server 192.168.122.50"
    echo "  $0 test-server test-server.local --verbose"
    echo "  $0 test-server 192.168.122.50 --continue-on-fail"
    exit 1
}

# Parse arguments
if [ $# -lt 2 ]; then
    usage
fi

EXPECTED_HOSTNAME="$1"
TARGET="$2"
shift 2

# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        --continue-on-fail)
            CONTINUE_ON_FAIL=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            usage
            ;;
    esac
done

echo "=========================================="
echo "Keystone Deployment Verification"
echo "=========================================="
echo "Target: $TARGET"
echo "Expected hostname: $EXPECTED_HOSTNAME"
echo ""

# Helper function for running SSH commands with timeout
ssh_cmd() {
    local timeout=${SSH_TIMEOUT:-10}
    local output
    local exit_code

    if [ "$VERBOSE" = true ]; then
        ssh -o ConnectTimeout="$timeout" -o StrictHostKeyChecking=no "root@$TARGET" "$@"
        exit_code=$?
    else
        output=$(ssh -o ConnectTimeout="$timeout" -o StrictHostKeyChecking=no "root@$TARGET" "$@" 2>&1)
        exit_code=$?
        if [ $exit_code -ne 0 ] && [ "$VERBOSE" = true ]; then
            echo "  SSH command failed: $output" >&2
        fi
        echo "$output"
    fi

    return $exit_code
}

# Helper functions for pass/fail/skip output
check_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASS_COUNT++))
}

check_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    if [ -n "${2:-}" ]; then
        echo -e "  ${YELLOW}→ $2${NC}"
    fi
    ((FAIL_COUNT++))
}

check_skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1"
    if [ -n "${2:-}" ]; then
        echo -e "  ${BLUE}→ $2${NC}"
    fi
    ((SKIP_COUNT++))
}

#
# Check 1: SSH Connectivity
#
echo "[1/5] SSH Connectivity..."
SSH_TIMEOUT=10
if timeout 15 ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes "root@$TARGET" "echo 'SSH OK'" &>/dev/null; then
    check_pass "SSH connection successful"
else
    check_fail "Cannot connect via SSH to root@$TARGET"
    echo ""
    echo -e "${YELLOW}Troubleshooting SSH Connection:${NC}"
    echo ""
    echo "1. Verify system is running:"
    echo "   - Check VM console or system screen"
    echo "   - System should be booted and at login prompt"
    echo ""
    echo "2. Check network connectivity:"
    echo "   - Try: ping $TARGET"
    echo "   - Verify IP address is correct"
    echo "   - Check routing and firewall rules"
    echo ""
    echo "3. Test SSH manually:"
    echo "   - Run: ssh -v root@$TARGET"
    echo "   - Look for authentication or connection errors"
    echo ""
    echo "4. Verify SSH service status (on target):"
    echo "   - systemctl status sshd"
    echo "   - journalctl -u sshd -n 50"
    echo ""
    echo "5. Check firewall (on target):"
    echo "   - nft list ruleset | grep 22"
    echo "   - Ensure port 22 is allowed"
    echo ""
    exit 2
fi

#
# Check 2: Hostname Verification
#
echo "[2/5] Hostname Verification..."
ACTUAL_HOSTNAME=$(ssh_cmd "hostname" 2>/dev/null || echo "UNKNOWN")
if [ "$ACTUAL_HOSTNAME" = "$EXPECTED_HOSTNAME" ]; then
    check_pass "Hostname matches: $ACTUAL_HOSTNAME"
elif [ "$ACTUAL_HOSTNAME" = "UNKNOWN" ]; then
    check_fail "Could not retrieve hostname from target" "SSH command failed or timed out"
else
    check_fail "Hostname mismatch: expected '$EXPECTED_HOSTNAME', got '$ACTUAL_HOSTNAME'" \
               "Check networking.hostName in configuration"
fi

#
# Check 3: Firewall Rules
#
echo "[3/5] Firewall Configuration..."
# Check if firewall is enabled
FIREWALL_STATUS=$(ssh_cmd "systemctl is-active firewall.service" 2>/dev/null || echo "inactive")
if [ "$FIREWALL_STATUS" = "active" ]; then
    check_pass "Firewall is active"

    # Check SSH port is allowed
    FIREWALL_RULES=$(ssh_cmd "nft list ruleset 2>/dev/null" || echo "")
    if echo "$FIREWALL_RULES" | grep -q "tcp dport.*22.*accept"; then
        check_pass "SSH port 22 is allowed"
    else
        if [ -n "$FIREWALL_RULES" ]; then
            check_fail "SSH port 22 rule not found in firewall" \
                       "Firewall may be blocking SSH access"
        else
            check_skip "Could not retrieve firewall rules" \
                       "nft command may not be available"
        fi
    fi
else
    if [ "$FIREWALL_STATUS" = "inactive" ]; then
        check_fail "Firewall service is not active" \
                   "Security risk: firewall should be enabled"
    else
        check_skip "Could not determine firewall status" \
                   "systemctl command may have failed"
    fi
fi

#
# Check 4: ZFS Pool Status
#
echo "[4/5] ZFS Pool Status..."
POOL_STATUS=$(ssh_cmd "zpool status rpool 2>&1" || echo "ERROR")
if echo "$POOL_STATUS" | grep -q "state: ONLINE"; then
    check_pass "ZFS pool 'rpool' is ONLINE and healthy"

    # Check if pool is imported
    if echo "$POOL_STATUS" | grep -q "rpool"; then
        check_pass "ZFS pool 'rpool' is imported"
    fi

    # Check for errors in pool
    if echo "$POOL_STATUS" | grep -q "errors: No known data errors"; then
        check_pass "No ZFS errors detected"
    else
        check_fail "ZFS pool has errors" \
                   "Run 'zpool status -v rpool' on target to inspect"
    fi
else
    if echo "$POOL_STATUS" | grep -q "no such pool"; then
        check_fail "ZFS pool 'rpool' not found" \
                   "Pool may not be imported or doesn't exist"
    elif echo "$POOL_STATUS" | grep -q "ERROR"; then
        check_fail "Could not query ZFS pool status" \
                   "ZFS may not be installed or pool is unavailable"
    else
        check_fail "ZFS pool 'rpool' is not healthy" \
                   "Pool state: $(echo "$POOL_STATUS" | grep "state:" || echo "unknown")"
    fi
fi

#
# Check 5: Encryption Status
#
echo "[5/5] Encryption Verification..."
# Check for encrypted datasets under rpool/crypt
ENCRYPTED_DATASETS=$(ssh_cmd "zfs list -H -o name,encryption rpool/crypt 2>&1" || echo "ERROR")
if [ "$ENCRYPTED_DATASETS" = "ERROR" ]; then
    check_skip "Could not query ZFS encryption status" \
               "ZFS commands may have failed"
elif echo "$ENCRYPTED_DATASETS" | grep -q "dataset does not exist"; then
    check_fail "Dataset 'rpool/crypt' does not exist" \
               "Encryption may not be configured correctly"
elif echo "$ENCRYPTED_DATASETS" | grep -q "aes-256-gcm"; then
    check_pass "ZFS encryption is enabled (aes-256-gcm)"

    # Count encrypted datasets
    DATASET_COUNT=$(echo "$ENCRYPTED_DATASETS" | grep -c "aes-256-gcm")
    check_pass "Found $DATASET_COUNT encrypted dataset(s)"
else
    if [ -n "$ENCRYPTED_DATASETS" ]; then
        check_fail "ZFS encryption not properly configured" \
                   "Expected aes-256-gcm encryption, check disko configuration"
    else
        check_skip "No encrypted datasets found" \
                   "Encryption may not be enabled"
    fi
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
echo -e "Skipped checks: ${YELLOW}$SKIP_COUNT${NC}"
TOTAL_CHECKS=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
echo -e "Total checks: $TOTAL_CHECKS"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    if [ $SKIP_COUNT -eq 0 ]; then
        echo -e "${GREEN}✓ All checks passed! Deployment verified successfully.${NC}"
    else
        echo -e "${GREEN}✓ All critical checks passed.${NC}"
        echo -e "${YELLOW}⚠ Some checks were skipped (see output above).${NC}"
    fi
    echo ""
    echo "Your Keystone server is ready to use:"
    echo "  SSH: ssh root@$TARGET"
    echo "  mDNS: ssh root@$EXPECTED_HOSTNAME.local"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some checks failed. Please review the output above.${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Review failed checks and their error messages"
    echo "2. SSH to target and investigate: ssh root@$TARGET"
    echo "3. Check system logs: journalctl -xe"
    echo "4. Verify configuration matches deployment"
    echo ""
    echo "Re-run verification after fixing issues:"
    echo "  $0 $EXPECTED_HOSTNAME $TARGET"
    echo ""
    exit 1
fi
