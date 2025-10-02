# Quickemu Testing for Keystone

Fast VM testing environment for Keystone NixOS configurations using Quickemu.

## Overview

[Quickemu](https://github.com/quickemu-project/quickemu) is a lightweight wrapper around QEMU that provides simplified VM creation and management. It's designed to "automatically do the right thing" with minimal configuration, making it ideal for rapid testing and development workflows.

### Why Quickemu for Keystone Testing?

**Advantages over libvirt/QEMU:**
- **Simpler Setup**: No XML configuration files or complex libvirt management
- **Better Defaults**: Automatically optimizes VM settings for performance
- **Faster Iteration**: Quick VM creation and destruction for testing
- **Less Infrastructure**: No need for network bridge management
- **Development Focused**: Built for testing and development workflows

**When to Use Quickemu vs libvirt:**

| Scenario | Quickemu | libvirt/QEMU |
|----------|----------|--------------|
| Quick testing | ✅ Ideal | ❌ Overkill |
| Development iteration | ✅ Fast | ⚠️ Slower |
| Production simulation | ⚠️ Basic | ✅ Advanced |
| Network complexity | ⚠️ Limited | ✅ Full control |
| Team environments | ✅ Simple | ✅ Robust |
| CI/CD integration | ✅ Lightweight | ⚠️ Heavy |

## Quick Start

### 1. Install Quickemu

```bash
# On NixOS (add to your configuration)
environment.systemPackages = with pkgs; [ quickemu ];

# Or with Nix flakes
nix shell nixpkgs#quickemu

# On Ubuntu/Debian
sudo apt install quickemu

# On Arch Linux
sudo pacman -S quickemu
```

### 2. Build Keystone ISO

```bash
# Build the installer ISO
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# Copy to quickemu VMs directory
mkdir -p ~/VMs/keystone
cp result/iso/*.iso ~/VMs/keystone/keystone-installer.iso
```

### 3. Create and Start Your First VM

```bash
# Create VM directory and configuration
mkdir -p ~/VMs/keystone-router
cd ~/VMs/keystone-router

# Create configuration file (see templates below)
cat > keystone-router.conf << 'EOF'
guest_os="linux"
disk_img="keystone-router/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="2G"
cpu_cores="2"
disk_size="16G"
network="br0"
macaddr="52:54:00:12:34:10"
port_forwards=("2222:22")
EOF

# Start the VM
quickemu --vm keystone-router.conf
```

## Multi-VM Architecture

### Network Topology

Quickemu VMs can communicate through several networking modes:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Router VM     │    │   Storage VM    │    │   Client VM     │
│ 192.168.122.10  │    │ 192.168.122.20  │    │ 192.168.122.51  │
│ (Gateway/VPN)   │    │ (NAS/Media)     │    │ (Desktop)       │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                        ┌────────┴────────┐
                        │  Host Bridge    │
                        │ (virbr0/br0)    │
                        └─────────────────┘
```

### Bridge Network Setup

Create a bridge network for VM communication:

```bash
# Create bridge (one-time setup)
sudo ip link add name br0 type bridge
sudo ip link set dev br0 up
sudo ip addr add 192.168.122.1/24 dev br0

# Enable NAT for internet access
sudo iptables -t nat -A POSTROUTING -s 192.168.122.0/24 -j MASQUERADE
sudo iptables -A FORWARD -i br0 -o br0 -j ACCEPT

# Make permanent (add to network configuration)
```

## VM Configuration Templates

### Router/Gateway VM

**File: `~/VMs/keystone-router/keystone-router.conf`**
```bash
guest_os="linux"
disk_img="keystone-router/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="2G"
cpu_cores="2"
disk_size="16G"
network="br0"
macaddr="52:54:00:12:34:10"
port_forwards=("2210:22" "8080:80" "1194:1194")
tpm="on"
secureboot="on"
```

### Storage/NAS VM

**File: `~/VMs/keystone-storage/keystone-storage.conf`**
```bash
guest_os="linux"
disk_img="keystone-storage/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="4G"
cpu_cores="4"
disk_size="32G"
network="br0"
macaddr="52:54:00:12:34:20"
port_forwards=("2220:22" "8081:80" "445:445" "2049:2049")
tpm="on"
secureboot="on"

# Additional data disks for ZFS
extra_args="-drive file=keystone-storage/data1.qcow2,format=qcow2,if=virtio -drive file=keystone-storage/data2.qcow2,format=qcow2,if=virtio"
```

### Client Workstation VM

**File: `~/VMs/keystone-client/keystone-client.conf`**
```bash
guest_os="linux"
disk_img="keystone-client/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="8G"
cpu_cores="4"
disk_size="64G"
network="br0"
macaddr="52:54:00:12:34:51"
port_forwards=("2251:22")
display="gtk"
viewer="none"
tpm="on"
secureboot="on"
```

### Backup Server VM

**File: `~/VMs/keystone-backup/keystone-backup.conf`**
```bash
guest_os="linux"
disk_img="keystone-backup/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="2G"
cpu_cores="2"
disk_size="32G"
network="br0"
macaddr="52:54:00:12:34:30"
port_forwards=("2230:22" "873:873")
tpm="on"

# Backup storage disk
extra_args="-drive file=keystone-backup/backup-storage.qcow2,format=qcow2,if=virtio"
```

### Development VM

**File: `~/VMs/keystone-dev/keystone-dev.conf`**
```bash
guest_os="linux"
disk_img="keystone-dev/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="6G"
cpu_cores="4"
disk_size="48G"
network="br0"
macaddr="52:54:00:12:34:52"
port_forwards=("2252:22" "3000:3000" "8000:8000")
display="gtk"
viewer="none"
tpm="on"
secureboot="on"
```

### Off-site/Remote VM

**File: `~/VMs/keystone-offsite/keystone-offsite.conf`**
```bash
guest_os="linux"
disk_img="keystone-offsite/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="1G"
cpu_cores="1"
disk_size="8G"
network="restrict"  # Isolated for security testing
macaddr="52:54:00:12:34:40"
port_forwards=("2240:22")
tpm="off"  # Minimal configuration
secureboot="off"
```

## Automation Scripts

### VM Orchestration Script

**File: `scripts/quickemu-cluster.sh`**
```bash
#!/usr/bin/env bash
# Quickemu Keystone Cluster Management

set -euo pipefail

VMS_DIR="$HOME/VMs"
VMS=("router" "storage" "client" "backup" "dev" "offsite")
KEYSTONE_DIR="$(dirname "$(realpath "$0")")/.."

usage() {
    echo "Usage: $0 {start|stop|status|deploy} [vm-name]"
    echo "  start [vm]    - Start VM(s)"
    echo "  stop [vm]     - Stop VM(s)" 
    echo "  status        - Show VM status"
    echo "  deploy [vm]   - Deploy configuration to VM(s)"
    echo "  build-iso     - Build Keystone installer ISO"
    echo "  setup         - Initial setup and ISO build"
    echo ""
    echo "Available VMs: ${VMS[*]}"
}

build_iso() {
    echo "Building Keystone installer ISO..."
    cd "$KEYSTONE_DIR"
    ./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
    
    # Copy to VMs directory
    mkdir -p "$VMS_DIR/keystone"
    ISO_FILE=$(find result -name "*.iso" | head -n1)
    if [ -n "$ISO_FILE" ]; then
        cp "$ISO_FILE" "$VMS_DIR/keystone/keystone-installer.iso"
        echo "ISO ready at: $VMS_DIR/keystone/keystone-installer.iso"
    else
        echo "Error: ISO file not found"
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
    fi
    
    # Create backup disk
    if [ "$vm_name" = "backup" ]; then
        [ ! -f "$vm_dir/backup-storage.qcow2" ] && qemu-img create -f qcow2 "$vm_dir/backup-storage.qcow2" 128G
    fi
}

start_vm() {
    local vm_name="$1"
    local vm_dir="$VMS_DIR/keystone-$vm_name"
    local conf_file="$vm_dir/keystone-$vm_name.conf"
    
    if [ ! -f "$conf_file" ]; then
        echo "Error: Configuration file not found: $conf_file"
        echo "Run '$0 setup' first or create the configuration manually"
        return 1
    fi
    
    setup_vm "$vm_name"
    
    echo "Starting VM: $vm_name"
    cd "$vm_dir"
    quickemu --vm "keystone-$vm_name.conf" --display none &
    
    # Wait for VM to start
    sleep 5
    echo "VM $vm_name started"
}

stop_vm() {
    local vm_name="$1"
    echo "Stopping VM: $vm_name"
    
    # Find and kill quickemu process for this VM
    pkill -f "keystone-$vm_name.conf" || echo "VM $vm_name not running"
}

deploy_vm() {
    local vm_name="$1"
    local config_name="${2:-$vm_name}"
    
    echo "Deploying configuration '$config_name' to VM '$vm_name'"
    
    # Get VM IP from MAC address (requires network scanning)
    local mac_addr
    case "$vm_name" in
        router) mac_addr="52:54:00:12:34:10" ;;
        storage) mac_addr="52:54:00:12:34:20" ;;
        client) mac_addr="52:54:00:12:34:51" ;;
        backup) mac_addr="52:54:00:12:34:30" ;;
        dev) mac_addr="52:54:00:12:34:52" ;;
        offsite) mac_addr="52:54:00:12:34:40" ;;
    esac
    
    # Find IP by MAC (simplified - may need adjustment for your network)
    local vm_ip
    vm_ip=$(arp -a | grep "$mac_addr" | grep -oP '\d+\.\d+\.\d+\.\d+' | head -n1)
    
    if [ -z "$vm_ip" ]; then
        echo "Could not find IP for VM $vm_name (MAC: $mac_addr)"
        echo "Check VM status and network configuration"
        return 1
    fi
    
    echo "Deploying to $vm_ip..."
    cd "$KEYSTONE_DIR"
    nixos-anywhere --flake ".#$config_name" "root@$vm_ip"
}

