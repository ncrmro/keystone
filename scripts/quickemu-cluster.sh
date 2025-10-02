#!/usr/bin/env bash
# Quickemu Keystone Cluster Management

set -euo pipefail

KEYSTONE_DIR="$(dirname "$(realpath "$0")")/.."
VMS_DIR="$KEYSTONE_DIR/vms"
VMS=("router" "storage" "client" "backup" "dev" "offsite")

usage() {
    echo "Usage: $0 {start|stop|status|deploy|build-iso|setup} [vm-name]"
    echo ""
    echo "Commands:"
    echo "  start [vm]    - Start VM(s)"
    echo "  stop [vm]     - Stop VM(s)" 
    echo "  status        - Show VM status"
    echo "  deploy [vm]   - Deploy configuration to VM(s)"
    echo "  build-iso     - Build Keystone installer ISO"
    echo "  setup         - Initial setup and ISO build"
    echo "  generate      - Generate VM configuration files"
    echo ""
    echo "Available VMs: ${VMS[*]}"
    echo ""
    echo "Examples:"
    echo "  $0 setup              # Initial setup"
    echo "  $0 start router       # Start router VM"
    echo "  $0 start              # Start all VMs"
    echo "  $0 deploy client      # Deploy client config"
    echo "  $0 status             # Show all VM status"
}

build_iso() {
    echo "Building Keystone installer ISO using flake..."
    cd "$KEYSTONE_DIR"
    
    # Build ISO using the flake's iso package
    if nix build .#iso; then
        echo "ISO build successful"
        
        # Copy to VMs directory
        mkdir -p "$VMS_DIR"
        ISO_FILE=$(find result/iso -name "*.iso" 2>/dev/null | head -n1)
        if [ -n "$ISO_FILE" ]; then
            cp "$ISO_FILE" "$VMS_DIR/keystone-installer.iso"
            echo "ISO ready at: $VMS_DIR/keystone-installer.iso"
            
            # Show ISO info
            echo "ISO size: $(du -h "$VMS_DIR/keystone-installer.iso" | cut -f1)"
        else
            echo "Error: ISO file not found in result directory"
            echo "Available files in result:"
            find result -type f 2>/dev/null || echo "  (no result directory)"
            exit 1
        fi
    else
        echo "Error: Failed to build ISO using nix build .#iso"
        exit 1
    fi
}

setup_vm() {
    local vm_name="$1"
    local vm_dir="$VMS_DIR/keystone-$vm_name"
    
    echo "Setting up VM: $vm_name"
    mkdir -p "$vm_dir"
    
    # Create additional disks for storage VMs
    if [ "$vm_name" = "storage" ]; then
        [ ! -f "$vm_dir/data1.qcow2" ] && qemu-img create -f qcow2 "$vm_dir/data1.qcow2" 64G
        [ ! -f "$vm_dir/data2.qcow2" ] && qemu-img create -f qcow2 "$vm_dir/data2.qcow2" 64G
        echo "  Created storage data disks"
    fi
    
    # Create backup disk
    if [ "$vm_name" = "backup" ]; then
        [ ! -f "$vm_dir/backup-storage.qcow2" ] && qemu-img create -f qcow2 "$vm_dir/backup-storage.qcow2" 128G
        echo "  Created backup storage disk"
    fi
}

start_vm() {
    local vm_name="$1"
    local vm_dir="$VMS_DIR/keystone-$vm_name"
    local conf_file="$vm_dir/keystone-$vm_name.conf"
    
    if [ ! -f "$conf_file" ]; then
        echo "Error: Configuration file not found: $conf_file"
        echo "Run '$0 generate' first to create configuration files"
        return 1
    fi
    
    # Check if already running
    if pgrep -f "keystone-$vm_name.conf" > /dev/null; then
        echo "VM $vm_name is already running"
        return 0
    fi
    
    # Check for ISO file
    local iso_path="$VMS_DIR/keystone-installer.iso"
    if [ ! -f "$iso_path" ]; then
        echo "Error: Keystone installer ISO not found: $iso_path"
        echo "Run '$0 build-iso' first to build the installer ISO"
        return 1
    fi
    
    setup_vm "$vm_name"
    
    echo "Starting VM: $vm_name"
    cd "$vm_dir"
    
    # Note: Removed dry-run validation as quickemu doesn't support --dry-run
    # Configuration validation will happen during actual startup
    
    # Start VM in background
    nohup quickemu --vm "keystone-$vm_name.conf" --display none > "keystone-$vm_name.log" 2>&1 &
    local pid=$!
    
    # Wait a moment to see if it starts successfully
    sleep 5
    if pgrep -f "keystone-$vm_name" > /dev/null; then
        echo "VM $vm_name started (PID: $pid)"
        echo "Log: $vm_dir/keystone-$vm_name.log"
        
        # Show connection info
        case "$vm_name" in
            router) echo "SSH: ssh -p 2210 root@localhost" ;;
            storage) echo "SSH: ssh -p 2220 root@localhost" ;;
            client) echo "SSH: ssh -p 2251 root@localhost" ;;
            backup) echo "SSH: ssh -p 2230 root@localhost" ;;
            dev) echo "SSH: ssh -p 2252 root@localhost" ;;
            offsite) echo "SSH: ssh -p 2240 root@localhost" ;;
        esac
    else
        echo "Error: VM $vm_name failed to start"
        echo "Check log: $vm_dir/keystone-$vm_name.log"
        if [ -f "$vm_dir/keystone-$vm_name.log" ]; then
            echo "Last few lines of log:"
            tail -5 "$vm_dir/keystone-$vm_name.log" | sed 's/^/  /'
        fi
        return 1
    fi
}

