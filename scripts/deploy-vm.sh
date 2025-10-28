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
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$TARGET" "echo 'SSH OK'" &>/dev/null; then
    echo -e "${GREEN}✓ SSH connection successful${NC}"
else
    echo -e "${RED}✗ Cannot connect to root@$TARGET${NC}"
    echo "Please ensure:"
    echo "  - Target system is booted from Keystone ISO"
    echo "  - SSH is enabled on the target"
    echo "  - Network connectivity is working"
    exit 2
fi

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
if nix run nixpkgs#nixos-anywhere -- --flake ".#$CONFIG_NAME" "root@$TARGET"; then
    echo ""
    echo -e "${GREEN}✓ Deployment completed successfully${NC}"
    echo ""
    echo "The system will now reboot..."
    echo "Wait for the system to boot (approximately 1-2 minutes)"
    echo ""
else
    echo ""
    echo -e "${RED}✗ Deployment failed${NC}"
    echo "Check the output above for errors."
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