case "${1:-}" in
    start)
        if [ -n "${2:-}" ]; then
            start_vm "$2"
        else
            for vm in "${VMS[@]}"; do
                start_vm "$vm"
            done
        fi
        ;;
    stop)
        if [ -n "${2:-}" ]; then
            stop_vm "$2"
        else
            for vm in "${VMS[@]}"; do
                stop_vm "$vm"
            done
        fi
        ;;
    status)
        echo "VM Status:"
        for vm in "${VMS[@]}"; do
            if pgrep -f "keystone-$vm.conf" > /dev/null; then
                echo "  keystone-$vm: RUNNING"
            else
                echo "  keystone-$vm: STOPPED"
            fi
        done
        ;;
    deploy)
        if [ -n "${2:-}" ]; then
            deploy_vm "$2" "${3:-$2}"
        else
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
    setup)
        build_iso
        echo "Creating VM directories and configurations..."
        for vm in "${VMS[@]}"; do
            setup_vm "$vm"
        done
        echo "Setup complete. VM configurations should be created manually."
        echo "See documentation for configuration templates."
        ;;
    *)
        usage
        exit 1
        ;;
esac
```

### Configuration Generator Script

**File: `scripts/generate-quickemu-configs.sh`**
```bash
#!/usr/bin/env bash
# Generate Quickemu configuration files for Keystone VMs

