# REQ-033: Hardware keys

Keystone uses hardware keys to bind sensitive local actions to a human who is
physically present at the machine. A root-affecting operation must not be
performable by an unattended agent merely because the agent has shell access,
SSH access, or a cached privileged session.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Context

Keystone systems are intentionally agent-capable: local and remote agents may
edit repositories, run builds, and propose updates. That does not mean agents
should be able to change the root operating system without a human confirming
the action.

Hardware keys provide that confirmation boundary. The default Keystone posture
is:

- Agents may prepare root-affecting work.
- A local human must approve root-affecting execution.
- Approval should require a physical hardware-key interaction.
- Where the key supports it, approval should require user verification by
  default: PIN, biometric verification, or an equivalent on-device verification
  step.

Hardware keys are also the primary Keystone mechanism for agenix secret access.
Secrets rekeying, secret editing, and secret decryption are sensitive because
they can expose credentials that later affect root systems. A touch or biometric
event confirms presence for the secret operation; it does not automatically
approve an unrelated root activation unless Keystone explicitly binds the two
actions together.

This requirement complements `REQ-032`, which defines full-disk encryption
unlock methods. FDE hardware-key unlock and privileged update approval are
different workflows, but they share the same security goal: a remote or
unattended process must not be able to silently cross the root trust boundary.

## User stories

### US-1: Human confirms root changes

As a Keystone user, I want root-affecting updates to require my physical
presence, so that an agent cannot update or reconfigure my machine without me.

Acceptance criteria:

- Keystone MUST distinguish preparation work from privileged execution.
- Keystone MUST allow agents to prepare builds, plans, and repository changes.
- Keystone MUST require human-presence approval before applying root-affecting
  changes by default.
- Human-presence approval MUST require an interaction that an unattended
  process cannot synthesize.

### US-2: Hardware key is the default approval factor

As a Keystone user with a hardware key, I want Keystone to prefer that key for
privileged approval, so that password-only approval is not the normal path.

Acceptance criteria:

- Keystone MUST prefer hardware-key approval when a configured hardware key is
  available.
- Hardware-key approval MUST require user presence, such as touch.
- Hardware-key approval SHOULD require user verification, such as FIDO2 PIN or
  biometric verification, when the hardware and integration support it.
- Password or polkit-only approval MAY be used as a fallback, but MUST be
  visible in configuration and reporting.

### US-3: Disk unlock methods prove local control

As a Keystone user, I want disk unlock credentials to be enrolled and tested in
an order that proves I control the machine locally before TPM auto-unlock is
trusted.

Acceptance criteria:

- Keystone MUST treat hardware-key disk unlock as a preferred manual fallback.
- Keystone MUST require a real presence interaction during hardware-key FDE
  unlock validation.
- Keystone MUST NOT treat TPM2 auto-unlock as evidence of human presence.
- Keystone MUST explain that TPM2 improves normal boot ergonomics only after
  manual unlock methods have been enrolled and validated.

### US-4: Agenix secrets require physical confirmation

As a Keystone user, I want agenix secret access to require my hardware key, so
that agents cannot silently decrypt, edit, or rekey secrets without me.

Acceptance criteria:

- Keystone MUST treat agenix secret access as a primary hardware-key use case.
- Keystone MUST require hardware-key presence for Keystone-managed agenix
  decrypt, edit, and rekey workflows.
- Keystone MUST require user verification by default for Keystone-managed
  agenix workflows when the selected hardware-key mechanism supports it.
- Keystone MUST keep any PIN or approval cache short enough that an agent
  cannot rely on stale approval after the human walks away.

## Functional requirements

### FR-001: Hardware-key identity model

**REQ-033.1** Keystone MUST model hardware keys as named, configured security
devices with enough metadata to identify the intended key in user-facing
workflows and reports.

**REQ-033.2** Keystone SHOULD support at least primary and backup hardware-key
roles for each user.

**REQ-033.3** Keystone MUST distinguish these hardware-key uses when reporting
state: SSH authentication, age/agenix secret access, FDE unlock, and privileged
approval.

**REQ-033.4** Keystone MUST NOT infer that a hardware key is safe for one use
only because it is configured for another use.

### FR-002: Human-presence approval for root operations

**REQ-033.5** Root-affecting Keystone commands MUST have an explicit approval
policy.

**REQ-033.6** The default approval policy for root-affecting commands MUST
require local human presence.

**REQ-033.7** Hardware-key approval MUST require user presence for each
approval action.

**REQ-033.8** Hardware-key approval MUST require user verification by default
for each approval action when supported by the configured key and approval
mechanism.

**REQ-033.9** Keystone MUST NOT allow an unattended agent, background service,
or remote shell to satisfy human-presence approval without a physical
hardware-key interaction.

**REQ-033.10** Keystone approval caching for root-affecting operations MUST
default to no more than 15 seconds.

**REQ-033.11** Any approval cache longer than 15 seconds MUST be explicitly
configured, visible in reports, and scoped narrowly enough that it cannot become
a general root session.

**REQ-033.12** SSH multiplexing, ControlMaster sockets, SSH agent caching,
polkit caching, sudo timestamp caching, and similar transport caches MUST NOT
be treated as fresh hardware-key human-presence approval for a root-affecting
Keystone command.

**REQ-033.13** Keystone MUST NOT reuse a prior hardware-key approval for a
different root-affecting command unless the reuse scope is explicit, bounded,
and visible to the user.

