# Keystone OS Implementation Plan

This document describes the technology choices and architecture for implementing the Keystone OS specification.

## Technology Stack Overview

| Requirement | Technology | Rationale |
|------------|------------|-----------|
| Base OS | NixOS | Declarative, reproducible, atomic upgrades |
| Package Management | Nix Flakes | Hermetic builds, lockfile support |
| Disk Partitioning | Disko | Declarative disk layout, nixos-anywhere integration |
| Filesystem | ZFS | Snapshots, compression, native encryption |
| Boot Volume Encryption | LUKS | TPM2 integration via systemd-cryptenroll |
| Verified Boot | Lanzaboote | Secure Boot with signed UKI |
| Hardware Security | TPM2 | Key protection, boot measurement |
| Remote Installation | nixos-anywhere | SSH-based deployment with kexec |
| Mesh Networking | Tailscale/Headscale | WireGuard-based, NAT traversal |
| Desktop Environment | Hyprland | Modern Wayland compositor |
| Testing Framework | NixOS VM Tests | Built-in, flake-integrated testing |

---

## Disk & Encryption Architecture

### Disko for Declarative Partitioning

Disko provides declarative disk layout as Nix expressions, ensuring reproducible partitioning across deployments.

**Partition Layout:**
```
Physical Disk
├── ESP (1GB, EFI System Partition)
│   └── FAT32 → /boot
├── ZFS Partition (remaining space)
│   └── rpool (ZFS pool)
│       ├── credstore (100MB zvol)
│       │   └── LUKS encrypted → /etc/credstore
│       └── crypt/ (ZFS native encryption)
│           ├── system/root → /
│           ├── system/nix → /nix
│           └── system/var → /var
└── Swap Partition (configurable)
    └── Random encryption per boot
```

### Credstore Pattern

The credstore pattern separates key management from filesystem encryption:

1. **LUKS Volume**: Small zvol encrypted with TPM2 or password
2. **ZFS Key Storage**: ZFS encryption key stored inside credstore
3. **Layered Unlock**: LUKS unlocks first, then provides key for ZFS

**Why this pattern?**
- TPM2 integration via systemd-cryptenroll (LUKS-native)
- ZFS encryption key can be any file (more flexible)
- Recovery key unlocks LUKS, which unlocks everything

### Boot Flow

```
Firmware → Lanzaboote → systemd-boot → initrd
                                          │
                                          ├─ import-rpool-bare (import ZFS pool)
                                          │
                                          ├─ cryptsetup@credstore (TPM2/password unlock)
                                          │
                                          ├─ mount credstore (ext4 to /etc/credstore)
                                          │
                                          ├─ rpool-load-key (load ZFS key from credstore)
                                          │
                                          └─ sysroot.mount (mount encrypted ZFS)
```

---

## Verified Boot Architecture

### Lanzaboote for Secure Boot

Lanzaboote generates signed Unified Kernel Images (UKI) compatible with UEFI Secure Boot.

**Components:**
- **Stub**: Signed EFI stub that loads kernel + initrd
- **Kernel**: Linux kernel embedded in UKI
- **Initrd**: Initial ramdisk with systemd
- **Cmdline**: Kernel parameters embedded and signed

**Key Enrollment:**
```
Setup Mode (factory state)
    │
    ├─ Generate Platform Key (PK)
    ├─ Generate Key Exchange Key (KEK)
    ├─ Generate Signature Database Key (db)
    │
    └─ Enroll keys via sbctl
         │
         └─ User Mode (secured state)
```

### Why Lanzaboote over GRUB?

- Native UKI support (kernel + initrd in single signed file)
- Simpler key management with sbctl integration
- Better systemd-boot integration
- Smaller attack surface

---

## Hardware Security (TPM2)

### PCR Binding Strategy

Platform Configuration Registers (PCRs) measure boot state. Keystone binds to:

| PCR | Measures | Purpose |
|-----|----------|---------|
| 1 | Firmware configuration | Detect BIOS/UEFI changes |
| 7 | Secure Boot state | Detect key enrollment changes |

**Why PCRs 1 and 7?**
- PCR 0 (firmware code) changes too frequently with updates
- PCR 4 (boot manager) changes with every kernel update
- PCRs 1+7 balance security with update resilience

### systemd-cryptenroll Integration

```bash
# Enroll TPM2 key for credstore volume
systemd-cryptenroll /dev/zvol/rpool/credstore \
    --tpm2-device=auto \
    --tpm2-pcrs=1+7

# Enroll recovery key
systemd-cryptenroll /dev/zvol/rpool/credstore \
    --recovery-key
```

### Enrollment Workflow

1. **First Boot**: System prompts for TPM enrollment
2. **Recovery Key**: User saves generated recovery key
3. **TPM Bind**: Key bound to current PCR values
4. **Remove Default**: Default "keystone" password removed
5. **Subsequent Boots**: Automatic unlock via TPM

---

## Remote Installation (nixos-anywhere)

### Deployment Workflow

```
Local Machine                    Target Machine
     │                                 │
     ├─ Build configuration ──────────►│
     │                                 │
     ├─ SSH connect ──────────────────►│ (running any Linux)
     │                                 │
     ├─ Upload kexec image ───────────►│
     │                                 │
     │                         kexec into NixOS installer
     │                                 │
     ├─ Run disko partitioning ───────►│
     │                                 │
     ├─ Install NixOS ────────────────►│
     │                                 │
     ├─ Inject extra files ───────────►│
     │                                 │
     └─ Reboot into installed system ─►│
```

