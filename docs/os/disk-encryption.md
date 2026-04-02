---
title: Disk Encryption
description: Unified disk encryption model — unlock methods, boot chain, fallback, and recovery
---

# Disk Encryption

This document is the single source of truth for Keystone's block-storage encryption model. It covers:

- How encrypted storage is laid out
- Which unlock methods are supported
- How the boot-time unlock chain works
- Fallback and recovery behavior
- Recommended configurations for laptops and workstations

> **Scope**: This document covers **boot-time block-storage unlock** only.
> User-session secret decryption (agenix, age-plugin-yubikey, GPG) is a
> separate concern — see [Hardware Keys](hardware-keys.md) for that topic.

---

## Architecture Overview

Keystone encrypts all user data at rest. The exact layout depends on the
storage backend, but both share a common principle: a LUKS-encrypted
volume protects the root filesystem (or the key that unlocks it).

### ZFS (default)

```
┌─────────────────────────────────────────────────────────────────────┐
│  ESP (/boot)  │  ZFS pool "rpool"                                  │
│  (unencrypted │  ┌──────────────────────────────────────────────┐   │
│   FAT32)      │  │  credstore (ZFS zvol → LUKS → ext4)         │   │
│               │  │    stores: /etc/credstore/zfs-sysroot.mount  │   │
│               │  ├──────────────────────────────────────────────┤   │
│               │  │  rpool/crypt  (encrypted ZFS dataset)        │   │
│               │  │    encryptionroot = rpool/crypt              │   │
│               │  │    keylocation = file:///etc/credstore/...   │   │
│               │  │    ├── crypt/system      → /                 │   │
│               │  │    ├── crypt/system/nix  → /nix              │   │
│               │  │    ├── crypt/system/var  → /var              │   │
│               │  │    └── crypt/home/<user> → /home/<user>      │   │
│               │  └──────────────────────────────────────────────┘   │
│               │                                                     │
│  Swap (random │                                                     │
│   encryption) │                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

The **credstore** is a small (100 MB default) ZFS zvol formatted as LUKS2
+ ext4. It holds a single file — the random 256-bit key that ZFS uses to
decrypt `rpool/crypt`. All unlock methods (TPM2, FIDO2, password, recovery
key) are enrolled as LUKS keyslots on this credstore device.

### ext4

```
┌──────────────────────────────────────┐
│  ESP (/boot)  │  LUKS "cryptroot"   │
│  (unencrypted │   → ext4  → /       │
│   FAT32)      │                      │
│               │  LUKS "cryptswap"   │
│               │   (hibernation only) │
└──────────────────────────────────────┘
```

For ext4, the LUKS volume wraps the root partition directly. Unlock
methods are enrolled on `/dev/disk/by-partlabel/disk-root-root`.

---

## Boot-Time Unlock Chain

### ZFS boot sequence

1. **systemd-boot** / lanzaboote loads the kernel and initrd.
2. **import-rpool-bare** imports the ZFS pool without mounting.
3. **systemd-cryptsetup@credstore** attempts to unlock the credstore LUKS
   volume. It tries, in order:
   - TPM2 automatic unseal (if a `systemd-tpm2` token exists)
   - FIDO2 hardware key (if a `systemd-fido2` token exists)
   - Interactive password prompt (if the above fail or are absent)
4. **etc-credstore.mount** mounts the unlocked credstore at `/etc/credstore`.
5. **rpool-load-key** reads the ZFS encryption key from the credstore and
   runs `zfs load-key rpool/crypt`.
6. **sysroot.mount** mounts `/` and the remaining datasets.
7. Credstore is unmounted and LUKS closed before switching root.

### ext4 boot sequence

1. **systemd-boot** / lanzaboote loads the kernel and initrd.
2. **systemd-cryptsetup@cryptroot** attempts to unlock the LUKS root in the
   same TPM2 → FIDO2 → password order.
3. Root is mounted directly.

### What happens when TPM2 unlock fails

When the TPM2 unseal fails (firmware update, Secure Boot key rotation,
BIOS change, or any PCR drift), systemd falls back to the next available
method:

1. If FIDO2 is enrolled, the user is prompted to touch the hardware key.
2. If neither TPM2 nor FIDO2 succeeds, the system prompts for a password
   or recovery key on the boot console.
3. If no valid credential is entered within the configured timeout
   (`diskEncryption.fallback.passwordPromptTimeout`, default 90 s), the
   system drops to the systemd emergency console.

> **Key guarantee**: As long as a password or recovery key keyslot
> remains enrolled, the system is always recoverable from the boot
> console — regardless of TPM or FIDO2 state.

---

## Unlock Methods

### TPM2

| Aspect        | Detail                                              |
| ------------- | --------------------------------------------------- |
| Enrolled via  | `sudo keystone-enroll-tpm` or during initial setup  |
| LUKS token    | `systemd-tpm2`                                      |
| PCR binding   | Default PCR 1 (firmware) + PCR 7 (Secure Boot)      |
| UX            | Fully automatic — no interaction needed at boot      |
| Failure mode  | Falls back to FIDO2 → password → recovery key       |
| Requirement   | Secure Boot must be enabled                          |

TPM2 unlock seals the LUKS key against the measured boot state. If the
boot chain changes (firmware update, Secure Boot re-enrollment, kernel
change without matching PCR), the sealed key cannot be recovered and the
system falls back to interactive methods.

**Re-enrollment after PCR drift**:

```bash
# Boot using password / recovery key, then:
sudo keystone-enroll-tpm        # re-seal against current PCR values
```

### FIDO2

| Aspect        | Detail                                              |
| ------------- | --------------------------------------------------- |
| Enrolled via  | `sudo keystone-enroll-fido2`                         |
| LUKS token    | `systemd-fido2`                                      |
| UX            | Touch hardware key + optional PIN at boot            |
| Failure mode  | Falls back to password → recovery key                |
| Requirement   | `keystone.hardwareKey.enable = true`                 |

FIDO2 uses a hardware security key (e.g. YubiKey) as a LUKS unlock
credential. Unlike TPM2, FIDO2 is not tied to the boot measurement — it
works regardless of firmware or kernel changes.

> **FIDO2 vs. agenix hardware-key usage**: FIDO2 enrollment here is for
> **boot-time LUKS unlock only**. The hardware key's PIV applet and
> `age-plugin-yubikey` identity are used separately for **user-session
> secret decryption** (agenix). These are independent enrollment steps
> on different layers — see [Hardware Keys](hardware-keys.md).

### Password

| Aspect        | Detail                                              |
| ------------- | --------------------------------------------------- |
| Enrolled via  | `sudo keystone-enroll-password`                      |
| LUKS token    | Standard LUKS passphrase keyslot                     |
| UX            | Type password at boot console                        |
| Requirements  | Minimum 12 characters                                |

Password is the simplest fallback. It requires physical or remote console
access. Keystone recommends always keeping a password or recovery key
enrolled so the system is recoverable without hardware tokens.

### Recovery Key

| Aspect        | Detail                                              |
| ------------- | --------------------------------------------------- |
| Enrolled via  | `sudo keystone-enroll-recovery`                      |
| LUKS token    | `systemd-recovery` keyslot                           |
| UX            | Enter long key at boot console                       |
| Storage       | Offline only — password manager + printed copy       |

Recovery keys are 256-bit cryptographic keys formatted as dash-separated
groups (e.g. `fda7-w4n8-...`). They should be stored offline and never
on the encrypted disk itself.

---

## Recommended Configurations

### Workstation (TPM2 + password fallback)

The default Keystone configuration. Automatic unlock on every boot; type
password only when the TPM state drifts.

```nix
keystone.os = {
  secureBoot.enable = true;    # required for TPM2
  tpm.enable = true;
  diskEncryption.unlockMethods = {
    tpm2.enable = true;        # automatic boot unlock
    password.enable = true;    # fallback when TPM fails
  };
};
```

After installation:

```bash
sudo keystone-enroll-recovery   # or keystone-enroll-password
# Recovery/password is enrolled, TPM is enrolled, default password removed.
```

### Laptop (FIDO2 + password fallback)

For users who prefer a hardware key over TPM, or who travel with the
machine and want physical-presence assurance at every boot.

```nix
keystone.os = {
  secureBoot.enable = true;
  tpm.enable = false;           # skip TPM — use FIDO2 instead
  diskEncryption.unlockMethods = {
    tpm2.enable = false;
    fido2.enable = true;        # touch YubiKey at every boot
    password.enable = true;     # fallback if key is lost
  };
};
keystone.hardwareKey.enable = true;
```

After installation:

```bash
sudo keystone-enroll-password   # set a strong password first
sudo keystone-enroll-fido2      # enroll the hardware key
```

### High-security laptop (TPM2 + FIDO2 + recovery key)

Belt-and-suspenders: automatic unlock in steady state, hardware key if
TPM fails, recovery key as last resort.

```nix
keystone.os = {
  secureBoot.enable = true;
  tpm.enable = true;
  diskEncryption.unlockMethods = {
    tpm2.enable = true;
    fido2.enable = true;
    password.enable = true;     # recommended even with recovery key
    recoveryKey.enable = true;
  };
};
keystone.hardwareKey.enable = true;
```

After installation:

```bash
sudo keystone-enroll-recovery   # generate and save recovery key
sudo keystone-enroll-fido2      # enroll hardware key
# TPM is enrolled automatically during keystone-enroll-recovery
```

### Configuration matrix

| Config                          | Boot UX                   | Fallback                    | Best for              |
| ------------------------------- | ------------------------- | --------------------------- | --------------------- |
| TPM2 + password                 | Automatic                 | Password on PCR drift       | Desktop / workstation |
| FIDO2 + password                | Touch key each boot       | Password if key unavailable | Travel laptop         |
| TPM2 + FIDO2 + recovery key    | Automatic                 | Key touch → recovery key    | High-security laptop  |
| Password only                   | Type password every boot  | None beyond the password    | Testing / VMs         |

---

## Verifying Enrollment Status

### Check which LUKS keyslots are enrolled

```bash
# Quick summary
sudo systemd-cryptenroll /dev/zvol/rpool/credstore
# Example output:
# SLOT TYPE
#    0 password
#    1 recovery
#    2 tpm2
#    3 fido2

