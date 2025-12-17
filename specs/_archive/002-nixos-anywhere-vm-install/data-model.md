# Data Model: NixOS-Anywhere VM Installation

**Feature**: 002-nixos-anywhere-vm-install
**Date**: 2025-10-22
**Phase**: 1 - Design

## Overview

This document describes the configuration structure and data entities for the nixos-anywhere VM installation feature. Since this is infrastructure-as-code, the "data model" is represented as NixOS configuration options and their relationships.

## Configuration Entities

### 1. Deployment Target Configuration

**Entity**: `nixosConfiguration`

**Description**: A complete system configuration that can be deployed to a target machine.

**Attributes**:
- `system`: Target architecture (e.g., "x86_64-linux")
- `modules`: List of NixOS modules to include
- `specialArgs`: Additional arguments passed to modules (optional)

**Relationships**:
- Composes multiple NixOS modules (server, disko, etc.)
- References external inputs (nixpkgs, disko)
- Defines a buildable system derivation

**Example Structure**:
```nix
nixosConfigurations.test-server = {
  system = "x86_64-linux";
  modules = [
    disko.nixosModules.disko
    ./modules/server
    ./modules/disko-single-disk-root
    ./vms/test-server/configuration.nix
  ];
}
```

**Validation Rules**:
- `system` must be a supported NixOS platform
- All module paths must exist and be valid NixOS modules
- Required options must be set (hostname, disk device, SSH keys)

### 2. Disko Configuration

**Entity**: `keystone.disko` (module options)

**Description**: Disk partitioning and encryption configuration.

**Required Attributes**:
- `enable`: Boolean to activate disko configuration
- `device`: Absolute path to target disk device

**Optional Attributes**:
- `enableEncryptedSwap`: Whether to create encrypted swap (default: true)
- `swapSize`: Size of swap partition (default: "64G")
- `espSize`: Size of EFI system partition (default: "1G")

**Relationships**:
- Controls disk layout and ZFS pool creation
- Defines encryption parameters
- Creates filesystem mount structure

**Validation Rules**:
- `device` must be absolute path starting with `/dev/`
- `swapSize` and `espSize` must be valid size strings (e.g., "64G", "1G")
- Cannot be enabled without disko module imported

### 3. Server Configuration

**Entity**: `keystone.server` (module options)

**Description**: Server-specific system configuration.

**Attributes**:
- `enable`: Boolean to activate server configuration (default: true)

**Implied Configuration**:
- SSH server enabled with key-only authentication
- mDNS service (Avahi) for network discovery
- Firewall enabled with SSH port 22 allowed
- Server-optimized kernel parameters
- System administration tools installed

**Relationships**:
- Depends on base NixOS system
- Integrates with disko for storage
- Provides networking and security baseline

**Validation Rules**:
- Requires at least one SSH authorized key configured
- Hostname must be set

### 4. System Identity

**Entity**: `networking.hostName` (NixOS option)

**Description**: Unique identifier for the deployed system.

**Attributes**:
- String value representing the system hostname

**Validation Rules**:
- Must be valid hostname (alphanumeric, hyphens, no spaces)
- Should be unique within the network
- Used by mDNS for `<hostname>.local` resolution

**Relationships**:
- Advertised via mDNS/Avahi
- Used in system logging and identification
- Part of SSH host identification

### 5. SSH Access Configuration

**Entity**: `users.users.<name>.openssh.authorizedKeys.keys` (NixOS option)

**Description**: List of SSH public keys authorized to access the system.

**Attributes**:
- Array of SSH public key strings
- Typically configured for root user
- Each key is a complete SSH public key line

**Validation Rules**:
- Each key must be valid SSH public key format
- Keys should include identifying comments
- At least one key required for remote access

**Relationships**:
- Controls post-deployment SSH access
- Integrates with OpenSSH server configuration
- Required for automated deployments