stop_vm() {
    local vm_name="$1"
    echo "Stopping VM: $vm_name"
    
    # Find and kill quickemu process for this VM
    if pgrep -f "keystone-$vm_name.conf" > /dev/null; then
        pkill -f "keystone-$vm_name.conf"
        sleep 2
        # Force kill if still running
        pkill -9 -f "keystone-$vm_name.conf" 2>/dev/null || true
        echo "VM $vm_name stopped"
    else
        echo "VM $vm_name is not running"
    fi
}

get_vm_ip() {
    local vm_name="$1"
    local mac_addr
    
    case "$vm_name" in
        router) mac_addr="52:54:00:12:34:10" ;;
        storage) mac_addr="52:54:00:12:34:20" ;;
        client) mac_addr="52:54:00:12:34:51" ;;
        backup) mac_addr="52:54:00:12:34:30" ;;
        dev) mac_addr="52:54:00:12:34:52" ;;
        offsite) mac_addr="52:54:00:12:34:40" ;;
        *)
            echo "Unknown VM: $vm_name" >&2
            return 1
            ;;
    esac
    
    # Try multiple methods to find IP
    local vm_ip
    
    # Method 1: ARP table
    vm_ip=$(arp -a 2>/dev/null | grep -i "$mac_addr" | grep -oP '\d+\.\d+\.\d+\.\d+' | head -n1)
    
    # Method 2: DHCP leases (if available)
    if [ -z "$vm_ip" ] && [ -f /var/lib/dhcp/dhcpd.leases ]; then
        vm_ip=$(grep -i "$mac_addr" /var/lib/dhcp/dhcpd.leases -A 5 | grep "binding state active" -B 5 | grep -oP 'lease \K\d+\.\d+\.\d+\.\d+' | tail -n1)
    fi
    
    # Method 3: Network scan (as last resort)
    if [ -z "$vm_ip" ]; then
        echo "Scanning network for VM $vm_name (MAC: $mac_addr)..." >&2
        # Scan common VM network ranges
        for network in "192.168.122" "192.168.100" "10.0.2"; do
            vm_ip=$(nmap -sn "$network.0/24" 2>/dev/null | grep -B 2 -i "$mac_addr" | grep "Nmap scan report" | grep -oP '\d+\.\d+\.\d+\.\d+' | head -n1)
            [ -n "$vm_ip" ] && break
        done
    fi
    
    echo "$vm_ip"
}

deploy_vm() {
    local vm_name="$1"
    local config_name="${2:-$vm_name}"
    
    echo "Deploying configuration '$config_name' to VM '$vm_name'"
    
    # Check if VM is running
    if ! pgrep -f "keystone-$vm_name.conf" > /dev/null; then
        echo "Error: VM $vm_name is not running"
        echo "Start it first with: $0 start $vm_name"
        return 1
    fi
    
    # Get VM IP
    local vm_ip
    vm_ip=$(get_vm_ip "$vm_name")
    
    if [ -z "$vm_ip" ]; then
        echo "Could not find IP for VM $vm_name"
        echo "Check VM status and network configuration"
        echo "Try connecting via port forwarding instead:"
        case "$vm_name" in
            router) echo "  ssh -p 2210 root@localhost" ;;
            storage) echo "  ssh -p 2220 root@localhost" ;;
            client) echo "  ssh -p 2251 root@localhost" ;;
            backup) echo "  ssh -p 2230 root@localhost" ;;
            dev) echo "  ssh -p 2252 root@localhost" ;;
            offsite) echo "  ssh -p 2240 root@localhost" ;;
        esac
        return 1
    fi
    
    echo "Found VM at IP: $vm_ip"
    
    # Wait for SSH to be available
    echo "Waiting for SSH to be available..."
    local timeout=300
    local elapsed=0
    while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$vm_ip" true 2>/dev/null; do
        if [ $elapsed -ge $timeout ]; then
            echo "Error: SSH connection timeout after ${timeout}s"
            return 1
        fi
        echo "  Still waiting... (${elapsed}s/${timeout}s)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    echo "Deploying to $vm_ip..."
    cd "$KEYSTONE_DIR"
    if nixos-anywhere --flake ".#$config_name" "root@$vm_ip"; then
        echo "Deployment successful!"
    else
        echo "Deployment failed!"
        return 1
    fi
}

