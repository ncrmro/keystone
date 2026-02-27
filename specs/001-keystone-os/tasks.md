# Keystone OS Tasks

## Phase 1: ext4 + LUKS + TPM + Hibernation (Laptop)

### Task 1: Convert ext4 swap from random encryption to persistent LUKS [ADDED]
**Spec**: FR-002, FR-012
**File**: `modules/os/storage.nix`

Currently `storage.nix:380-382` uses `randomEncryption = true` for the ext4 swap partition. This must change to a persistent LUKS volume so the kernel can decrypt swap during hibernate resume.

- Replace `randomEncryption = true` with LUKS encryption on the swap partition
- Swap LUKS volume should use the same TPM unlock as the root LUKS volume (or be unlocked as part of the same flow)
- Ensure swap partition is sized >= RAM when hibernation is enabled

### Task 2: Add boot.resumeDevice configuration [ADDED]
**Spec**: FR-012
**File**: `modules/os/storage.nix`

Configure `boot.resumeDevice` to point to the decrypted swap device so the kernel knows where to find the hibernation image.

- Set `boot.resumeDevice = "/dev/mapper/cryptswap"` (or equivalent) when `hibernate.enable = true`
- Add `resume` to `boot.initrd.availableKernelModules` if needed
- Ensure resume happens after LUKS unlock but before normal boot continues

### Task 3: Add hibernate.enable option [ADDED]
**Spec**: FR-012
**File**: `modules/os/default.nix` or `modules/os/storage.nix`

Add `keystone.os.storage.hibernate.enable` option with assertions:

- Assert `cfg.type == "ext4"` when hibernate is enabled (ZFS cannot hibernate)
- Assert swap size >= RAM (or warn)
- When enabled, switch swap to persistent LUKS and configure resumeDevice

### Task 4: Validate TPM unlock survives hibernate/resume [ADDED]
**Spec**: FR-003, FR-012

TPM PCR values must not change during a hibernate/resume cycle. Verify:

- Boot → TPM unlock → hibernate → resume → system functional
- PCR measurements are identical before hibernate and after resume
- No re-enrollment needed after hibernate

### Task 5: Laptop fresh install end-to-end [ADDED]
**Spec**: SC-001, FR-012

Perform a fresh install on the laptop (Framework) with:

- ext4 + LUKS root
- Persistent LUKS swap (>= 32GB for 32GB RAM)
- TPM enrollment + Secure Boot
- Hibernate and verify resume works
- Document any issues for iteration

### Task 6: Iterate on installer UX [ADDED]
**Spec**: SC-001

Use repeated laptop installs to identify friction in the install experience:

- ISO boot → nixos-anywhere deploy time
- TPM enrollment smoothness
- First-boot experience
- Document improvements needed

## Phase 2: ZFS + Credstore + TPM (Workstation)

### Task 7: Validate ZFS workstation install
**Spec**: FR-002, FR-005

Perform a fresh install on workstation with:

- ZFS + credstore + LUKS + TPM
- Verify snapshots, compression, scrub all working
- Verify `allowHibernation = false` is enforced
- Document any issues

## Completed

(None yet)
