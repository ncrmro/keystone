# Tasks: TPM-Based Disk Encryption Enrollment

**Input**: Design documents from `/specs/006-tpm-enrollment/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: This feature relies on manual VM testing with bin/virtual-machine (no automated test suite requested in spec)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions
- **Module path**: `modules/tpm-enrollment/`
- **Documentation**: `docs/`
- **Examples**: `examples/tpm-enrollment/`
- **Tests**: Manual VM testing via `bin/virtual-machine`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and module structure

- [ ] T001 Create module directory structure at modules/tpm-enrollment/
- [ ] T002 [P] Create placeholder script files (enrollment-check.sh, enroll-recovery.sh, enroll-password.sh, enroll-tpm.sh)
- [ ] T003 [P] Create documentation directory at docs/tpm-enrollment.md
- [ ] T004 [P] Create examples directory at examples/tpm-enrollment/
- [ ] T005 Update flake.nix to export tpmEnrollment module in nixosModules

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core NixOS module infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T006 Create NixOS module skeleton in modules/tpm-enrollment/default.nix with enable option
- [ ] T007 Add module options: tpmPCRs (list of integers, default [1 7]), credstoreDevice (string, default "/dev/zvol/rpool/credstore")
- [ ] T008 Add assertions: Secure Boot enabled (config.keystone.secureBoot.enable), disko enabled (config.keystone.disko.enable)
- [ ] T009 Create systemd tmpfiles rule to create /var/lib/keystone directory (0755 root:root)
- [ ] T010 Implement PCR list to comma-separated string conversion helper function in default.nix

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - First-Boot TPM Enrollment Notification (Priority: P1) 🎯 MVP

**Goal**: Display warning banner on first login when TPM not enrolled, suppress after enrollment

**Independent Test**: Fresh Keystone installation → login → verify banner appears → enroll TPM → logout/login → verify banner suppressed

### Implementation for User Story 1

- [ ] T011 [P] [US1] Implement enrollment status detection logic in modules/tpm-enrollment/enrollment-check.sh
- [ ] T012 [US1] Add marker file validation (check /var/lib/keystone/tpm-enrollment-complete exists)
- [ ] T013 [US1] Add LUKS header validation (cryptsetup luksDump | grep systemd-tpm2)
- [ ] T014 [US1] Implement self-healing logic (create marker if TPM enrolled but marker missing)
- [ ] T015 [US1] Add warning banner display with ASCII box drawing and enrollment instructions
- [ ] T016 [US1] Configure shell profile integration in default.nix via environment.etc."profile.d/tpm-enrollment-warning.sh"

**Checkpoint**: At this point, User Story 1 should be fully functional - banner appears on fresh install, disappears after enrollment

---

## Phase 4: User Story 2 - Generate Recovery Key (Priority: P2)

**Goal**: Interactive script to generate cryptographically secure recovery key, enroll in LUKS, and configure TPM

**Independent Test**: Run keystone-enroll-recovery → save key → verify TPM enrolled → reboot → verify auto-unlock → disable TPM in BIOS → verify recovery key unlocks disk

### Implementation for User Story 2

- [ ] T017 [P] [US2] Implement prerequisite checks in modules/tpm-enrollment/enroll-recovery.sh (Secure Boot enabled, TPM available, credstore exists)
- [ ] T018 [P] [US2] Add recovery key generation using systemd-cryptenroll --recovery-key
- [ ] T019 [US2] Implement recovery key display with security warnings and storage recommendations
- [ ] T020 [US2] Add user confirmation prompt (press ENTER after saving key)
- [ ] T021 [US2] Implement TPM enrollment using configured PCR list from module options
- [ ] T022 [US2] Add default password removal logic (verify new credentials work first, then remove slot 0)
- [ ] T023 [US2] Create enrollment marker file with metadata (timestamp, method: recovery-key, PCRs used)

**Checkpoint**: User Story 2 complete - recovery key enrollment works independently, TPM auto-unlock functional

---

## Phase 5: User Story 3 - Replace Default Password with Custom Password (Priority: P2)

**Goal**: Interactive script to replace default "keystone" password with user-chosen secure password

**Independent Test**: Run keystone-enroll-password → set password → verify TPM enrolled → reboot → verify auto-unlock → disable TPM → verify custom password unlocks disk

### Implementation for User Story 3

- [ ] T024 [P] [US3] Implement password validation function in modules/tpm-enrollment/enroll-password.sh (12-64 chars, not "keystone")
- [ ] T025 [P] [US3] Add password prompt with silent input and confirmation
- [ ] T026 [US3] Implement password validation error messages (too short, too long, mismatch, prohibited)
- [ ] T027 [US3] Add optional password strength checking with pwscore (if available, warning only)
- [ ] T028 [US3] Implement LUKS password addition using cryptsetup luksAddKey
- [ ] T029 [US3] Add TPM enrollment and default password removal logic (reuse from US2)

**Checkpoint**: User Story 3 complete - custom password enrollment works independently alongside recovery key method

---

## Phase 6: User Story 4 - Automatic TPM Enrollment (Priority: P3)

**Goal**: Core TPM enrollment logic called by both recovery key and custom password scripts

**Independent Test**: Run standalone TPM enrollment (after manual credential setup) → verify TPM keyslot created → reboot → verify automatic unlock → check PCR binding correct

### Implementation for User Story 4

- [ ] T030 [P] [US4] Implement standalone TPM enrollment script in modules/tpm-enrollment/enroll-tpm.sh
- [ ] T031 [US4] Add Secure Boot validation using bootctl status (must show "enabled (user)")
- [ ] T032 [US4] Add TPM device detection using systemd-cryptenroll --tpm2-device=list
- [ ] T033 [US4] Implement systemd-cryptenroll command with configurable PCR list and --wipe-slot=empty
- [ ] T034 [US4] Add enrollment verification (check LUKS header for systemd-tpm2 token)
- [ ] T035 [US4] Add comprehensive error handling (no TPM, no Secure Boot, enrollment failure, keyslot exhaustion)

**Checkpoint**: All user stories complete - full enrollment workflow functional with TPM automatic unlock

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, examples, testing validation, and final integration

- [ ] T036 [P] Write user-facing documentation in docs/tpm-enrollment.md (enrollment guide, recovery scenarios, PCR configuration)
- [ ] T037 [P] Create example configuration in examples/tpm-enrollment/configuration.nix showing module usage
- [ ] T038 [P] Add flake.nix example showing external usage of tpmEnrollment module
- [ ] T039 Create manual test plan based on quickstart.md validation steps
- [ ] T040 Test on VM with bin/virtual-machine (fresh install, enrollment, reboot, auto-unlock, recovery)
- [ ] T041 Test PCR configuration variations (default [1,7], custom [7], custom [0,1,7])

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - US1 (P1) can start immediately after Foundational
  - US2 (P2) can start after Foundational - independent of US1
  - US3 (P2) can start after Foundational - independent of US1 and US2
  - US4 (P3) should start after US2 and US3 (provides shared enrollment logic they call)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: No dependencies on other stories - pure notification feature
- **User Story 2 (P2)**: Calls US4 logic but can be developed in parallel and integrated later
- **User Story 3 (P2)**: Calls US4 logic but can be developed in parallel and integrated later
- **User Story 4 (P3)**: Provides shared logic for US2 and US3 - develop last or extract during US2/US3

### Within Each User Story

- **US1**: Sequential implementation (detection → validation → banner → integration)
- **US2**: Parallel checks (T017, T018) → Sequential flow (T019-T023)
- **US3**: Parallel validation/prompts (T024, T025) → Sequential flow (T026-T029)
- **US4**: Parallel checks (T030, T031, T032) → Sequential enrollment (T033-T035)

### Parallel Opportunities

- **Setup phase**: T002, T003, T004 can all run in parallel (different files)
- **US1**: T011 can be developed independently before integration (T012-T016 sequential)
- **US2**: T017 and T018 can be developed in parallel
- **US3**: T024 and T025 can be developed in parallel
- **US4**: T030, T031, T032 can be developed in parallel
- **Polish**: T036, T037, T038 can all run in parallel (different files)

- **Cross-story parallelism**: Once Foundational (Phase 2) completes:
  - US1, US2, US3 can all be developed in parallel by different developers
  - US4 can be developed alongside US2/US3 and integrated when ready

---

## Parallel Example: Foundational Phase

```bash
# After completing Setup, these Foundational tasks can run in parallel:
# (Note: Different sections of default.nix, can be coordinated)

