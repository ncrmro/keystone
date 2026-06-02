# REQ-032: Full-disk encryption unlock methods

Keystone-managed hosts need a clear, testable full-disk encryption enrollment
model that lets users choose durable manual unlock methods before enabling TPM2
automatic unlock.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Context

Keystone installs encrypted systems with a temporary LUKS password so the first
boot is recoverable. Long-term enrollment has three different jobs:

- A hardware key, such as a YubiKey/FIDO2 device, gives strong manual unlock
  with better ergonomics than typing a long recovery key.
- A generated recovery key gives high-entropy paper backup for disaster
  recovery, but is intentionally hard to type and must be stored off-host.
- A custom LUKS password gives manual fallback without extra hardware, but is
  weaker than hardware-backed or generated randomness unless the user chooses
  and stores it carefully.
- TPM2 gives day-to-day automatic unlock only after Secure Boot and measured
  boot state are trustworthy.

The setup workflow must make this distinction visible. TPM2 is not a backup
credential. It is the ergonomic normal-boot path after at least one backup
credential is enrolled and tested.

## User stories

### US-1: Choose trusted unlock methods

As a Keystone user enrolling a new host, I want to choose which manual unlock
methods I trust, so that I can balance ergonomics, recovery safety, and
hardware availability.

Acceptance criteria:

- The setup flow MUST explain the preferred order: hardware key, generated
  recovery key, custom LUKS password, then TPM2 automatic unlock.
- The setup flow MUST allow a user with a YubiKey/FIDO2 device to trust the
  hardware key enough to skip creating a custom LUKS password.
- The setup flow MUST allow the user to create a generated recovery key instead
  of, or in addition to, a custom LUKS password.
- The setup flow MUST explain that host passwords SHOULD be unique per host and
  SHOULD differ from the login password.

### US-2: Validate each layer before trusting it

As a Keystone user, I want to reboot-test each configured unlock method before
Keystone removes the temporary installer password, so that I know every fallback
works before I need it.

Acceptance criteria:

- Keystone MUST guide the user through a progressive validation sequence:
  hardware key first, generated recovery key or custom password next, and TPM2
  automatic unlock last.
- Keystone MUST NOT consider an unlock method trusted merely because a LUKS
  token or keyslot exists.
- Keystone MUST require a real boot-time or initrd-equivalent validation before
  marking an unlock method trusted.
- Keystone SHOULD prefer real reboot tests on physical hardware.
- Keystone MAY provide an explicit dry-run or test mode for virtual-machine CI
  when a physical reboot is not available.

### US-3: Enable TPM2 only after fallback trust exists

As a Keystone user, I want TPM2 auto-unlock to be the final step, so that a
machine never becomes dependent on an untested or unavailable fallback.

Acceptance criteria:

- Keystone MUST block TPM2 enrollment until at least one durable manual unlock
  method is enrolled.
- Keystone MUST warn before TPM2 enrollment if no manual unlock method has been
  reboot-tested.
- Keystone SHOULD keep the temporary installer password available until at
  least one long-term manual unlock method has been validated.
- Keystone MUST remove or rotate the temporary installer password before the
  workflow is complete.

## Functional requirements

### FR-001: Unlock method model

**REQ-032.1** Keystone MUST model LUKS unlock methods separately from boot
integrity state.

**REQ-032.2** Keystone MUST distinguish these unlock method classes:
hardware key, generated recovery key, custom password, temporary installer
password, and TPM2 automatic unlock.

**REQ-032.3** Keystone MUST present TPM2 as automatic unlock, not as a recovery
method.

**REQ-032.4** Keystone MUST treat Secure Boot custom-key enrollment as a
prerequisite for TPM2 automatic unlock when PCR 7 is part of the TPM binding.

### FR-002: User choice

**REQ-032.5** `ks hardware setup` MUST allow users to enroll a YubiKey/FIDO2
hardware key when a compatible device is present.

**REQ-032.6** `ks hardware setup` MUST allow users to skip a custom LUKS
password when they choose to trust hardware-key and recovery-key based unlock.

**REQ-032.7** `ks hardware setup` MUST allow users to set a custom LUKS
password when they want a memorized manual fallback.

**REQ-032.8** `ks hardware setup` MUST allow users to generate a recovery key
instead of, or in addition to, setting a custom LUKS password.

**REQ-032.9** Generated recovery keys MUST be displayed with instructions to
store them outside the encrypted disk before any destructive keyslot cleanup.

### FR-003: Progressive validation

**REQ-032.10** Keystone MUST explain that enrollment is progressive: enroll a
candidate unlock method, reboot-test it, mark it trusted, then proceed to the
next layer.

