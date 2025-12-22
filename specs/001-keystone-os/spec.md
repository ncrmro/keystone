# Keystone OS Specification

## Overview

- **Goal**: Provide a reproducible, secure operating system distribution that can be deployed to any hardware with full disk encryption, automatic hardware-based unlock, and mesh network integration.
- **Scope**: First-class support for servers and workstations; deployment via bootable installer or remote installation to SSH-accessible systems.
- **Automation**: All features must be testable via `nix flake check` for CI/CD integration.

## Functional Requirements

### FR-001 Declarative Configuration

The system configuration MUST be fully declarative and reproducible.

- All system state defined in version-controllable expressions
- Same configuration produces identical systems across deployments
- Single output per target system configuration
- Configuration changes applied atomically with rollback capability

### FR-002 Full Disk Encryption

All user data MUST be encrypted at rest.

- Storage volumes encrypted before any user data is written
- Encryption keys never stored in plaintext on disk
- Key material protected by hardware security module when available
- Fallback authentication method when hardware security unavailable
- Swap space encrypted with ephemeral keys

### FR-003 Automatic Unlock

Systems MUST unlock automatically when boot integrity is verified.

- No manual password entry required under normal boot conditions
- Unlock bound to verified boot state measurements
- Automatic unlock fails safely if boot integrity is compromised
- Clear notification when manual unlock is required
- First-boot enrollment workflow for hardware security binding

### FR-004 Verified Boot Chain

The boot process MUST be cryptographically verified from firmware to userspace.

- Custom signing keys enrolled for platform ownership
- Boot artifacts signed and verified at each stage
- Tampering with boot components prevents automatic unlock
- Support for firmware in "setup mode" during initial deployment
- Transition from setup mode to user mode after key enrollment

### FR-005 Copy-on-Write Storage

The filesystem MUST support efficient snapshots and data integrity.

- Point-in-time snapshots without performance penalty
- Automatic data compression
- Data integrity verification (checksums)
- Remote replication capability for backups
- Per-dataset configuration (quotas, compression, snapshots)

---

## Block Storage Configuration

This section details the storage configuration options for the root operating system pool.

### Root OS Pool

The root pool contains the operating system, user home directories, and system data.

#### Filesystem Type

| Type | Use Case | Features |
|------|----------|----------|
| `zfs` | Default, recommended | Snapshots, compression, checksums, encryption, quotas |
| `ext4` | Simple/legacy | Minimal overhead, wide compatibility, no advanced features |

When `ext4` is selected:
- LUKS encryption is used directly on the partition
- No snapshots, compression, or per-user quotas available
- Suitable for resource-constrained systems or VMs

#### Disk Configuration

**Single Disk (default):**
```
devices = [ "/dev/disk/by-id/nvme-..." ];
```

**Multi-Disk with Redundancy Mode:**

| Mode | Min Disks | Description | Use Case |
|------|-----------|-------------|----------|
| `single` | 1 | No redundancy, single disk or concatenated | Dev/testing |
| `mirror` | 2 | All disks mirror each other (RAID1) | Small redundancy |
| `stripe` | 2 | Data striped across disks (RAID0) | Performance, no redundancy |
| `raidz1` | 3 | Single parity (RAID5 equivalent) | Balanced redundancy |
| `raidz2` | 4 | Double parity (RAID6 equivalent) | High redundancy |
| `raidz3` | 5 | Triple parity | Maximum redundancy |

```
devices = [
  "/dev/disk/by-id/nvme-disk1"
  "/dev/disk/by-id/nvme-disk2"
  "/dev/disk/by-id/nvme-disk3"
];
mode = "raidz1";
```

#### Partition Sizing

Configurable sizes for partitions and datasets:

| Partition/Dataset | Default | Description |
|-------------------|---------|-------------|
| `esp` | `1G` | EFI System Partition (boot) |
| `swap` | `8G` | Encrypted swap (random key per boot) |
| `credstore` | `100M` | LUKS volume for ZFS encryption keys |
| `root` | remaining | Root filesystem |