# Developer A:
Task T006: "Create NixOS module skeleton in modules/tpm-enrollment/default.nix"
Task T007: "Add module options"

# Developer B:
Task T008: "Add assertions"
Task T009: "Create systemd tmpfiles rule"

# Both merge their work, then:
Task T010: "Implement PCR list conversion helper" (depends on T007)
```

---

## Parallel Example: User Stories (After Foundational)

```bash
# Once Foundational complete, these user stories can proceed in parallel:

# Developer A: User Story 1 (P1) - MVP
Task T011-T016: "First-boot notification banner"

# Developer B: User Story 2 (P2) - Recovery key
Task T017-T023: "Recovery key enrollment"

# Developer C: User Story 3 (P2) - Custom password
Task T024-T029: "Custom password enrollment"

# Later, integrate:
# Developer D: User Story 4 (P3) - Shared TPM logic
Task T030-T035: "Standalone TPM enrollment"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T005)
2. Complete Phase 2: Foundational (T006-T010) - **CRITICAL BLOCKER**
3. Complete Phase 3: User Story 1 (T011-T016)
4. **STOP and VALIDATE**:
   - Fresh install via nixos-anywhere
   - Login via SSH
   - Verify banner appears
   - Manually enroll TPM (using systemd-cryptenroll directly)
   - Logout/login
   - Verify banner suppressed
