# Keystone VM Infrastructure

Multi-VM testing environment for Keystone NixOS configurations using libvirt/QEMU.

## Overview

This infrastructure provides 2-6 virtual machines for testing complete Keystone deployments locally:

- **Router** (keystone-router) - Gateway with VPN, DNS, firewall
- **Storage** (keystone-storage) - NAS with ZFS, media services, Samba/NFS
- **Client** (keystone-client) - Hyprland desktop workstation
- **Backup** (keystone-backup) - Backup server with Restic/rsync
- **Dev** (keystone-dev) - Development workstation with tools
- **Off-site** (keystone-off-site) - Remote/VPS simulation

## Quick Start

1. **Setup the network:**
   ```bash
   cd vm-infrastructure
   make setup-network
   ```

2. **Build the installer ISO:**
   ```bash
   make build-iso
   ```

3. **Start VMs (choose any combination):**
   ```bash
   # Start all VMs
   make up-all
   
   # Or start specific VMs
   make up-router up-storage up-client
   ```

4. **Deploy configurations:**
   ```bash
   # Deploy to all running VMs
   make deploy-all
   
   # Or deploy to specific VMs
   make deploy-router
   make deploy-storage CONFIG=nas  # Use different config
   ```

## Network Architecture

- **Network**: `keystone-net` (192.168.100.0/24)
- **Gateway**: 192.168.100.1 (host)
- **DHCP Range**: 192.168.100.50-100 (clients)
- **Static IPs**:
  - Router: 192.168.100.10
  - Storage: 192.168.100.20  
  - Backup: 192.168.100.30
  - Off-site: 192.168.100.40

## VM Specifications

| VM | RAM | CPU | Disk | Purpose |
|----|-----|-----|------|---------|
| Router | 2GB | 2 | 16GB | Gateway, VPN, DNS |
| Storage | 4GB | 4 | 32GB + 2x64GB data | NAS, media, backup target |
| Client | 8GB | 4 | 64GB | Desktop workstation |
| Backup | 2GB | 2 | 32GB + 128GB backup | Backup services |
| Dev | 6GB | 4 | 48GB | Development environment |
| Off-site | 1GB | 1 | 8GB | Remote/VPS simulation |

## Available Commands

### Network Management
```bash
make setup-network      # Create virtual network
make clean-network      # Remove virtual network
make teardown-network   # Complete teardown
```

### VM Management
```bash
make up-<vm>            # Start specific VM
make down-<vm>          # Stop specific VM  
make clean-<vm>         # Remove VM and disks
make up-all             # Start all VMs
make down-all           # Stop all VMs
make clean-all          # Remove all VMs
```

### Deployment
```bash
make deploy-<vm>        # Deploy default config to VM
make deploy-<vm> CONFIG=name  # Deploy specific config
make deploy-all         # Deploy to all running VMs
```

### Monitoring
```bash
make status             # Show VM and network status
make snapshot-all       # Create snapshots of running VMs
```

## Configuration Files

VM configurations are in `configs/`:

- `router.nix` - Router/gateway server
- `storage.nix` - NAS/storage server  
- `client.nix` - Desktop workstation
- `backup.nix` - Backup server
- `dev.nix` - Development workstation
- `off-site.nix` - Remote server

Each config imports the appropriate Keystone modules and sets up:
- Encrypted disk with TPM2 (where supported)
- Network configuration
- Role-specific services
- Security hardening

## Directory Structure

```
vm-infrastructure/
├── Makefile              # Main orchestration
├── README.md             # This file
├── network/
│   └── keystone-net.xml  # Virtual network definition
├── vms/                  # VM definitions
│   ├── router/vm.xml
│   ├── storage/vm.xml
│   ├── client/vm.xml
│   ├── backup/vm.xml
│   ├── dev/vm.xml
│   └── off-site/vm.xml
├── scripts/              # Helper scripts
│   ├── build-and-boot.sh # ISO building
│   └── deploy-vm.sh      # Deployment automation
└── configs/              # NixOS configurations
    ├── router.nix
    ├── storage.nix
    ├── client.nix
    ├── backup.nix
    ├── dev.nix
    └── off-site.nix
```

## Example Workflows

### Test a Complete Home Lab
```bash
# Start core infrastructure
make up-router up-storage up-backup

# Add workstations
make up-client up-dev

# Deploy everything
make deploy-all

# Check status
make status
```

### Development Testing
```bash
# Start minimal setup
make up-router up-dev

# Deploy with custom configs
make deploy-router
make deploy-dev CONFIG=development

# Test changes...

# Snapshot current state
make snapshot-all
```

### Simulate VPS Deployment
```bash
# Test off-site configuration
make up-off-site
make deploy-off-site

# Verify connectivity
ssh root@192.168.100.40
```

## Requirements

- libvirt/QEMU
- virsh command-line tools
- Sufficient RAM (minimum 8GB recommended for multiple VMs)
- Disk space for VM images (~500GB recommended)

## Troubleshooting

### VMs Won't Start
- Check libvirt service: `systemctl status libvirtd`
- Verify network: `virsh net-list`
- Check disk space: `df -h /tmp`

### Network Issues
- Restart network: `virsh net-destroy keystone-net && virsh net-start keystone-net`
- Check DHCP leases: `virsh net-dhcp-leases keystone-net`

### Deployment Failures
- Verify SSH access: `ssh root@<vm-ip>`
- Check VM console: `virsh console keystone-<vm>`
- Review deployment logs

### Performance Issues
- Reduce number of concurrent VMs
- Increase VM memory if host allows
- Use snapshots to avoid full rebuilds

## Integration with Physical Hardware

These VM configurations serve as templates for real hardware deployment:

```bash
# Deploy router config to physical hardware
nixos-anywhere --flake .#router root@192.168.1.100

# Deploy storage config to NAS hardware  
nixos-anywhere --flake .#storage root@192.168.1.101
```

The configurations are designed to work with both VMs and bare metal with minimal changes.