## Configuration Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Flake Input (flake.nix)                                     │
│                                                              │
│  nixosConfigurations.test-server                            │
│  ├─ system: "x86_64-linux"                                  │
│  └─ modules: [...]                                          │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ├──────────────────────────────────────────┐
                   │                                          │
                   ▼                                          ▼
        ┌──────────────────────┐                ┌────────────────────────┐
        │ Disko Module          │                │ Server Module          │
        │                       │                │                        │
        │ keystone.disko        │                │ keystone.server        │
        │ ├─ enable: true       │                │ └─ enable: true        │
        │ ├─ device: "/dev/vda" │                │                        │
        │ └─ swapSize: "64G"    │                │ Provides:              │
        │                       │                │ ├─ SSH server          │
        │ Creates:              │                │ ├─ mDNS/Avahi          │
        │ ├─ ESP partition      │                │ ├─ Firewall rules      │
        │ ├─ ZFS pool "rpool"   │                │ └─ Admin tools         │
        │ ├─ Credstore (LUKS)   │                │                        │
        │ └─ Encrypted datasets │                │                        │
        └───────────┬───────────┘                └────────────┬───────────┘
                    │                                         │
                    └──────────────┬──────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────────────────┐
                    │ System-Level Configuration               │
                    │                                          │
                    │ ├─ networking.hostName: "test-server"   │
                    │ ├─ users.users.root.openssh.authorized  │
                    │ │  Keys.keys: ["ssh-ed25519 ..."]       │
                    │ └─ Additional system settings           │
                    └──────────────────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────────────────┐
                    │ Built System Configuration               │
                    │ (Ready for nixos-anywhere deployment)    │
                    └──────────────────────────────────────────┘
```

## State Transitions

### Deployment Lifecycle

```
┌─────────────┐
│ Undeployed  │  Initial state - configuration exists in flake
│ (config)    │
└──────┬──────┘
       │
       │ nixos-anywhere --flake .#test-server root@target-ip
       │
       ▼
┌─────────────┐
│ Deploying   │  Disk partitioning, formatting, system installation
└──────┬──────┘
       │
       │ Installation completes, system reboots
       │
       ▼
┌─────────────┐
│ First Boot  │  Credstore unlock (password prompt), ZFS key load
└──────┬──────┘
       │
       │ Boot completes, services start
       │
       ▼
┌─────────────┐
│ Running     │  System operational, SSH accessible
│             │  Services: sshd, avahi, systemd-resolved
└─────────────┘
```

### Encryption State

```
┌─────────────┐
│ Credstore   │  LUKS volume containing ZFS encryption key
│ (locked)    │
└──────┬──────┘
       │
       │ Boot process: TPM2 unlock OR password prompt
       │
       ▼
┌─────────────┐
│ Credstore   │  Mounted at /etc/credstore in initrd
│ (unlocked)  │
└──────┬──────┘
       │
       │ systemd credential loaded
       │
       ▼
┌─────────────┐
│ ZFS Pool    │  Key loaded from credstore
│ (unlocked)  │  Datasets mountable
└──────┬──────┘
       │
       │ Filesystems mounted
       │
       ▼
┌─────────────┐
│ System      │  Root, /nix, /var, /home accessible
│ (running)   │
└─────────────┘
```

## Configuration Validation

### Required Configuration Checklist

- [ ] `networking.hostName` is set
- [ ] `keystone.disko.enable = true`
- [ ] `keystone.disko.device` points to correct disk
- [ ] At least one SSH public key configured
- [ ] `keystone.server.enable = true`
- [ ] System architecture matches target hardware

### Common Configuration Errors

1. **Missing SSH keys**: Deployment succeeds but system is inaccessible
   - **Fix**: Add `users.users.root.openssh.authorizedKeys.keys`

2. **Wrong disk device**: Formats incorrect disk or fails to find device
   - **Fix**: Verify device path with `lsblk` on target system

3. **Hostname conflict**: mDNS collision on network
   - **Fix**: Choose unique hostname for network

4. **Missing disko module import**: Configuration fails to build
   - **Fix**: Import `disko.nixosModules.disko` in modules list

## Schema Representation

Since this is NixOS, the "schema" is defined by module option types. Here's the relevant subset:

```nix
{
  # Deployment target configuration
  nixosConfigurations.<name> = {
    system = types.str;
    modules = types.listOf types.deferredModule;
  };

  # Disko module options
  options.keystone.disko = {
    enable = types.bool;
    device = types.str;
    enableEncryptedSwap = types.bool;
    swapSize = types.str;
    espSize = types.str;
  };

  # Server module options
  options.keystone.server = {
    enable = types.bool;
  };

  # NixOS system options (subset used)
  options.networking.hostName = types.str;
  options.users.users.<name>.openssh.authorizedKeys.keys = types.listOf types.str;
}
```

## Summary

The data model for this feature is primarily **declarative configuration** rather than runtime data structures. The key entities are:

1. **nixosConfiguration**: Deployment target definition
2. **Disko options**: Disk and encryption configuration
3. **Server options**: System services and security
4. **System identity**: Hostname and network presence
5. **SSH access**: Authentication credentials

All configuration is expressed in Nix language and evaluated at build time to produce a bootable system image that nixos-anywhere deploys to the target machine.
