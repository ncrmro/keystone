---
title: Keystone hardware enrollment
description: Why and how to move a fresh Keystone install from the default disk password to layered hardware-backed unlock
---

# Keystone hardware enrollment

Read this once before Step 7 of
[`onboarding.md`](onboarding.md), then keep it open while you do the
post-install hardening on a new host.

## In one minute

- A fresh Keystone Linux install is intentionally bootstrappable, not final:
  the root LUKS volume still accepts the installer password `keystone`.
- Your first security task after install is to replace that default password
  and enroll the unlock methods you want to keep long-term.
- The recommended first-time command on a normal Keystone laptop or server is:

  ```bash
  ks hardware setup
  ```

- Preview the exact plan first with:

  ```bash
  ks hardware setup --dry-run
  ```

- Inspect the current state before and after with:

  ```bash
  sudo ks hardware report
  ```

## What Keystone is trying to achieve

After enrollment, a fully configured machine aims for this layered unlock
model:

| Method | What it is | Used when |
|---|---|---|
| FIDO2 | YubiKey or other hardware-key unlock | Preferred human fallback when the key is present |
| Recovery key | An 8-word paper key | High-entropy disaster recovery |
| Password | Your chosen LUKS passphrase | Manual fallback |
| TPM2 | Automatic unlock bound to Secure Boot + measured boot state | Normal day-to-day boot |
| Fingerprint | `fprintd` enrollment for login/sudo | Desktop convenience, not disk unlock |

The important model is: Keystone does not want a single magic unlock path.
It wants automatic boot when the machine is healthy, plus at least one human
recovery path when it is not.

Keystone prefers human disk-unlock fallbacks in this order:

1. FIDO2/YubiKey, because it gives recovery-key-like protection with easier
   day-to-day ergonomics when the key is present.
2. Recovery key, because it is high-entropy and reliable, but awkward to type
   and store safely.
3. Password, because it is the most familiar fallback but should be unique per
   host and different from your login password.

TPM2 is different: it is the automatic full-disk unlock path for normal boots,
not the credential you rely on when hardware or firmware state changes.

## Which command to use

| Command | Use it when |
|---|---|
| `ks hardware setup` | First-time end-to-end enrollment on a newly installed host |
| `sudo ks hardware report` | Check current state before changes or verify after changes |
| `ks hardware enroll password --disk=root` | Only rotate the default `keystone` LUKS password |
| `ks hardware enroll recovery --disk=root` | Generate a paper recovery key and enroll TPM2 in one run |
| `ks hardware enroll tpm2 --disk=root` | Re-bind TPM2 after firmware or Secure Boot changes |
| `ks hardware enroll fido2 --disk=root` | Add a plugged-in YubiKey or other FIDO2 device |
| `ks hardware enroll fingerprint` | Enroll a fingerprint reader for login/sudo |

For v1.1, the LUKS-targeting commands only support the root unlock volume.

## Recommended first-time flow

Run these on the newly installed host after Step 6 of
[`onboarding.md`](onboarding.md):

```bash
sudo ks hardware report
ks hardware setup --dry-run
ks hardware setup
sudo reboot
sudo ks hardware report
```

What to look for:

- Before enrollment, `report` usually shows the password slot as default and
  TPM2 / recovery / FIDO2 as missing.
- The dry-run should show either the full enrollment plan or the Secure Boot
  staging work that must happen before TPM enrollment can continue.
- The interactive setup should establish a FIDO2 or recovery fallback first,
  enroll TPM2 automatic unlock, then rotate the default password.
- If Secure Boot is not active yet, `ks hardware setup` now stages that work
  too: it can generate keys or enroll them in Setup Mode, then stop cleanly
  for the required firmware change or reboot before you rerun it.
- After reboot, `report` should show the default password warning gone.

## Preconditions and common blockers

- You must run enrollment on the installed system, not the live ISO.
- Secure Boot must end up enrolled, not merely present in firmware.
- TPM2 auto-unlock requires a visible TPM device.
- `ks hardware setup` is interactive in v1.1. There is still no
  non-interactive mode.
- When Secure Boot needs a firmware change, `ks hardware setup` will explain
  the state and offer to reboot directly into firmware setup. On systems that
  support it, this uses `systemctl reboot --firmware-setup`; otherwise enter
  firmware during boot with the vendor hotkey.

If a machine does not meet those conditions, `ks hardware report` will usually
tell you why before you change anything.

### Secure Boot firmware settings

The exact menu is vendor-specific. Look for these concepts rather than exact
labels:

- **Secure Boot enablement** turns enforcement on. Do this only after Keystone
  has generated/enrolled keys and the signed lanzaboote boot entry is present.
- **Setup Mode** or **Audit Mode** allows the OS to modify Secure Boot keys.
  Audit Mode is useful on firmware that otherwise blocks the current OS from
  booting while still allowing key enrollment.
- On many Dell systems, this is under **Boot Configuration**. Enable Secure
  Boot, then set **Secure Boot Mode** to **Audit Mode** while Keystone enrolls
  keys. After `ks hardware setup` reports Secure Boot enrolled and the system
  boots through lanzaboote, switch Secure Boot enforcement on and re-run
  `ks hardware setup`.

If you are already in Linux and Keystone has paused for firmware action, choose
the prompt to reboot into firmware setup or run:

```bash
sudo systemctl reboot --firmware-setup
```

<details>
<summary>Example: <code>ks hardware report</code> before enrollment</summary>