VMS_DIR="$HOME/VMs"

generate_config() {
    local vm_name="$1"
    local vm_dir="$VMS_DIR/keystone-$vm_name"
    local conf_file="$vm_dir/keystone-$vm_name.conf"
    
    mkdir -p "$vm_dir"
    
    case "$vm_name" in
        router)
            cat > "$conf_file" << 'EOF'
guest_os="linux"
disk_img="keystone-router/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="2G"
cpu_cores="2"
disk_size="16G"
network="br0"
macaddr="52:54:00:12:34:10"
port_forwards=("2210:22" "8080:80" "1194:1194")
tpm="on"
secureboot="on"
EOF
            ;;
        storage)
            cat > "$conf_file" << 'EOF'
guest_os="linux"
disk_img="keystone-storage/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="4G"
cpu_cores="4"
disk_size="32G"
network="br0"
macaddr="52:54:00:12:34:20"
port_forwards=("2220:22" "8081:80" "445:445" "2049:2049")
tpm="on"
secureboot="on"
extra_args="-drive file=keystone-storage/data1.qcow2,format=qcow2,if=virtio -drive file=keystone-storage/data2.qcow2,format=qcow2,if=virtio"
EOF
            ;;
        client)
            cat > "$conf_file" << 'EOF'
guest_os="linux"
disk_img="keystone-client/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="8G"
cpu_cores="4"
disk_size="64G"
network="br0"
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
guest_os="linux"
disk_img="keystone-backup/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="2G"
cpu_cores="2"
disk_size="32G"
network="br0"
macaddr="52:54:00:12:34:30"
port_forwards=("2230:22" "873:873")
tpm="on"
extra_args="-drive file=keystone-backup/backup-storage.qcow2,format=qcow2,if=virtio"
EOF
            ;;
        dev)
            cat > "$conf_file" << 'EOF'