# Detailed LUKS header
sudo cryptsetup luksDump /dev/zvol/rpool/credstore
```

### Check status via Keystone tooling

```bash
# Refresh and display disk unlock status
sudo keystone-refresh-disk-unlock-status
cat /var/lib/keystone/disk-unlock-status.json
# {
#   "checked_at": "2025-01-15T10:30:00+00:00",
#   "device": "/dev/zvol/rpool/credstore",
#   "tpm_enrolled": true,
#   "fido2_enrolled": false
# }
```

### Verify Secure Boot (required for TPM2)

```bash
sudo bootctl status | grep "Secure Boot"
# Secure Boot: enabled (user)
```

---

## Recovery Procedures

### TPM2 unlock stopped working after an update

This happens when a firmware update, Secure Boot key rotation, or kernel
change shifts the PCR values away from the sealed policy.

1. **At the boot console**, enter your password or recovery key when
   prompted.
2. After booting, re-enroll TPM:
   ```bash
   sudo keystone-enroll-tpm
   ```
3. Reboot to verify automatic unlock is restored.

### Lost or broken hardware key (FIDO2)

1. Boot using password or recovery key.
2. Wipe the old FIDO2 slot:
   ```bash
   sudo systemd-cryptenroll --wipe-slot=fido2 /dev/zvol/rpool/credstore
   ```
3. Enroll the replacement key:
   ```bash
   sudo keystone-enroll-fido2
   ```

### Forgot password, have recovery key

1. Enter the recovery key at the boot console.
2. Enroll a new password:
   ```bash
   sudo systemd-cryptenroll --password /dev/zvol/rpool/credstore
   ```

### Changing unlock methods safely

When adding or removing enrollment, follow this order to avoid lockout:

1. **Always add the new method first** before removing the old one.
2. **Verify** the new method works (reboot and test).
3. **Only then** wipe the old slot if desired.

```bash
# Example: switch from password to FIDO2
sudo keystone-enroll-fido2                    # add FIDO2
sudo reboot                                    # verify FIDO2 works
sudo systemd-cryptenroll --wipe-slot=0 /dev/zvol/rpool/credstore  # remove old password
sudo systemd-cryptenroll --password /dev/zvol/rpool/credstore      # set a new fallback password
```

> **Safety rule**: Never remove all human-usable keyslots (password and
> recovery key) unless you are certain the remaining hardware-backed
> methods are working and you accept the risk.

---

## Module Options Reference

```nix
keystone.os.diskEncryption = {
  unlockMethods = {
    tpm2.enable     = true;    # default: true (matches keystone.os.tpm.enable)
    fido2.enable    = false;   # default
    password.enable = true;    # default — recommended fallback
    recoveryKey.enable = false;# default
  };

  fallback.passwordPromptTimeout = 90;  # seconds

  device = "/dev/zvol/rpool/credstore"; # default; set to
  # "/dev/disk/by-partlabel/disk-root-root" for ext4
};
```

See `keystone.os.tpm.pcrs` for TPM PCR binding configuration.

---

## Concepts: Boot Unlock vs. Session Secrets

Keystone uses encryption at two distinct layers. This document covers
only the first:

| Layer                    | What it protects              | When it runs      | Mechanisms                       |
| ------------------------ | ----------------------------- | ----------------- | -------------------------------- |
| **Boot-time block unlock** | Entire disk / ZFS pool       | initrd (stage 1)  | TPM2, FIDO2, password, recovery  |
| **Session secret decrypt** | agenix secrets, SSH keys     | User login        | age-plugin-yubikey (PIV), GPG    |

The hardware key's **FIDO2 applet** is used for boot-time LUKS unlock.
The same key's **PIV applet** (via `age-plugin-yubikey`) is used for
session-time agenix decryption. These are independent enrollments — one
does not imply the other.

---

## Related Documentation

- [TPM Enrollment](tpm-enrollment.md) — step-by-step TPM enrollment commands
- [Hardware Keys](hardware-keys.md) — YubiKey setup, SSH, GPG, and agenix
- [Installation](installation.md) — initial system installation with disko