5. Deploy/demo if ready - **MVP ACHIEVED**: Users are notified about enrollment status

### Incremental Delivery

1. **Foundation** (Phases 1-2): Module structure + configuration ready
2. **MVP** (Phase 3 + Foundation): User Story 1 → Test independently → Deploy/Demo
   - Value: Users see security notification, understand action needed
3. **Increment 2** (Phase 4): Add User Story 2 → Test independently → Deploy/Demo
   - Value: Users can enroll with recovery key, achieve automatic unlock
4. **Increment 3** (Phase 5): Add User Story 3 → Test independently → Deploy/Demo
   - Value: Users have choice between recovery key and custom password
5. **Increment 4** (Phase 6): Add User Story 4 → Test all workflows → Deploy/Demo
   - Value: Streamlined enrollment, all workflows integrated
6. **Polish** (Phase 7): Documentation, examples, comprehensive testing

Each increment adds value without breaking previous functionality.

### Parallel Team Strategy

With 3 developers after Foundational phase completes:

1. **Team completes Setup + Foundational together** (T001-T010)
2. **Once Foundational done, parallelize**:
   - **Developer A**: User Story 1 (T011-T016) - Notification banner
   - **Developer B**: User Story 2 (T017-T023) - Recovery key enrollment
   - **Developer C**: User Story 3 (T024-T029) - Custom password enrollment
3. **Integration**: Developer D adds User Story 4 (T030-T035) - Shared TPM logic
4. **Team completes Polish together** (T036-T041)

Stories integrate independently - US1 works alone, US2/US3 initially duplicate TPM logic, US4 extracts common code.

---

## PCR Configuration Details

The module uses a configurable PCR list that converts to systemd-cryptenroll format:

**NixOS Configuration**:
```nix
keystone.tpmEnrollment = {
  enable = true;
  tpmPCRs = [ 1 7 ];  # Default: firmware config + Secure Boot
  credstoreDevice = "/dev/zvol/rpool/credstore";
};
```

**Conversion in default.nix** (Task T010):
```nix
# Helper function converts list to comma-separated string
tpmPCRString = lib.concatStringsSep "," (map toString cfg.tpmPCRs);
# Result: "1,7"
```

**Usage in enrollment scripts** (Tasks T021, T029, T033):
```bash
systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=${tpmPCRString} \
  --wipe-slot=empty \
  /dev/zvol/rpool/credstore
```

**Alternative PCR configurations users can set**:
- `tpmPCRs = [ 7 ]` - Secure Boot only (more update-resilient)
- `tpmPCRs = [ 0 1 7 ]` - Firmware + config + Secure Boot (more restrictive)
- `tpmPCRs = [ 7 11 ]` - Secure Boot + kernel UKI (requires signed policies)

---

## Notes

- **[P] tasks**: Different files, no dependencies on incomplete work
- **[Story] label**: Maps task to user story for traceability and independent testing
- **No automated tests**: Feature relies on manual VM testing per spec (bin/virtual-machine with TPM emulation)
- **PCR configuration**: Defaults to [1, 7] per spec, but configurable for advanced users
- **Module pattern**: Follows existing Keystone modules (secure-boot, disko-single-disk-root)
- **Commit strategy**: Commit after each task or logical group (e.g., all US1 tasks together)
- **Validation**: Stop at any checkpoint to independently test the user story
- **Recovery testing**: Critical to verify recovery key/password works when TPM disabled

**Research Note**: Research recommended PCR 7 only, but spec requires 1+7 as default with configuration option. Module allows both via tpmPCRs option.
