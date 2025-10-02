#!/usr/bin/env bash
# Build Keystone ISO and prepare for VM deployment

set -euo pipefail

VM_NAME="${1:-}"
ISO_PATH="/var/lib/libvirt/images/keystone-installer.iso"
KEYSTONE_DIR="$(dirname "$(dirname "$(realpath "$0")")")"

if [ -z "$VM_NAME" ]; then
    echo "Usage: $0 <vm-name>"
    echo "Available VMs: router, storage, client, backup, dev, off-site"
    exit 1
fi

VM_DIR="$KEYSTONE_DIR/vm-infrastructure/vms/$VM_NAME"
if [ ! -d "$VM_DIR" ]; then
    echo "Error: VM configuration directory not found: $VM_DIR"
    exit 1
fi

echo "Building Keystone ISO with SSH keys..."
cd "$KEYSTONE_DIR"

# Build ISO using keystone's build script
if [ -f "bin/build-iso" ]; then
    ./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
else
    echo "Warning: bin/build-iso not found, using nix build directly"
    nix build .#iso
fi

# Find the built ISO
if [ -e result ]; then
    RESULT_PATH=$(readlink -f result)
    ISO_FILE=$(find "$RESULT_PATH" -name "*.iso" -type f | head -n 1)
    
    if [ -n "$ISO_FILE" ]; then
        echo "Copying ISO to libvirt images directory..."
        sudo mkdir -p /var/lib/libvirt/images
        sudo cp "$ISO_FILE" "$ISO_PATH"
        sudo chmod 644 "$ISO_PATH"
        echo "ISO ready at: $ISO_PATH"
    else
        echo "Error: No ISO file found in build result"
        exit 1
    fi
else
    echo "Error: Build did not create a 'result' symlink"
    exit 1
fi

echo "ISO build and preparation complete for VM: $VM_NAME"
echo "You can now use 'make up-$VM_NAME' to start the VM"