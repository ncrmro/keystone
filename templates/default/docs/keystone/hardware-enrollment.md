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

After enrollment, a fully configured machine aims for this layered fallback:

| Method | What it is | Used when |
|---|---|---|
| Password | Your chosen LUKS passphrase | Manual fallback if automatic methods fail |
| Recovery key | An 8-word paper key | Disaster recovery |
| TPM2 | Automatic unlock bound to Secure Boot + measured boot state | Normal day-to-day boot |
| FIDO2 | Optional hardware-key unlock | Manual fallback after TPM rebinding or hardware changes |
| Fingerprint | `fprintd` enrollment for login/sudo | Desktop convenience, not disk unlock |

The important model is: Keystone does not want a single magic unlock path.
It wants automatic boot when the machine is healthy, plus at least one human
recovery path when it is not.

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
- The interactive setup should rotate the default password first, then show
  the recovery key once, then enroll TPM2, then optionally enroll FIDO2 or
  fingerprint if the hardware is present.
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

If a machine does not meet those conditions, `ks hardware report` will usually
tell you why before you change anything.

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
  • Enroll Secure Boot keys
  • Reboot and re-run setup: Secure Boot keys will be active after reboot. Re-run `ks hardware setup` to continue TPM enrollment.
  • Rotate default password on `root`
  • Generate recovery key + enroll TPM2 on `root`
  • Skip: no fingerprint reader detected
```

If a FIDO2 key is plugged in, you should also see a step like:

```text
  • Enroll FIDO2 (Yubico YubiKey OTP+FIDO+CCID) on `root`
```

On a host where Secure Boot is disabled entirely, the dry-run will instead
start with a staging step like:

```text
  • Generate Secure Boot keys
  • Pause for firmware action: Enter firmware, enable Secure Boot or Setup Mode, then re-run `ks hardware setup` to enroll the generated keys and continue TPM enrollment.
```

</details>

<details>
<summary>Example: interactive first-time setup</summary>

```text
Setup plan:
  • Rotate default password on `root`
  • Generate recovery key + enroll TPM2 on `root`
  • Enroll FIDO2 (Yubico YubiKey OTP+FIDO+CCID) on `root`
  • Skip: no fingerprint reader detected

Continue? [y/N]:
```

After confirmation, a representative run looks like:

```text
→ Rotate default password on `root`
=== Keystone enrollment: rotate LUKS password ===

Rotating slot 0 to the new passphrase...
[OK] LUKS slot 0 rotated.

→ Generate recovery key + enroll TPM2 on `root`
=== Keystone enrollment: recovery key + TPM2 ===

[Step 1/3] Generating recovery key...

+-------------------------------------------------------------------------+
|                       YOUR RECOVERY KEY                                 |
+-------------------------------------------------------------------------+
|                                                                         |
|  aaaaaaaa-bbbbbbbb-cccccccc-dddddddd-eeeeeeee-ffffffff-gggggggg-hhhhhhhh  |
|                                                                         |
+-------------------------------------------------------------------------+

[!] Save this key immediately. It will not be shown again.

Store in:
  - Password manager with offline backup
  - Printed paper in physical safe

[Step 2/3] Enrolling TPM2 (PCRs 1,7)...
[OK] TPM2 enrolled (password slot preserved as manual fallback).

[Step 3/3] Writing enrollment marker...
[OK] Done. Test with: sudo reboot

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

```bash
ks hardware enroll fingerprint
```

This is not part of LUKS unlock. It controls user auth above the disk layer.

## After enrollment

After the first successful run:

1. Reboot once to confirm TPM auto-unlock really works.
2. Run `sudo ks hardware report` again.
3. Store the recovery key somewhere outside the encrypted disk.
4. If you use a FIDO2 key, test that flow before you need it.

If you want an AI agent to walk you through the exact flow on a live system,
use the prompts in [`system-agent-prompts.md`](system-agent-prompts.md).
