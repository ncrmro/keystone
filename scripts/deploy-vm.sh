#!/usr/bin/env bash
#
# Keystone VM Deployment Wrapper
#
# Usage: ./scripts/deploy-vm.sh <config-name> <target-ip> [options]
#
# This script wraps nixos-anywhere to provide a streamlined deployment experience
# with validation, confirmation, and optional post-deployment verification.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
VERIFY=false
FORCE=false

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo -e "${RED}Deployment failed with exit code $exit_code${NC}"
        echo "Check the output above for detailed error information."
    fi
}
trap cleanup EXIT

# Handle interruption gracefully
interrupt() {
    echo ""
    echo -e "${YELLOW}⚠ Deployment interrupted by user${NC}"
    exit 130
}
trap interrupt SIGINT SIGTERM

# Usage information
usage() {
    echo "Usage: $0 <config-name> <target-ip> [options]"
    echo ""
    echo "Arguments:"
    echo "  config-name - NixOS configuration name from flake (e.g., test-server)"
    echo "  target-ip   - IP address or hostname of target system"
    echo ""
    echo "Options:"
    echo "  --verify    - Run verification script after deployment"
    echo "  --force     - Skip confirmation prompt"
    echo "  --help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 test-server 192.168.122.50"
    echo "  $0 test-server 192.168.122.50 --verify"
    echo "  $0 test-server test-server.local --verify --force"
    echo ""
    exit 1
}

