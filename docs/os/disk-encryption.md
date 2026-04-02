---
title: Disk Encryption
description: Credstore boot chain, ZFS encryption, and recovery behavior
---

# Disk Encryption

**Version**: 1.0
**Module**: `keystone.os.storage`

## Overview

Keystone uses a two-layer encryption model for ZFS-based storage:

1. **Credstore** — a small LUKS2-encrypted volume (`/dev/zvol/rpool/credstore`)
   that stores the ZFS encryption key.
2. **ZFS native encryption** — the `rpool/crypt` dataset tree is encrypted with
   a raw key stored inside credstore.

TPM2 provides automatic unlock for the credstore during normal boots.
When TPM unlock fails (PCR mismatch, hardware change, etc.), the system
falls back to a password or recovery-key prompt on the active boot
console.

---

## Credstore Boot Chain

The initrd unlocks the system in the following order:

```
import-rpool-bare.service
  │  Imports ZFS pool without mounting datasets.
  │  Runs before cryptsetup-pre.target so the credstore
  │  zvol becomes available for LUKS unlock.
  ▼
systemd-cryptsetup@credstore.service
  │  Unlocks /dev/zvol/rpool/credstore via:
  │    1. TPM2 token (automatic, if PCRs match)
  │    2. Password/recovery-key prompt (after token-timeout=30s)
  │  Produces /dev/mapper/credstore.
  ▼
etc-credstore.mount
  │  Mounts /dev/mapper/credstore → /etc/credstore (ext4).
  ▼
rpool-load-key.service
  │  Loads ZFS encryption key from /etc/credstore/zfs-sysroot.mount
  │  into rpool/crypt via `zfs load-key`.
  ▼
sysroot.mount
  │  Mounts rpool/crypt/system → /sysroot.
  ▼
initrd-switch-root.target
    Transitions to the real root filesystem.
```

### Key dependencies

| Unit | Depends on | Failure effect |
|------|-----------|----------------|
| `import-rpool-bare` | ZFS module, disk devices | Pool not available → credstore zvol missing |
| `systemd-cryptsetup@credstore` | `import-rpool-bare` (via `cryptsetup-pre.target`) | Credstore locked → ZFS key unavailable |
| `etc-credstore.mount` | `systemd-cryptsetup@credstore` | Mount fails → rpool-load-key blocked |
| `rpool-load-key` | `etc-credstore.mount`, `import-rpool-bare` | ZFS key not loaded → root datasets cannot mount |
| `sysroot.mount` | `rpool-load-key` | Root not mounted → boot fails |

---

## Recovery Behavior

### Token timeout

Keystone sets `token-timeout=30s` in the credstore crypttab options.
This tells `systemd-cryptsetup` to abandon the TPM2 token after 30 seconds
and fall back to the systemd password-agent path.

Without an explicit timeout, the TPM2 token could retry indefinitely,
causing the boot to appear hung.

### Password-agent path

When TPM2 unlock fails and the token timeout expires, `systemd-cryptsetup`
activates the systemd password-agent framework.  The password prompt
appears on the console device configured by kernel parameters
(e.g. `console=ttyS0,115200n8 console=tty0`).

### Remote unlock (initrd SSH)

If `keystone.os.remoteUnlock.enable = true`, the initrd starts an SSH
server before disk unlock.  Connecting via SSH drops into
`systemd-tty-ask-password-agent`, which can supply the credential
remotely.  This is the supported secondary recovery surface for headless
servers.

### Emergency shell

`boot.initrd.systemd.emergencyAccess` controls whether an emergency
shell is available in the initrd.  Keystone defaults this to `false`
for production security.  Set it to `true` (or a password hash) in
test/development configurations to enable a recovery shell when the
unlock chain fails completely.

### Credential types

| Enrolled in LUKS | Prompt usable in initrd | Recovery possible |
|-----------------|------------------------|-------------------|
| Recovery key ✓ | Console visible ✓ | ✓ Enter key at prompt |
| Recovery key ✓ | Console not visible ✗ | ✓ Via initrd SSH (if enabled) |
| Recovery key ✓ | No console, no SSH ✗ | ✓ Offline recovery (boot from USB) |
| No credential ✗ | — | ✗ Data recovery requires LUKS header backup |

> **Key distinction**: A recovery credential enrolled in the LUKS header is
> necessary but not sufficient for interactive recovery.  The password prompt
> must also be visible and reachable on the active boot console.

---

## ext4 Storage Type

When `keystone.os.storage.type = "ext4"`, the encryption model is simpler:

- A single LUKS2 partition (`cryptroot`) protects the root filesystem.
- TPM2 provides automatic unlock with the same `token-timeout=30s` policy.
- No credstore or ZFS key indirection is involved.

The same recovery behavior applies: TPM failure leads to a password prompt
after the token timeout.

---

## Offline Recovery Procedure

If the machine cannot be unlocked interactively:

```bash
# 1. Boot from NixOS installer USB

# 2. Import the ZFS pool
zpool import -N -d /dev/disk/by-id rpool

# 3. Unlock credstore
cryptsetup open /dev/zvol/rpool/credstore credstore
# Enter recovery key or password when prompted

# 4. Mount credstore and load the ZFS key
mkdir -p /etc/credstore
mount /dev/mapper/credstore /etc/credstore
zfs load-key -L file:///etc/credstore/zfs-sysroot.mount rpool/crypt

# 5. Mount root datasets
mkdir -p /mnt
zfs mount -o mountpoint=/mnt rpool/crypt/system
zfs mount -o mountpoint=/mnt/nix rpool/crypt/system/nix
zfs mount -o mountpoint=/mnt/var rpool/crypt/system/var

# 6. Chroot and repair
nixos-enter --root /mnt
# Inside chroot: re-enroll TPM, fix boot config, etc.

# 7. Clean up
exit  # leave chroot
umount -R /mnt
umount /etc/credstore
cryptsetup close credstore
zpool export rpool
```

---

## Diagnostics

### Check credstore unlock status at boot

```bash
# Check if credstore unlocked successfully
journalctl -b -u systemd-cryptsetup@credstore.service

# Check for TPM-specific errors
journalctl -b | grep -i "tpm\|credstore\|token"

# Check rpool-load-key service
journalctl -b -u rpool-load-key.service
```

### Inspect LUKS header

```bash
# List keyslots and tokens
sudo cryptsetup luksDump /dev/zvol/rpool/credstore

# Verify TPM2 token is present
sudo cryptsetup luksDump /dev/zvol/rpool/credstore | grep systemd-tpm2
```

### Verify recovery credential works

```bash
# Test without rebooting (opens credstore with password, then closes)
sudo cryptsetup open --test-passphrase /dev/zvol/rpool/credstore
```

---

## Related Documentation

- [TPM Enrollment](tpm-enrollment.md) — enrollment commands and PCR configuration
- [Testing Procedure](testing-procedure.md) — VM-based deployment testing
- [Testing VM](testing-vm.md) — libvirt VM infrastructure

---

**Version**: 1.0
**Last Updated**: 2026-04-02
**Maintainer**: Keystone Project