guest_os="linux"
disk_img="keystone-dev/disk.qcow2"
iso="../keystone/keystone-installer.iso"
ram="6G"
cpu_cores="4"
disk_size="48G"
network="br0"
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
guest_os="linux"
disk_img="keystone-offsite/disk.qcow2"
iso="../keystone/keystone-installer.iso"
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
    esac
    
    echo "Generated: $conf_file"
}

VMS=("router" "storage" "client" "backup" "dev" "offsite")

for vm in "${VMS[@]}"; do
    generate_config "$vm"
done

echo "All configuration files generated in $VMS_DIR"
```

## Example Workflows

### 1. Quick Development Testing

Test a single configuration change rapidly:

```bash
# Build ISO with changes
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# Start minimal test environment
scripts/quickemu-cluster.sh start router client

# Deploy and test
scripts/quickemu-cluster.sh deploy router
scripts/quickemu-cluster.sh deploy client

# SSH into VMs for testing
ssh -p 2210 root@localhost  # router
ssh -p 2251 root@localhost  # client

# Clean up
scripts/quickemu-cluster.sh stop
```

### 2. Multi-Node Storage Testing

Test NAS and backup interactions:

```bash
# Start storage infrastructure
scripts/quickemu-cluster.sh start storage backup

# Deploy configurations
scripts/quickemu-cluster.sh deploy storage
scripts/quickemu-cluster.sh deploy backup

# Test storage services
ssh -p 2220 root@localhost  # storage
ssh -p 2230 root@localhost  # backup

# Test file sharing
scp -P 2220 testfile.txt root@localhost:/srv/shared/
```

### 3. Complete Infrastructure Test

Full deployment testing:

```bash
# Start all VMs
scripts/quickemu-cluster.sh start

# Deploy all configurations
scripts/quickemu-cluster.sh deploy

# Test connectivity between VMs
# Test VPN connections
# Test service discovery
# Test backup operations

# Create snapshots for later testing
for vm in router storage client backup dev offsite; do
    quickemu --vm ~/VMs/keystone-$vm/keystone-$vm.conf --snapshot create test-snapshot
done
```

### 4. Performance Testing

Test under load:

```bash
# Start performance-critical VMs
scripts/quickemu-cluster.sh start storage dev

# Deploy with performance monitoring
scripts/quickemu-cluster.sh deploy storage
scripts/quickemu-cluster.sh deploy dev

# Run benchmarks
ssh -p 2220 root@localhost "dd if=/dev/zero of=/tmp/test bs=1M count=1000"
ssh -p 2252 root@localhost "stress --cpu 4 --timeout 30s"
```

## Advanced Features

### TPM and Secure Boot Testing

Test TPM2 and Secure Boot functionality:

```bash
# VMs with TPM enabled can test:
# - LUKS encryption with TPM auto-unlock
# - Secure Boot verification
# - Key attestation

# Check TPM status in VM
ssh -p 2210 root@localhost "tpm2_getcap properties-variable"
```

### USB Passthrough Testing

Test USB device access:

```bash
# Add to VM configuration
usb_devices=("054c:0268")  # Specific USB device

# Test USB audio, storage, etc.
```

### Headless CI/CD Integration

Automated testing in CI environments:

```bash
# Headless start
quickemu --vm keystone-router.conf --display none

# Automated deployment testing
timeout 300 scripts/quickemu-cluster.sh deploy router
if [ $? -eq 0 ]; then
    echo "Deployment successful"
else
    echo "Deployment failed"
    exit 1
fi
```

### Snapshot Management

Quick testing with snapshots:

```bash
# Create clean state snapshot
quickemu --vm keystone-router.conf --snapshot create clean-install

# Test changes
# Make modifications...

# Restore to clean state
quickemu --vm keystone-router.conf --snapshot apply clean-install

