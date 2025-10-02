#!/usr/bin/env bash
# Deploy a Keystone configuration to a VM using nixos-anywhere

set -euo pipefail

VM_NAME="${1:-}"
CONFIG_NAME="${2:-$VM_NAME}"
TARGET_IP="${3:-}"

if [ -z "$VM_NAME" ] || [ -z "$CONFIG_NAME" ]; then
    echo "Usage: $0 <vm-name> [config-name] [target-ip]"
    echo "Examples:"
    echo "  $0 router                    # Deploy router config to router VM"
    echo "  $0 storage nas              # Deploy nas config to storage VM"
    echo "  $0 client workstation       # Deploy workstation config to client VM"
    exit 1
fi

KEYSTONE_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
CONFIG_DIR="$KEYSTONE_DIR/vm-infrastructure/configs"

# Check if config exists
if [ ! -f "$CONFIG_DIR/$CONFIG_NAME.nix" ]; then
    echo "Error: Configuration file not found: $CONFIG_DIR/$CONFIG_NAME.nix"
    echo "Available configurations:"
    ls -1 "$CONFIG_DIR"/*.nix 2>/dev/null | xargs -n1 basename -s .nix || echo "  (none found)"
    exit 1
fi

# Get VM IP if not provided
if [ -z "$TARGET_IP" ]; then
    echo "Getting IP address for VM: $VM_NAME"
    
    # Try to get IP from DHCP leases
    DHCP_LEASE=$(sudo virsh net-dhcp-leases keystone-net 2>/dev/null | grep "keystone-$VM_NAME" | awk '{print $5}' | cut -d'/' -f1 || true)
    
    if [ -n "$DHCP_LEASE" ]; then
        TARGET_IP="$DHCP_LEASE"
        echo "Found VM IP: $TARGET_IP"
    else
        echo "Could not automatically determine VM IP address."
        echo "Please check the VM status and provide the IP manually:"
        echo "  virsh net-dhcp-leases keystone-net"
        echo "  $0 $VM_NAME $CONFIG_NAME <ip-address>"
        exit 1
    fi
fi

echo "Deploying configuration '$CONFIG_NAME' to VM '$VM_NAME' at $TARGET_IP"
echo "Config file: $CONFIG_DIR/$CONFIG_NAME.nix"

# Wait for SSH to be available
echo "Waiting for SSH to be available on $TARGET_IP..."
timeout=300
elapsed=0
while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$TARGET_IP" true 2>/dev/null; do
    if [ $elapsed -ge $timeout ]; then
        echo "Error: SSH connection timeout after ${timeout}s"
        exit 1
    fi
    echo "  Still waiting... (${elapsed}s/${timeout}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done

echo "SSH connection established. Starting deployment..."

# Deploy using nixos-anywhere
cd "$KEYSTONE_DIR"
nixos-anywhere --flake ".#$CONFIG_NAME" "root@$TARGET_IP"

echo "Deployment complete!"
echo "VM '$VM_NAME' is now running configuration '$CONFIG_NAME'"