**REQ-033.14** Root-affecting command reporting MUST show when a command is
using password-only, polkit-only, cached, or hardware-key-backed approval.

### FR-003: Hardware-key enrollment defaults

**REQ-033.15** Keystone hardware-key enrollment defaults MUST require user
presence.

**REQ-033.16** Keystone hardware-key enrollment defaults MUST require user
verification when the credential type supports it.

**REQ-033.17** Keystone MUST NOT generate Keystone-managed root/admin hardware
credentials with a no-touch or no-presence policy.

**REQ-033.18** Keystone MUST warn when an imported hardware-key credential is
usable for root-affecting workflows but does not require presence.

**REQ-033.19** Keystone SHOULD warn when an imported hardware-key credential is
usable for root-affecting workflows but does not require user verification.

### FR-004: Full-disk encryption unlock

**REQ-033.20** Hardware-key FDE unlock enrollment MUST require the user to
present the physical key.

**REQ-033.21** Hardware-key FDE unlock validation MUST require the user to
unlock the disk with the hardware key during a boot-time or initrd-equivalent
test.

**REQ-033.22** Keystone MUST explain that a hardware-key FDE unlock method
provides recovery-key-grade security with better ergonomics only while the
physical key and its PIN or biometric policy remain protected.

**REQ-033.23** Keystone MUST NOT present TPM2 auto-unlock as a human-presence
approval mechanism.

**REQ-033.24** Keystone MUST NOT mark TPM2 auto-unlock as fully trusted until
at least one durable manual unlock method has been enrolled and validated per
`REQ-032`.

### FR-005: Secret access

**REQ-033.25** Keystone-managed age/agenix hardware-key identities MUST
require touch for each decrypt operation.

**REQ-033.26** Keystone-managed age/agenix hardware-key identities MUST
require user verification by default when the selected token mechanism supports
it.

**REQ-033.27** Keystone-managed age/agenix PIN or verification caching MUST
default to no more than 15 seconds when Keystone can control the cache window.

**REQ-033.28** Keystone-managed age/agenix workflows MUST document any cache
window controlled by token firmware, `age-plugin-yubikey`, ssh-agent, gpg-agent,
or another external component.

**REQ-033.29** Keystone MUST document that a secret-decrypt touch confirms
secret access, not root activation approval, unless the privileged approval
workflow explicitly binds the decrypt action to the requested root operation.

### FR-006: Documentation and user prompts

**REQ-033.30** Keystone docs MUST explain the difference between user presence,
user verification, and TPM2 auto-unlock.

**REQ-033.31** Keystone docs MUST explain the common PIN domains separately:
FIDO2 PIN, PIV PIN, PIV PUK, and login password.

**REQ-033.32** Privileged approval prompts MUST name the command being approved
and whether approval requires touch, PIN, biometric verification, or password.

**REQ-033.33** FDE enrollment prompts MUST explain when the user should insert
the key, enter a PIN, touch the key, lift a finger, or reboot.

**REQ-033.34** Template documentation MUST explain that hardware-key presence
prevents agents from silently updating root machines.

## Non-functional requirements

### NFR-001: Security

**REQ-033.35** Keystone MUST fail closed when the configured hardware-key
approval factor is unavailable for a root-affecting command.

**REQ-033.36** Keystone MUST NOT log hardware-key PINs, biometric secrets,
private key handles, LUKS passphrases, generated recovery keys, or TPM sealed
secrets.

**REQ-033.37** Keystone MUST treat SSH access as remote reachability, not as
human-presence approval.

**REQ-033.38** Keystone MUST treat desktop unlock state as insufficient for
root-affecting approval unless a fresh hardware-key approval is collected for
the specific action or bounded approval scope.

### NFR-002: Usability

**REQ-033.39** Keystone SHOULD make the secure default easy: enroll a hardware
key, verify it works, then use it for FDE fallback and privileged approval.

**REQ-033.40** Keystone SHOULD provide clear fallback paths for hosts without
hardware keys, but those fallback paths MUST be visible as weaker than
hardware-key-backed approval.

**REQ-033.41** Keystone SHOULD use progressive disclosure in docs and prompts:
short normal-path instructions first, exact commands and expected output in
expanded or follow-up sections.

## Testing requirements

### TR-001: Unit and integration tests

**REQ-033.42** Approval-policy tests MUST cover that root-affecting commands
default to human-presence approval.

**REQ-033.43** Approval-policy tests MUST cover that password-only or
polkit-only fallback is explicit and reportable.

**REQ-033.44** Hardware-key enrollment tests MUST cover that Keystone-managed
root/admin credentials do not use no-touch or no-presence defaults.

**REQ-033.45** FDE planner tests MUST cover that TPM2 auto-unlock cannot
satisfy the human-presence requirement.

### TR-002: End-to-end tests

**REQ-033.46** E2E hardware enrollment tests SHOULD validate hardware-key disk
unlock before recovery-key or custom-password validation, and TPM2 auto-unlock
last.

**REQ-033.47** E2E privileged approval tests SHOULD validate that an
unattended agent session can prepare a root-affecting change but cannot apply
it without a human-presence approval event.

**REQ-033.48** E2E reporting tests SHOULD verify that `ks hardware report` and
the privileged approval surface show whether hardware-key-backed approval is
configured, available, and recently validated.

## Related requirements

- `REQ-001`: Keystone OS security model.
- `REQ-019`: `ks` CLI update and activation workflows.
- `REQ-027`: Desktop hardware and account menus.
- `REQ-032`: Full-disk encryption unlock methods.