# Continue testing
```

## Performance Optimization

### Resource Allocation Guidelines

| VM Type | Minimum | Recommended | Development |
|---------|---------|-------------|-------------|
| Router | 1G/1CPU | 2G/2CPU | 2G/2CPU |
| Storage | 2G/2CPU | 4G/4CPU | 6G/4CPU |
| Client | 4G/2CPU | 8G/4CPU | 12G/6CPU |
| Backup | 1G/1CPU | 2G/2CPU | 2G/2CPU |
| Dev | 4G/2CPU | 6G/4CPU | 8G/6CPU |
| Off-site | 512M/1CPU | 1G/1CPU | 1G/1CPU |

### Host System Requirements

- **Minimum**: 16GB RAM, 4-core CPU, 200GB storage
- **Recommended**: 32GB RAM, 8-core CPU, 500GB SSD
- **Development**: 64GB RAM, 12-core CPU, 1TB NVME

### Performance Tuning

```bash
# Enable KVM acceleration
modprobe kvm-intel  # or kvm-amd

# Optimize disk performance
echo 'preallocation="metadata"' >> vm.conf

# Use host CPU features
echo 'cpu_cores="host"' >> vm.conf

# Allocate hugepages for better memory performance
echo 'vm.nr_hugepages=1024' >> /etc/sysctl.conf
```

## Troubleshooting

### Common Issues

**VM Won't Start:**
```bash
# Check QEMU/KVM support
ls /dev/kvm
qemu-system-x86_64 --version

# Check configuration syntax
quickemu --vm vm.conf --dry-run
```

**Network Issues:**
```bash
# Verify bridge exists
ip link show br0

# Check bridge connectivity
ping 192.168.122.1

# Verify VM network
ssh -p 2210 root@localhost "ip addr show"
```

**Performance Issues:**
```bash
# Check host resources
htop
free -h
df -h

# Monitor VM performance
ssh -p 2210 root@localhost "htop"
```

**Deployment Failures:**
```bash
# Check SSH connectivity
ssh -p 2210 root@localhost

# Verify nixos-anywhere can connect
nixos-anywhere --dry-run --flake .#router root@localhost

# Check VM console for errors
quickemu --vm keystone-router.conf --monitor
```

### Network Debugging

```bash
# Check VM connectivity
for port in 2210 2220 2251 2230 2252 2240; do
    echo "Testing port $port:"
    nc -zv localhost $port
done

# Monitor network traffic
sudo tcpdump -i br0

# Check ARP table for VM MACs
arp -a | grep "52:54:00:12:34"
```

### Log Analysis

```bash
# Quickemu logs
journalctl -u quickemu

# QEMU logs (if available)
cat ~/.local/share/quickemu/logs/keystone-router.log

# VM console logs
ssh -p 2210 root@localhost "journalctl -f"
```

## Comparison: Quickemu vs libvirt

| Feature | Quickemu | libvirt/QEMU |
|---------|----------|--------------|
| **Setup Complexity** | ⭐⭐⭐⭐⭐ Simple | ⭐⭐ Complex |
| **Configuration** | Key=value files | XML definitions |
| **Network Management** | Basic bridge support | Full network control |
| **Performance** | Good defaults | Highly tunable |
| **Snapshot Management** | Built-in commands | virsh snapshots |
| **Development Speed** | ⭐⭐⭐⭐⭐ Fast | ⭐⭐⭐ Moderate |
| **Production Readiness** | ⭐⭐⭐ Good | ⭐⭐⭐⭐⭐ Excellent |
| **Resource Usage** | Lower overhead | Higher overhead |
| **Learning Curve** | ⭐⭐⭐⭐⭐ Easy | ⭐⭐ Steep |
| **Automation** | Shell scripts | Complex APIs |

### When to Choose Each

**Choose Quickemu for:**
- Rapid development and testing
- Individual developer workflows
- Quick feature validation
- CI/CD testing pipelines
- Learning and experimentation

**Choose libvirt for:**
- Production simulations
- Complex network topologies
- Team development environments
- Long-running test infrastructure
- Advanced virtualization features

## Integration with Keystone

Quickemu integrates seamlessly with Keystone's existing tools:

- **ISO Building**: Use existing `bin/build-iso` script
- **Configurations**: Deploy with `nixos-anywhere` as normal
- **Module Testing**: Test all Keystone modules in isolation
- **Network Services**: Port forwarding exposes services
- **Development**: Fast iteration on configuration changes

This makes Quickemu an excellent complement to the full libvirt infrastructure, providing a lightweight option for daily development and testing workflows.