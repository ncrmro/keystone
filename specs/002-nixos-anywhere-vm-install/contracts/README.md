# Configuration Contracts

**Feature**: 002-nixos-anywhere-vm-install
**Date**: 2025-10-22

## Overview

This directory contains the "contracts" for the nixos-anywhere VM installation feature. In the context of NixOS infrastructure, contracts are represented as:

1. **Module option schemas** (type definitions)
2. **Configuration examples** (usage contracts)
3. **Interface specifications** (how components interact)

Unlike traditional API contracts (REST/GraphQL), NixOS contracts are declarative configuration interfaces.

## Contracts Defined

### 1. Deployment Configuration Contract

**File**: [`deployment-config.nix`](./deployment-config.nix)

**Purpose**: Defines the structure and requirements for a minimal Keystone server deployment configuration.

**Required Fields**:
- `system`: Target architecture
- `modules`: List including disko and server modules
- `networking.hostName`: Unique system identifier
- `keystone.disko.enable`: Must be `true`
- `keystone.disko.device`: Disk device path
- `users.users.root.openssh.authorizedKeys.keys`: At least one SSH key

**Optional Fields**:
- `keystone.disko.enableEncryptedSwap`: Boolean (default: true)
- `keystone.disko.swapSize`: String (default: "64G")
- `keystone.disko.espSize`: String (default: "1G")
- `keystone.server.enable`: Boolean (default: true)

**Validation**:
- NixOS type system enforces types at evaluation time
- Assertions in modules check required options
- Build fails if contract violated

### 2. Deployment Command Interface

**File**: [`deployment-commands.md`](./deployment-commands.md)

**Purpose**: Specifies the command-line interface for deployment operations.

**Commands**:

#### Deploy to VM
```bash
nixos-anywhere --flake .#test-server root@<target-ip>
```

**Parameters**:
- `--flake`: Path to flake with `#` separator and configuration name
- Target: SSH connection string (`root@<ip-address>`)

**Preconditions**:
- Target system booted from Keystone ISO
- SSH access enabled on target
- Network connectivity between dev machine and target

**Postconditions**:
- System installed and configured
- Target reboots into installed system
- SSH access available with configured keys

#### Verify Deployment
```bash
./scripts/verify-deployment.sh test-server <target-ip>
```

**Parameters**:
- Configuration name (matches flake output)
- Target IP address or hostname

**Exit Codes**:
- `0`: All checks passed
- `1`: One or more checks failed
- `2`: Cannot connect to target

### 3. Module Interface Contract

**File**: [`module-interface.nix`](./module-interface.nix)

**Purpose**: Defines how modules interact and their dependencies.

**Module Dependencies**:
```
test-server configuration
  ├─ disko.nixosModules.disko (external)
  ├─ keystone.server (local)
  │   └─ Requires: networking, users, services options
  ├─ keystone.disko (local)
  │   ├─ Requires: disko module, boot options
  │   └─ Provides: fileSystems, boot.initrd configuration
  └─ VM-specific overrides (local)
      └─ Provides: hostname, SSH keys, disk device
```

**Interface Points**:
- **Input**: Flake reference (`.#test-server`)
- **Composition**: Module list evaluation
- **Output**: Bootable system closure
- **Deployment**: SSH-based installation

### 4. Verification Contract

**File**: [`verification-checks.md`](./verification-checks.md)

**Purpose**: Defines the checks performed to verify successful deployment.

**Required Checks**:
1. **SSH Connectivity**: Can connect to target via SSH
2. **Hostname Verification**: System reports correct hostname
3. **Firewall Status**: Only SSH port 22 is open
4. **ZFS Pool Status**: `rpool` is imported and healthy
5. **Encryption Status**: Datasets are encrypted and unlocked
6. **Service Status**: sshd, avahi, systemd-resolved are active
7. **mDNS Advertisement**: System responds to `<hostname>.local`

**Check Format**:
```
✓ PASS: [Check name] - [Details]
✗ FAIL: [Check name] - [Error details]
```

**Failure Handling**:
- Critical failures (SSH, hostname) stop verification
- Non-critical failures (mDNS) are logged but don't fail deployment
- All failures included in summary report

## Contract Enforcement

### Build-Time Enforcement

NixOS evaluates all configuration at build time:

```bash
# Test configuration validity
nix build .#nixosConfigurations.test-server.config.system.build.toplevel

# Evaluation errors indicate contract violations
# Type errors, missing options, assertion failures all caught here
```

### Deployment-Time Enforcement

nixos-anywhere validates during deployment:

1. **Pre-flight checks**: SSH connectivity, target disk existence
2. **Partition validation**: Confirms disk device is correct
3. **Installation verification**: System builds and installs correctly
4. **Post-install checks**: System boots and is accessible

### Runtime Enforcement

Verification script validates post-deployment:

```bash
./scripts/verify-deployment.sh test-server <target-ip>
# Runs all checks from verification contract
# Returns non-zero exit code on any failure
```

## Usage Examples

### Minimal Deployment Configuration

```nix
# vms/test-server/configuration.nix
{ config, pkgs, ... }:
{
  networking.hostName = "test-server";

  keystone = {
    disko = {
      enable = true;
      device = "/dev/vda";
    };
    server.enable = true;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJlZ... developer@workstation"
  ];
}
```

### Extended Configuration

```nix
# Add custom options while maintaining contract
{ config, pkgs, ... }:
{
  networking.hostName = "production-server";

  keystone = {
    disko = {
      enable = true;
      device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB";
      swapSize = "128G";  # Override default
    };
    server.enable = true;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3... admin@workstation"
    "ssh-ed25519 AAAAC3... backup@backup-server"
  ];

  # Additional configuration beyond contract minimum
  time.timeZone = "America/New_York";
  environment.systemPackages = with pkgs; [ neovim ];
}
```

## Contract Evolution

### Versioning Strategy

- Contracts follow Keystone project versioning
- Breaking changes require major version bump
- New optional fields are minor version changes
- Documentation updates are patch changes

### Deprecation Process

1. Mark old option as deprecated with warning
2. Provide migration path in documentation
3. Maintain compatibility for one major version
4. Remove in next major version

### Extension Points

Contracts can be extended via:
- Additional module imports
- Extra configuration options
- Custom systemd services
- Override mechanisms

All extensions must maintain compatibility with core contract requirements.

## Summary

These contracts define the interface between:
- Developer and deployment system (configuration structure)
- Deployment tool and target system (installation protocol)
- Modules and NixOS (option types and behavior)
- Verification and running system (health checks)

By adhering to these contracts, deployments are reliable, reproducible, and verifiable.