**ZFS Dataset Sizing (quotas):**

| Dataset | Default | Description |
|---------|---------|-------------|
| `/nix` | unlimited | Nix store (compression highly effective) |
| `/var` | unlimited | Variable data, logs |
| `/home/<user>` | configurable | Per-user home with quota |

#### Configuration Options

```nix
keystone.os.storage = {
  # Filesystem type
  type = "zfs";  # or "ext4"

  # Disk devices (by-id paths recommended)
  devices = [ "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB" ];

  # Redundancy mode (only for multi-disk ZFS)
  mode = "single";  # single, mirror, stripe, raidz1, raidz2, raidz3

  # Partition sizes
  esp.size = "1G";
  swap.size = "8G";        # Set to "0" to disable swap
  credstore.size = "100M"; # Only for ZFS

  # ZFS-specific options
  zfs = {
    compression = "zstd";     # off, lz4, zstd, gzip-N
    atime = "off";            # Access time updates
    arcMax = "4G";            # ARC cache limit
    autoSnapshot = true;      # Enable auto-snapshots
    autoScrub = true;         # Weekly integrity check
  };
};
```

### TODO: Additional Storage Pools (Future)

The following storage pool types are planned for future implementation:

#### Data Pool (NAS/Media)
- Separate pool for bulk data storage
- Optimized for large files (media, backups)
- Different redundancy than root pool
- Network sharing via NFS/SMB

```nix
# Future API concept
keystone.os.pools.data = {
  devices = [ "/dev/disk/by-id/sata-disk1" "/dev/disk/by-id/sata-disk2" ];
  mode = "mirror";
  mountpoint = "/data";
  shares = {
    media = { path = "/data/media"; nfs = true; smb = true; };
    backups = { path = "/data/backups"; nfs = true; };
  };
};
```

#### Backup Pool
- Dedicated pool for receiving ZFS snapshots
- Can be external/removable drives
- Rotation support for multiple backup drives

```nix
# Future API concept
keystone.os.pools.backup = {
  devices = [ "/dev/disk/by-id/usb-backup-drive" ];
  mode = "single";
  mountpoint = "/backup";
  receive = {
    from = [ "rpool" "data" ];  # Pools to receive snapshots from
    schedule = "daily";
  };
};
```

#### Cache/Fast Pool
- NVMe cache for spinning disk pools
- L2ARC read cache
- SLOG write cache

```nix
# Future API concept
keystone.os.pools.data.cache = {
  l2arc = "/dev/disk/by-id/nvme-cache";
  slog = "/dev/disk/by-id/nvme-slog";
};
```

---

### FR-006 Remote Installation

Systems MUST be deployable to any SSH-accessible target.

- Deploy over network to running system (kexec-based)
- Bootable installer media generation with SSH key injection
- Disk partitioning defined declaratively and applied automatically
- Support for injecting additional files during deployment
- Installation progress observable via SSH

### FR-007 Mesh Network Client

Systems MUST be able to join private mesh networks.

- Automatic connection to coordination server on first boot
- Node discovery without manual IP configuration
- Secure remote access without port forwarding or NAT traversal
- DNS-based node resolution within mesh
- Exit node capability for routing traffic through specific nodes

### FR-008 Mesh Network Server

Systems MUST be able to host mesh network coordination services.

- Self-hosted coordination server for mesh network
- Node authentication and authorization management
- Access control list (ACL) configuration
- DNS integration for automatic node name resolution
- Web-based administration interface

### FR-009 Server Role

The system MUST support always-on server configurations.

- Headless operation without display manager
- SSH access enabled by default
- Service discovery via multicast DNS (mDNS)
- Firewall with secure defaults
- Support for network gateway, DNS, and storage services

### FR-010 Workstation Role

The system MUST support interactive desktop workstation configurations.

- Graphical desktop environment with compositor
- Display manager with auto-login capability
- Audio system with application mixing
- Network management with graphical interface
- Bluetooth connectivity
- Terminal development environment (editor, shell, multiplexer)

### FR-011 Testing via Flake Checks