```text
Machine
  Secure Boot:        enrolled
  TPM2 device:        present (/dev/tpmrm0)
  FIDO2 devices:      none plugged in
  Fingerprint reader: none detected

LUKS volumes (1 unlock targets):
  root            /dev/disk/by-partlabel/disk-root-root  [primary, opens in initrd]
    Holds: rootfs encryption keys
    password   ⚠  DEFAULT — must be rotated
    recovery   —
    tpm2       —
    fido2      —

Warnings:
  ✖ [volume root] Volume `root` still accepts the default installer password.
      → Run `ks hardware enroll password --disk=root`.
```

The device path may be `/dev/zvol/rpool/credstore` on ZFS-backed installs.
The important signals are the default-password warning and the missing unlock
methods.

</details>

<details>
<summary>Example: <code>ks hardware setup --dry-run</code></summary>

```text
(dry run — would execute the following plan:)
Unlock model:
  FIDO2/YubiKey is the preferred human fallback when present.
  Recovery keys are high-entropy and reliable, but hard to type and store.
  Passwords are manual fallback; use a host-unique passphrase, not your login password.
  TPM2 provides automatic full-disk unlock after Secure Boot is active.
  Fingerprints are for login/sudo convenience, not disk unlock.

  • Enroll Secure Boot keys
  • Reboot and re-run setup: Secure Boot keys will be active after reboot. Re-run `ks hardware setup` to continue TPM enrollment.
  • Generate recovery key for `root`
  • Enroll TPM2 automatic unlock on `root`
  • Rotate default password on `root`
  • Skip: no fingerprint reader detected
```

If a FIDO2 key is plugged in, you should also see a step like:

```text
  • Enroll FIDO2 hardware key (Yubico YubiKey OTP+FIDO+CCID) on `root`
```

On a host where Secure Boot is disabled entirely, the dry-run will instead
start with a staging step like:

```text
  • Generate Secure Boot keys
  • Pause for firmware action: Enter firmware, enable Secure Boot or Setup/Audit Mode, then re-run `ks hardware setup` to enroll the generated keys and continue TPM enrollment.
```

During the real run, Keystone will offer to reboot directly into firmware
setup at this pause.

</details>

<details>
<summary>Example: interactive first-time setup</summary>

```text
Setup plan:
Unlock model:
  FIDO2/YubiKey is the preferred human fallback when present.
  Recovery keys are high-entropy and reliable, but hard to type and store.
  Passwords are manual fallback; use a host-unique passphrase, not your login password.
  TPM2 provides automatic full-disk unlock after Secure Boot is active.
  Fingerprints are for login/sudo convenience, not disk unlock.

  • Enroll FIDO2 hardware key (Yubico YubiKey OTP+FIDO+CCID) on `root`
  • Enroll TPM2 automatic unlock on `root`
  • Rotate default password on `root`
  • Skip: no fingerprint reader detected

Continue? [y/N]:
```

After confirmation, a representative run looks like:

```text
→ Enroll FIDO2 hardware key (Yubico YubiKey OTP+FIDO+CCID) on `root`
=== Keystone enrollment: FIDO2 hardware key ===

Detected FIDO2 device: Yubico YubiKey OTP+FIDO+CCID
Touch your FIDO2 device when it blinks...
[OK] FIDO2 enrolled.

→ Enroll TPM2 automatic unlock on `root`
=== Keystone enrollment: TPM2 (standalone) ===

Enrolling TPM2 (PCRs 1,7)...
[OK] TPM2 enrolled.

→ Rotate default password on `root`
=== Keystone enrollment: rotate LUKS password ===

Rotating slot 0 to the new passphrase...
[OK] LUKS slot 0 rotated.

✓ Setup complete. Run `ks hardware report` to verify.
```

</details>

## What each manual command is for

### Rotate only the default LUKS password

Use this when you are not ready to enroll TPM2 yet, but you want the
publicly known installer password gone immediately.

```bash
ks hardware enroll password --disk=root
```

This changes slot 0 in place. It does not add TPM2, FIDO2, or a recovery key.

### Generate a paper recovery key and enroll TPM2 together

This is the strongest manual path when you want a written recovery credential.

```bash
ks hardware enroll recovery --disk=root
```

This:

- keeps your chosen password as a manual fallback
- prints the recovery key once
- enrolls TPM2 for normal boot

### Re-bind TPM2 after firmware changes

Use this after Secure Boot key changes, firmware updates, or other TPM/PCR
drift that causes a previously enrolled system to prompt for manual unlock.

```bash
ks hardware enroll tpm2 --disk=root
```

### Add a FIDO2 hardware key

Plug the device in first, then run:

```bash
ks hardware enroll fido2 --disk=root
```

You will be prompted to touch the hardware key when it blinks.

### Enroll fingerprint for login and sudo

Fingerprint enrollment does not unlock the encrypted disk. It only improves
login and sudo ergonomics after the machine has booted.

```bash
ks hardware enroll fingerprint
```

The sensor will ask for the same finger several times. Lift and place your
finger each time so it can capture enough samples; failed scans can be retried.

This is not part of LUKS unlock. It controls user auth above the disk layer.

## After enrollment

After the first successful run:

1. Reboot once to confirm TPM auto-unlock really works.
2. Run `sudo ks hardware report` again.
3. Store the recovery key somewhere outside the encrypted disk.
4. If you use a FIDO2 key, test that flow before you need it.

If you want an AI agent to walk you through the exact flow on a live system,
use the prompts in [`system-agent-prompts.md`](system-agent-prompts.md).