**REQ-032.11** If a hardware key is enrolled, Keystone MUST offer a reboot test
that requires unlocking with that hardware key before TPM2 auto-unlock is
enabled.

**REQ-032.12** If a generated recovery key is enrolled, Keystone MUST offer a
reboot test that requires unlocking with that recovery key before the recovery
key is marked trusted.

**REQ-032.13** If a custom LUKS password is enrolled, Keystone MUST offer a
reboot test that requires unlocking with that custom password before the
password is marked trusted.

**REQ-032.14** If multiple manual methods are configured, Keystone SHOULD guide
the user through testing each method by temporarily removing or not presenting
easier methods as needed, such as unplugging the FIDO2 key while testing a
password or recovery key.

**REQ-032.15** Keystone MUST make clear that TPM2 validation is different from
manual-method validation: the TPM2 test succeeds when the host reboots without
manual LUKS entry under the expected Secure Boot state.

### FR-004: Safety gates

**REQ-032.16** Keystone MUST NOT remove the temporary installer password until
at least one long-term manual unlock method has been validated.

**REQ-032.17** Keystone SHOULD require explicit user confirmation before
removing the temporary installer password if only one long-term manual unlock
method exists.

**REQ-032.18** Keystone MUST report any remaining temporary installer password
as a warning after enrollment.

**REQ-032.19** Keystone MUST report a durable manual unlock method as untrusted
until its validation evidence exists.

**REQ-032.20** Keystone MUST fail safe if validation evidence is missing,
ambiguous, or from the wrong host.

### FR-005: Reporting and documentation

**REQ-032.21** `ks hardware report` MUST show each enrolled unlock method and
whether it is unvalidated, validated, stale, or unavailable.

**REQ-032.22** `ks hardware report` MUST explain when TPM2 is enrolled but no
validated manual backup exists.

**REQ-032.23** Template documentation MUST describe why hardware keys and
generated recovery keys are preferred over memorized passwords for disk unlock.

**REQ-032.24** Template documentation MUST include a short checklist for the
reboot validation order: YubiKey/FIDO2, recovery key or custom password, then
TPM2 automatic unlock.

**REQ-032.25** The CLI MUST explain what the user should expect during a reboot
test, including whether they should insert, touch, remove, or avoid using a
hardware key.

## Non-functional requirements

### NFR-001: Security

**REQ-032.26** Validation state MUST NOT store plaintext unlock credentials.

**REQ-032.27** Validation state MUST be scoped to a concrete host and LUKS
volume identity.

**REQ-032.28** Keystone MUST NOT log generated recovery keys, passphrases, FIDO2
PINs, or TPM sealed secrets.

### NFR-002: Usability

**REQ-032.29** The setup flow SHOULD use progressive disclosure: short default
explanations with expandable details in template docs.

**REQ-032.30** The setup flow SHOULD keep the initial decision simple: choose
hardware key, recovery key, password, or a combination, then test each layer.

**REQ-032.31** Error messages MUST state whether the user is blocked by
firmware state, missing hardware, a failed validation reboot, or an untrusted
manual fallback.

## Testing requirements

### TR-001: Unit tests

**REQ-032.32** Planner tests MUST cover the ordering: manual fallback
enrollment and validation before TPM2 enrollment.

**REQ-032.33** Planner tests MUST cover the case where a YubiKey/FIDO2
enrollment lets the user skip custom password creation while still requiring
some validated backup path.

**REQ-032.34** Planner tests MUST cover recovery-key-only, password-only, and
recovery-key-plus-password choices.

### TR-002: E2E tests

**REQ-032.35** Hardware enrollment E2E tests SHOULD validate that TPM2 is not
enrolled before the manual fallback phase completes.

**REQ-032.36** Hardware enrollment E2E tests SHOULD include a reboot boundary
for TPM2 automatic unlock validation.

**REQ-032.37** When virtual FIDO2 support is available, E2E tests SHOULD verify
the hardware-key validation branch before TPM2 enrollment.

**REQ-032.38** Manual hardware test instructions MUST cover a real YubiKey
reboot test, recovery key or password reboot test, and final TPM2 reboot test.

## Out of scope

- Network unlock over SSH or Tailscale.
- Multi-factor disk unlock requiring both TPM2 and a manual credential.
- Centralized recovery-key escrow.
- Automatic recovery-key rotation.
- Remote attestation of TPM state.

## Related requirements

- `REQ-001` defines Keystone OS full disk encryption and verified boot
  requirements.
- `specs/_archive/006-tpm-enrollment/spec.md` is the historical TPM-only
  enrollment spec; this spec supersedes its unlock-method ordering model.