All system features MUST be testable via standard flake check mechanism.

- Tests runnable with `nix flake check`
- Virtual machine-based testing for system configurations
- Hardware security emulation for TPM-dependent features
- Secure Boot verification in emulated environment
- Headless execution for CI/CD pipelines

## Non-Functional Requirements

### NFR-001 Reproducibility

- Identical inputs produce identical outputs
- All dependencies pinned to specific versions
- No reliance on external state during build
- Offline builds possible with cached dependencies

### NFR-002 Security Posture

- Defense in depth with multiple security layers
- Minimal attack surface with only required services enabled
- Secure defaults requiring explicit opt-out
- No default passwords in production configurations
- Secrets never committed to version control

### NFR-003 Observability

- Installation progress visible with detailed logging
- Boot process debuggable via serial console
- System logs aggregated and queryable
- Health metrics exportable for monitoring
- Clear error messages with remediation guidance

## Testing Requirements

### TR-001 Fast Iteration Testing

Tests for rapid configuration development without full security stack.

**Flake check output**: `checks.x86_64-linux.vm-terminal`, `checks.x86_64-linux.vm-desktop`

- Quick virtual machine builds (< 2 minutes)
- No disk encryption or verified boot overhead
- SSH access for interactive debugging
- Persistent disk state between runs (optional)
- Both headless (terminal) and graphical (desktop) modes

### TR-002 Full Stack Testing

Tests for complete deployment including all security features.

**Flake check output**: `checks.x86_64-linux.integration-deployment`

- Hardware security module emulation
- Verified boot in emulated UEFI environment
- Full disk encryption with automatic unlock verification
- End-to-end deployment via remote installation
- Post-deployment security state validation

### TR-003 Module Testing

Tests for individual module functionality.

**Flake check output**: `checks.x86_64-linux.nixos-*`

- Service startup verification
- Configuration option validation
- Module interaction testing
- Regression testing for module changes

## Success Criteria

### SC-001 Deployment Success

- Fresh system deployable from ISO in under 30 minutes
- Remote deployment to SSH target in under 15 minutes
- First boot completes without manual intervention (after hardware enrollment)

### SC-002 Security Verification

- Disk contents unreadable without proper authentication
- Boot tampering detected and automatic unlock prevented
- Hardware security enrollment completes in under 5 minutes

### SC-003 Network Integration

- Mesh network connection established within 60 seconds of boot
- Node discoverable by hostname within mesh network
- Remote access functional without port forwarding

### SC-004 Test Coverage

- All functional requirements have corresponding flake checks
- Tests complete in under 30 minutes total
- Test failures produce actionable diagnostics

## Out of Scope

The following features are explicitly out of scope for this specification and planned for future versions:

- **Automated backups**: ZFS snapshot scheduling and remote replication automation
- **Monitoring stack**: Prometheus, Grafana, alerting infrastructure
- **Multi-host deployment**: Orchestrated deployment across multiple systems
- **Container orchestration**: Kubernetes/k3s integration
- **Distributed storage**: Ceph, GlusterFS, or similar
- **Enterprise features**: LDAP/AD integration, compliance automation, audit logging
- **Laptop-specific features**: Suspend/hibernate, battery management, lid switch handling
- **Multi-GPU configurations**: Complex graphics setups, GPU passthrough

---

## Apple Silicon Mac Support (`operating-system-mac`)

