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
| Battery Monitoring | UPower | Standard Linux battery API, D-Bus integration |
| Brightness Control | brightnessctl | Backlight control, already in Hyprland bindings |
| Fingerprint Auth | fprintd | Standard Linux fingerprint stack (currently broken) |

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

## Laptop Features (FR-011)

This section covers laptop-specific functionality added to the desktop module.

### Technology Stack

| Feature | Technology | Rationale |
|---------|------------|-----------|
| Battery Monitoring | UPower | Standard Linux battery API, D-Bus integration |
| Notifications | mako + notify-send | Already in desktop stack, libnotify compatible |
| Brightness Control | brightnessctl | Already configured in Hyprland bindings |
| WiFi Management | NetworkManager | Already enabled in desktop module |
| Fingerprint | fprintd + PAM | Standard Linux fingerprint stack |

### Battery Alert Notifications (FR-011.1)

**Architecture:**
```
UPower D-Bus → battery-notify service → notify-send → mako
                      │
                      └─ Thresholds: 20% (warning), 10% (critical), 5% (urgent)
```

**Implementation:**
1. Enable UPower service in `modules/desktop/nixos.nix`:
   ```nix
   services.upower.enable = mkDefault true;
   ```

2. Create systemd user service `battery-notify.service`:
   - Monitor `org.freedesktop.UPower` D-Bus signals
   - Send notifications via `notify-send` with escalating urgency
   - Use hysteresis (2% buffer) to prevent notification spam

3. Add to home-manager autostart in `modules/desktop/home/hyprland/autostart.nix`

**Notification Levels:**
| Threshold | Urgency | Sound | Persistent |
|-----------|---------|-------|------------|
| 20% | Normal | No | No |
| 10% | Critical | Yes | No |
| 5% | Critical | Yes | Yes (requires dismiss) |

### WiFi & Captive Portal Handling (FR-011.2, FR-011.3)

**Current State:**
- NetworkManager enabled in `modules/desktop/nixos.nix`
- Waybar network widget with `on-click = "nm-connection-editor"`
- Tailscale DNS configured via `systemd-resolved`

**Problem:**
Tailscale's MagicDNS intercepts all DNS queries, preventing captive portal redirects from working. Coffee shop/hotel WiFi shows "no internet" because the portal page never loads.

**Solutions:**

1. **neverssl.com Workaround** (Documentation only):
   - Navigate to `http://neverssl.com` to trigger captive portal redirect
   - Works because the site is HTTP-only (no HTTPS upgrade)

2. **Tailscale Toggle Script** (`keystone-tailscale`):
   ```bash
   #!/usr/bin/env bash
   case "$1" in
     down) tailscale down && notify-send "Tailscale" "Disconnected" ;;
     up)   tailscale up && notify-send "Tailscale" "Connected" ;;
     *)    tailscale status ;;
   esac
   ```

3. **Documentation** (`docs/laptop-wifi.md`):
   - Step-by-step captive portal workflow
   - Troubleshooting common issues

### Brightness Control (FR-011.4)

**Current State (Already Implemented):**
```nix
# modules/desktop/home/hyprland/bindings.nix
bindel = [
  ",XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+"
  ",XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-"
];
```

**Additions Needed:**
1. Keyboard backlight support:
   ```nix
   ",XF86KbdBrightnessUp, exec, brightnessctl -d *::kbd_backlight set 10%+"
   ",XF86KbdBrightnessDown, exec, brightnessctl -d *::kbd_backlight set 10%-"
   ```

2. Verify `brightnessctl` is in system packages (it's likely pulled in already)

3. SwayOSD integration (already configured) provides visual feedback

### Fingerprint Scanner (FR-011.5) - Status: Broken

**Current State:** Not enabled, needs investigation

**Planned Implementation:**
```nix
# modules/desktop/nixos.nix
services.fprintd.enable = mkDefault true;

# PAM integration
security.pam.services = {
  login.fprintAuth = true;
  sudo.fprintAuth = true;
  hyprlock.fprintAuth = true;
};
```

**Investigation Needed:**
1. Check hardware compatibility (laptop model)
2. Test fprintd enrollment: `fprintd-enroll`
3. Debug PAM configuration order (fingerprint vs password)
4. Verify hyprlock PAM service exists

**Documentation:** `docs/fingerprint.md` (troubleshooting guide)

### File Changes Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `modules/desktop/nixos.nix` | Modify | Add UPower, fprintd services |
| `modules/desktop/home/components/battery-notify.nix` | New | Battery notification service |
| `modules/desktop/home/hyprland/bindings.nix` | Modify | Add keyboard backlight keys |
| `modules/desktop/home/scripts/keystone-tailscale.sh` | New | Tailscale toggle script |
| `docs/laptop-wifi.md` | New | Captive portal documentation |
| `docs/fingerprint.md` | New | Fingerprint setup/troubleshooting |

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
| **Battery Notifications** | **Not Started** | FR-011.1 |
| **Captive Portal Docs** | **Not Started** | FR-011.2, FR-011.3 |
| **Keyboard Backlight** | **Not Started** | FR-011.4 |
| **Fingerprint Auth** | **Broken** | FR-011.5, needs investigation |

---

## References

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Disko Documentation](https://github.com/nix-community/disko)
- [Lanzaboote Documentation](https://github.com/nix-community/lanzaboote)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Headscale Documentation](https://headscale.net/)
- [systemd-cryptenroll](https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html)