# Parse arguments
if [ $# -lt 2 ]; then
    usage
fi

CONFIG_NAME="$1"
TARGET="$2"
shift 2

# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        --verify)
            VERIFY=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            usage
            ;;
    esac
done

echo "=========================================="
echo "Keystone VM Deployment"
echo "=========================================="
echo -e "Configuration: ${BLUE}$CONFIG_NAME${NC}"
echo -e "Target: ${BLUE}$TARGET${NC}"
echo -e "Verify after deployment: ${BLUE}$VERIFY${NC}"
echo ""

#
# Pre-flight checks
#
echo -e "${BLUE}[Pre-flight]${NC} Checking prerequisites..."

# Check if nix is available
if ! command -v nix &>/dev/null; then
    echo -e "${RED}✗ Nix command not found${NC}"
    echo "Please install Nix: https://nixos.org/download.html"
    exit 1
fi

# Check if nixos-anywhere is available via nix run
if ! nix eval nixpkgs#nixos-anywhere.version --raw &>/dev/null; then
    echo -e "${RED}✗ nixos-anywhere not available${NC}"
    echo "Ensure nixpkgs is accessible in your Nix configuration"
    exit 1
fi

# Check basic network connectivity
if ! ping -c 1 -W 2 "$TARGET" &>/dev/null; then
    echo -e "${YELLOW}⚠ Cannot ping $TARGET${NC}"
    echo "Network connectivity may be limited (ping failed)"
    echo "Will attempt SSH connection anyway..."
else
    echo -e "${GREEN}✓ Network connectivity OK${NC}"
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

#
# Step 1: Validate configuration builds
#
echo -e "${BLUE}[1/4]${NC} Validating configuration..."
if nix build ".#nixosConfigurations.$CONFIG_NAME.config.system.build.toplevel" --no-link 2>&1 | grep -q "error:"; then
    echo -e "${RED}✗ Configuration build failed${NC}"
    echo "Please fix the configuration errors and try again."
    exit 1
else
    echo -e "${GREEN}✓ Configuration builds successfully${NC}"
fi

#
# Step 2: Check SSH connectivity to target
#
echo -e "${BLUE}[2/4]${NC} Checking SSH connectivity..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "root@$TARGET" "echo 'SSH OK'" &>/dev/null; then
    echo -e "${RED}✗ Cannot connect to root@$TARGET${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Verify target system is booted:"
    echo "     - Check the VM console or physical system screen"
    echo "     - Ensure system has reached login prompt"
    echo ""
    echo "  2. Verify SSH is enabled:"
    echo "     - On target, run: systemctl status sshd"
    echo "     - If using Keystone ISO, SSH should be enabled by default"
    echo ""
    echo "  3. Verify network connectivity:"
    echo "     - Ping target: ping $TARGET"
    echo "     - Check IP is correct"
    echo "     - Check firewall rules"
    echo ""
    echo "  4. Verify SSH authentication:"
    echo "     - Try manual SSH: ssh root@$TARGET"
    echo "     - Check if password is required (ISO should allow key auth)"
    echo ""
    exit 2
fi

echo -e "${GREEN}✓ SSH connection successful${NC}"

# Check target disk configuration
echo -e "${BLUE}[2b/4]${NC} Verifying target system configuration..."
TARGET_INFO=$(ssh -o StrictHostKeyChecking=no "root@$TARGET" "lsblk -d -n -o NAME,SIZE,TYPE | grep disk || true" 2>/dev/null)
if [ -n "$TARGET_INFO" ]; then
    echo "Available disks on target:"
    while IFS= read -r line; do
        echo "  /dev/$line"
    done <<< "$TARGET_INFO"
    echo -e "${GREEN}✓ Target system accessible${NC}"
else
    echo -e "${YELLOW}⚠ Could not enumerate target disks${NC}"
    echo "Proceeding anyway..."
fi
echo ""

#
# Step 3: Confirmation prompt (unless --force)
#
if [ "$FORCE" = false ]; then
    echo ""
    echo -e "${YELLOW}⚠ WARNING${NC}: This will:"
    echo "  - Partition and format the target disk"
    echo "  - Install NixOS with configuration '$CONFIG_NAME'"
    echo "  - ALL DATA on the target disk will be LOST"
    echo ""
    read -p "Continue with deployment? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
fi

#
# Step 4: Run nixos-anywhere
#
echo -e "${BLUE}[3/4]${NC} Deploying with nixos-anywhere..."
echo "This may take 5-10 minutes..."
echo ""

# Run nixos-anywhere with progress output
DEPLOY_EXIT_CODE=0
nix run nixpkgs#nixos-anywhere -- --flake ".#$CONFIG_NAME" "root@$TARGET" || DEPLOY_EXIT_CODE=$?

if [ $DEPLOY_EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Deployment completed successfully${NC}"
    echo ""
    echo "The system will now reboot..."
    echo "Wait for the system to boot (approximately 1-2 minutes)"
    echo ""
else
    echo ""
    echo -e "${RED}✗ Deployment failed with exit code $DEPLOY_EXIT_CODE${NC}"
    echo ""
    echo "Common issues and solutions:"
    echo ""
    echo "  1. Disk formatting errors:"
    echo "     - Check disk device path in configuration"
    echo "     - Ensure disk is not in use"
    echo "     - Verify disk has sufficient space (minimum 20GB recommended)"
    echo ""
    echo "  2. Network disconnection:"
    echo "     - Check network stability"
    echo "     - Verify SSH connection: ssh root@$TARGET"
    echo "     - nixos-anywhere can be retried after fixing the issue"
    echo ""
    echo "  3. Configuration errors:"
    echo "     - Review the build output above"
    echo "     - Check module imports and options"
    echo "     - Verify all required options are set"
    echo ""
    echo "  4. ZFS/Encryption errors:"
    echo "     - Ensure ZFS modules are available in ISO kernel"
    echo "     - Check disko configuration syntax"
    echo "     - Verify credstore setup if using encryption"
    echo ""
    echo "To retry: $0 $CONFIG_NAME $TARGET"
    echo ""
    exit 3
fi

#
# Step 5: Optional verification
#
if [ "$VERIFY" = true ]; then
    echo -e "${BLUE}[4/4]${NC} Running post-deployment verification..."
    echo "Waiting 30 seconds for system to fully boot..."
    sleep 30

    # Extract hostname from configuration (simple approach: use config name)
    HOSTNAME="$CONFIG_NAME"

    # Run verification script
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/verify-deployment.sh" ]; then
        "$SCRIPT_DIR/verify-deployment.sh" "$HOSTNAME" "$TARGET"
    else
        echo -e "${YELLOW}⚠ Verification script not found${NC}"
        echo "Run manually: ./scripts/verify-deployment.sh $HOSTNAME $TARGET"
    fi
else
    echo -e "${BLUE}[4/4]${NC} Skipping verification (use --verify to enable)"
    echo ""
    echo "To verify the deployment manually, run:"
    echo "  ./scripts/verify-deployment.sh $CONFIG_NAME $TARGET"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Deployment Complete!${NC}"
echo "=========================================="
echo "You can now SSH into the system:"
echo "  ssh root@$TARGET"
echo ""
echo "Or use mDNS (if on same network):"
echo "  ssh root@$CONFIG_NAME.local"
echo ""