This section specifies support for running Keystone on Apple Silicon Macs (M1/M2/M3) via the [nixos-apple-silicon](https://github.com/nix-community/nixos-apple-silicon) project.

### Overview

Apple Silicon Macs use a fundamentally different security architecture than x86 systems. The Secure Enclave is not accessible from Linux, so TPM-based automatic disk unlock is not possible. A separate module output (`operating-system-mac`) provides Mac-specific configuration while sharing common infrastructure with the x86 module.

### Platform Differences

| Aspect | x86 (`operating-system`) | Apple Silicon (`operating-system-mac`) |
|--------|--------------------------|----------------------------------------|
| Boot Security | TPM2 + Secure Boot (Lanzaboote) | Apple iBoot chain (not controllable) |
| Key Storage | TPM2 PCR binding | Not available from Linux |
| Disk Unlock | Automatic via TPM | Manual password required |
| Boot Loader | systemd-boot + Lanzaboote | systemd-boot only |
| EFI Variables | Modifiable | Read-only (`canTouchEfiVariables = false`) |
| Storage | ZFS or ext4 | ext4 initially (ZFS untested) |

### FR-012 Apple Silicon Hardware Support

Systems MUST support Apple Silicon Mac hardware via Asahi Linux.

- Import `nixos-apple-silicon` for kernel and driver support
- Configure firmware extraction from EFI partition
- Set `boot.loader.efi.canTouchEfiVariables = false`
- Support M1, M2, M3 chip families

### FR-013 Mac Storage Configuration

Apple Silicon systems MUST support encrypted storage with manual unlock.

- LUKS2 encryption with Argon2id key derivation
- Manual password entry at boot (no TPM auto-unlock)
- ext4 filesystem initially (ZFS deferred pending testing)
- Same partition layout options as x86 (ESP, swap, root)

### FR-014 Shared Module Infrastructure

Common functionality MUST be shared between x86 and Mac modules.

- User management (`keystone.os.users`) shared
- Service configuration (`keystone.os.services`) shared
- Nix settings (`keystone.os.nix`) shared
- Platform-specific options only exist in respective modules

### Mac-Specific Limitations

The following x86 features are NOT available on Apple Silicon:

| Feature | Reason |
|---------|--------|
| `keystone.os.tpm` | No TPM hardware; Secure Enclave inaccessible from Linux |
| `keystone.os.secureBoot` | Apple uses different boot verification; Lanzaboote incompatible |
| ZFS storage | Untested on Asahi kernel; deferred to future work |
| Automatic disk unlock | No hardware key storage available |

### Mac User Stories

#### US-MAC-1: Module Base Refactor (Priority: P0)

As a developer, I want the common OS module code extracted into a shared base so that both x86 and Mac modules can reuse it without duplication.

**Acceptance Criteria**:
1. Existing `operating-system` module works unchanged after refactor
2. `nix flake check` passes with no errors

#### US-MAC-2: Mac Module Creation (Priority: P1)

As a user with an Apple Silicon Mac, I want to install NixOS using Keystone modules so that I can have a consistent Keystone experience on my Mac hardware.

**Acceptance Criteria**:
1. `keystone.nixosModules.operating-system-mac` produces valid aarch64-linux system
2. `keystone.os.tpm` and `keystone.os.secureBoot` options do NOT exist in Mac module
3. System boots successfully on Apple Silicon hardware

#### US-MAC-3: LUKS Encryption (Priority: P2)

As a user, I want my Mac's disk to be encrypted with LUKS so that my data is protected at rest.

**Acceptance Criteria**:
1. LUKS encryption prompts for password at boot
2. Root filesystem unlocks and mounts after correct password

#### US-MAC-4: User Environment (Priority: P3)

As a user, I want my terminal and desktop environment to work on my Mac.

**Acceptance Criteria**:
1. Terminal environment (Zsh, Helix, Zellij) available when `terminal.enable = true`
2. Hyprland launches when `desktop.enable = true` (GPU maturity caveats apply)

### Mac Success Criteria

- **SC-MAC-1**: `nix flake check` passes for both x86_64-linux and aarch64-linux
- **SC-MAC-2**: Test configuration using `operating-system-mac` builds successfully
- **SC-MAC-3**: x86 `operating-system` module continues to pass all existing tests
- **SC-MAC-4**: User can deploy to Apple Silicon hardware using nixos-anywhere

### Mac Out of Scope

- ZFS storage on Apple Silicon (deferred pending kernel testing)
- TPM-equivalent security via Secure Enclave (not accessible from Linux)
- Intel Mac support (use standard x86 `operating-system` module)
- Automated installer ISO for Mac (complex Asahi boot chain)
- GPU-accelerated Hyprland testing (depends on Asahi driver maturity)