### Extra Files Pattern

Pre-generated files injected during installation:
- `/etc/ssh/ssh_host_*`: SSH host keys (for initrd unlock)
- `/etc/credstore/zfs.key`: Pre-generated ZFS encryption key
- `/var/lib/tailscale/`: Pre-authenticated Tailscale state

---

## Mesh Networking (Headscale/Tailscale)

### Tailscale Client

Nodes join mesh network via Tailscale daemon:

```nix
services.tailscale = {
  enable = true;
  useRoutingFeatures = "client"; # or "server" for exit node
};
```

**Features:**
- MagicDNS: `hostname.tailnet-name.ts.net`
- NAT traversal via DERP relays
- Direct connections when possible (hole punching)

### Headscale Server

Self-hosted coordination server:

```nix
services.headscale = {
  enable = true;
  address = "0.0.0.0";
  port = 8080;
  settings = {
    server_url = "https://headscale.example.com";
    dns_config = {
      magic_dns = true;
      base_domain = "internal";
    };
  };
};
```

**Features:**
- Full control over coordination infrastructure
- Custom ACLs for access control
- No dependency on Tailscale SaaS

---

## Testing Infrastructure

### Current State (bin/ scripts)

Existing testing via Python scripts:
- `bin/build-vm`: Fast QEMU VMs, no encryption
- `bin/virtual-machine`: libvirt VMs with TPM emulation
- `bin/test-deployment`: End-to-end integration testing
- `bin/test-installer`: NixOS VM tests for installer

### Target State (Flake Checks)

Migrate to proper `nix flake check` outputs:

```nix
# flake.nix
{
  checks.x86_64-linux = {
    # Fast iteration VMs
    vm-terminal = nixosTest { /* ... */ };
    vm-desktop = nixosTest { /* ... */ };

    # Full stack integration
    integration-deployment = nixosTest {
      nodes.installer = { /* ISO config */ };
      nodes.target = {
        virtualisation.tpm.enable = true;
        # ...
      };
      testScript = ''
        # Deploy and verify
      '';
    };

    # Module tests
    nixos-disko = nixosTest { /* ... */ };
    nixos-secure-boot = nixosTest { /* ... */ };
    nixos-tpm-enrollment = nixosTest { /* ... */ };
  };
}
```

### TPM Emulation

NixOS VM tests support software TPM via swtpm:

```nix
nodes.machine = {
  virtualisation.tpm.enable = true;
};
```

### Migration Path

1. **Phase 1**: Add basic `checks` output alongside existing scripts
2. **Phase 2**: Port `bin/test-deployment` logic to NixOS test
3. **Phase 3**: Deprecate Python scripts, use flake checks exclusively
4. **Phase 4**: Remove `bin/` testing scripts

---

## Module Structure

### Current Exports

```nix
nixosModules = {
  server              # Base server configuration
  client              # Workstation with desktop
  diskoSingleDiskRoot # ZFS + LUKS + credstore
  secureBoot          # Lanzaboote configuration
  tpmEnrollment       # TPM binding and enrollment
  users               # User management
  ssh                 # SSH configuration
  isoInstaller        # Bootable installer
};

homeModules = {
  terminal            # Terminal dev environment
  desktop             # Hyprland desktop
};
```

### Recommended Composition

**Server Deployment:**
```nix
imports = [
  keystone.nixosModules.diskoSingleDiskRoot
  keystone.nixosModules.secureBoot
  keystone.nixosModules.tpmEnrollment
  keystone.nixosModules.server
];
```

**Workstation Deployment:**
```nix
imports = [
  keystone.nixosModules.diskoSingleDiskRoot
  keystone.nixosModules.secureBoot
  keystone.nixosModules.tpmEnrollment
  keystone.nixosModules.client
];

# Home Manager
home-manager.users.user = {
  imports = [ keystone.homeModules.desktop ];
};
```

---

## Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| Disko disk layout | Complete | `modules/disko-single-disk-root/` |
| ZFS encryption | Complete | Credstore pattern implemented |
| LUKS/TPM integration | Complete | systemd-cryptenroll in initrd |
| Lanzaboote | Complete | `modules/secure-boot/` |
| TPM enrollment | Complete | `modules/tpm-enrollment/` |
| Server module | Complete | `modules/server/` |
| Client module | Complete | `modules/client/` |
| Hyprland desktop | Complete | `modules/keystone/desktop/` |
| Terminal environment | Complete | `modules/keystone/terminal/` |
| nixos-anywhere support | Complete | Tested in `bin/test-deployment` |
| ISO installer | Complete | `modules/iso-installer.nix` |
| Tailscale client | Complete | Via upstream NixOS module |
| Headscale server | Partial | Needs module refinement |
| Flake checks | Not Started | Currently in `bin/` scripts |

---

## References

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Disko Documentation](https://github.com/nix-community/disko)
- [Lanzaboote Documentation](https://github.com/nix-community/lanzaboote)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Headscale Documentation](https://headscale.net/)
- [systemd-cryptenroll](https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html)