generate_configs() {
    echo "Generating Quickemu configuration files..."
    "$KEYSTONE_DIR/scripts/generate-quickemu-configs.sh"
}

show_status() {
    echo "Quickemu Keystone VM Status:"
    echo "============================"
    
    local running_count=0
    for vm in "${VMS[@]}"; do
        local status="STOPPED"
        local pid=""
        if pgrep -f "keystone-$vm" > /dev/null; then
            status="RUNNING"
            pid=$(pgrep -f "keystone-$vm")
            running_count=$((running_count + 1))
        fi
        
        printf "  %-12s: %-8s" "keystone-$vm" "$status"
        [ -n "$pid" ] && printf " (PID: %s)" "$pid"
        echo
    done
    
    echo ""
    echo "Summary: $running_count/${#VMS[@]} VMs running"
    
    if [ $running_count -gt 0 ]; then
        echo ""
        echo "VM Access (via port forwarding):"
        for vm in "${VMS[@]}"; do
            if pgrep -f "keystone-$vm.conf" > /dev/null; then
                case "$vm" in
                    router) echo "  router:  ssh -p 2210 root@localhost" ;;
                    storage) echo "  storage: ssh -p 2220 root@localhost" ;;
                    client) echo "  client:  ssh -p 2251 root@localhost" ;;
                    backup) echo "  backup:  ssh -p 2230 root@localhost" ;;
                    dev) echo "  dev:     ssh -p 2252 root@localhost" ;;
                    offsite) echo "  offsite: ssh -p 2240 root@localhost" ;;
                esac
            fi
        done
    fi
}

main() {
    case "${1:-}" in
        start)
            if [ -n "${2:-}" ]; then
                if [[ " ${VMS[*]} " =~ " $2 " ]]; then
                    start_vm "$2"
                else
                    echo "Error: Unknown VM '$2'"
                    echo "Available VMs: ${VMS[*]}"
                    exit 1
                fi
            else
                echo "Starting all VMs..."
                for vm in "${VMS[@]}"; do
                    start_vm "$vm" || echo "Warning: Failed to start $vm"
                done
            fi
            ;;
        stop)
            if [ -n "${2:-}" ]; then
                if [[ " ${VMS[*]} " =~ " $2 " ]]; then
                    stop_vm "$2"
                else
                    echo "Error: Unknown VM '$2'"
                    echo "Available VMs: ${VMS[*]}"
                    exit 1
                fi
            else
                echo "Stopping all VMs..."
                for vm in "${VMS[@]}"; do
                    stop_vm "$vm"
                done
            fi
            ;;
        status)
            show_status
            ;;
        deploy)
            if [ -n "${2:-}" ]; then
                if [[ " ${VMS[*]} " =~ " $2 " ]]; then
                    deploy_vm "$2" "${3:-$2}"
                else
                    echo "Error: Unknown VM '$2'"
                    echo "Available VMs: ${VMS[*]}"
                    exit 1
                fi
            else
                echo "Deploying to all running VMs..."
                for vm in "${VMS[@]}"; do
                    if pgrep -f "keystone-$vm.conf" > /dev/null; then
                        deploy_vm "$vm" || echo "Warning: Failed to deploy to $vm"
                    else
                        echo "Skipping $vm (not running)"
                    fi
                done
            fi
            ;;
        build-iso)
            build_iso
            ;;
        generate)
            generate_configs
            ;;
        setup)
            echo "Setting up Quickemu Keystone environment..."
            build_iso
            generate_configs
            echo ""
            echo "Setup complete!"
            echo "You can now start VMs with: $0 start [vm-name]"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Check if quickemu is available
if ! command -v quickemu >/dev/null 2>&1; then
    echo "Error: quickemu is not installed or not in PATH"
    echo "Please install quickemu first:"
    echo "  - NixOS: Add 'quickemu' to environment.systemPackages"
    echo "  - Ubuntu: sudo apt install quickemu"
    echo "  - Arch: sudo pacman -S quickemu"
    exit 1
fi

# Check if qemu-img is available
if ! command -v qemu-img >/dev/null 2>&1; then
    echo "Error: qemu-img is not installed or not in PATH"
    echo "Please install QEMU tools"
    exit 1
fi

main "$@"