#!/usr/bin/env bash
# Generate Quickemu configuration files for Keystone VMs

set -euo pipefail

KEYSTONE_DIR="$(dirname "$(realpath "$0")")/.."
VMS_DIR="$KEYSTONE_DIR/vms"

generate_config() {
    local vm_name="$1"
    local vm_dir="$VMS_DIR/keystone-$vm_name"
    local conf_file="$vm_dir/keystone-$vm_name.conf"
    
    echo "Generating config for: $vm_name"
    mkdir -p "$vm_dir"
    
    case "$vm_name" in
        router)
            cat > "$conf_file" << 'EOF'
# Keystone Router/Gateway VM Configuration
guest_os="linux"
disk_img="disk.qcow2"
iso="../keystone-installer.iso"
ram="2G"
cpu_cores="2"
disk_size="16G"
# network="default"  # Comment out network to use default QEMU user networking
macaddr="52:54:00:12:34:10"
port_forwards=("2210:22" "8080:80" "1194:1194")
tpm="on"
secureboot="on"
EOF
            ;;
        storage)
            cat > "$conf_file" << 'EOF'
# Keystone Storage/NAS VM Configuration
guest_os="linux"
disk_img="disk.qcow2"
iso="../keystone-installer.iso"
ram="4G"
cpu_cores="4"
disk_size="32G"
# network="default"  # Comment out network to use default QEMU user networking
macaddr="52:54:00:12:34:20"
port_forwards=("2220:22" "8081:80" "445:445" "2049:2049")
tpm="on"
secureboot="on"
extra_args="-drive file=data1.qcow2,format=qcow2,if=virtio -drive file=data2.qcow2,format=qcow2,if=virtio"
EOF
            ;;
        client)
            cat > "$conf_file" << 'EOF'
# Keystone Client Workstation VM Configuration
guest_os="linux"
disk_img="disk.qcow2"
iso="../keystone-installer.iso"
ram="8G"
cpu_cores="4"
disk_size="64G"
# network="default"  # Comment out network to use default QEMU user networking
macaddr="52:54:00:12:34:51"
port_forwards=("2251:22")
display="gtk"
viewer="none"
tpm="on"
secureboot="on"
EOF
            ;;
        backup)
            cat > "$conf_file" << 'EOF'
# Keystone Backup Server VM Configuration
guest_os="linux"
disk_img="disk.qcow2"
iso="../keystone-installer.iso"
ram="2G"
cpu_cores="2"
disk_size="32G"
# network="default"  # Comment out network to use default QEMU user networking
macaddr="52:54:00:12:34:30"
port_forwards=("2230:22" "873:873")
tpm="on"
extra_args="-drive file=backup-storage.qcow2,format=qcow2,if=virtio"
EOF
            ;;
        dev)
            cat > "$conf_file" << 'EOF'
# Keystone Development Workstation VM Configuration
guest_os="linux"
disk_img="disk.qcow2"
iso="../keystone-installer.iso"
ram="6G"
cpu_cores="4"
disk_size="48G"
# network="default"  # Comment out network to use default QEMU user networking
macaddr="52:54:00:12:34:52"
port_forwards=("2252:22" "3000:3000" "8000:8000")
display="gtk"
viewer="none"
tpm="on"
secureboot="on"
EOF
            ;;
        offsite)
            cat > "$conf_file" << 'EOF'
# Keystone Off-site/Remote VM Configuration
guest_os="linux"
disk_img="disk.qcow2"
iso="../keystone-installer.iso"
ram="1G"
cpu_cores="1"
disk_size="8G"
network="restrict"
macaddr="52:54:00:12:34:40"
port_forwards=("2240:22")
tpm="off"
secureboot="off"
EOF
            ;;
        *)
            echo "Error: Unknown VM type '$vm_name'"
            return 1
            ;;
    esac
    
    echo "  Created: $conf_file"
}

# Check if VMs directory exists
if [ ! -d "$VMS_DIR" ]; then
    echo "Creating VMs directory: $VMS_DIR"
    mkdir -p "$VMS_DIR"
fi

# Generate configurations for all VM types
VMS=("router" "storage" "client" "backup" "dev" "offsite")

echo "Generating Quickemu configuration files..."
echo "VMs directory: $VMS_DIR"
echo ""

for vm in "${VMS[@]}"; do
    generate_config "$vm"
done

echo ""
echo "Configuration files generated successfully!"
echo ""
echo "Next steps:"
echo "1. Build Keystone ISO: ./scripts/quickemu-cluster.sh build-iso"
echo "2. Start VMs: ./scripts/quickemu-cluster.sh start [vm-name]"
echo "3. Deploy configs: ./scripts/quickemu-cluster.sh deploy [vm-name]"
echo ""
echo "For more information, see: docs/quickemu-testing.md"