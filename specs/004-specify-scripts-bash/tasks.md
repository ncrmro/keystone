# Tasks: Secure Boot Custom Key Enrollment

**Input**: Design documents from `/specs/004-specify-scripts-bash/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/script-interfaces.md

**Tests**: Not explicitly requested in spec - focus on implementation and integration with existing test framework

**Organization**: Tasks grouped by user story to enable independent implementation and testing

**IMPLEMENTATION NOTE**: This feature was implemented using a Python-based approach (`bin/post-install-provisioner`) instead of separate bash scripts. This provides:
- Better maintainability and error handling
- Integration with existing Python test infrastructure (bin/test-deployment)
- Extensibility for future provisioning tasks (TPM enrollment, etc.)
- Single source of truth for post-installation logic

The implementation fulfills all user stories and contracts, but using Python instead of bash scripts.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and directory structure

- [X] T001 Create scripts/ directory for Secure Boot shell scripts
- [X] T002 [P] Ensure sbctl is available in NixOS environment (added to examples/test-server.nix)
- [X] T003 [P] Verify bootctl availability in target environment
- [X] T004 [P] Create documentation structure in specs/004-specify-scripts-bash/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T005 Document sbctl command syntax and exit codes from research.md
- [ ] T006 [P] Create error handling helper functions for JSON error output (reusable across all scripts)
- [ ] T007 [P] Create pre-condition check functions (root user, sbctl available, efivars mounted)
- [ ] T008 Define standard exit code constants (SUCCESS=0, PRECONDITION_FAILED=1, etc.)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Generate Custom Secure Boot Keys (Priority: P1) 🎯 MVP

**Goal**: Generate Platform Key (PK), Key Exchange Key (KEK), and signature database (db) keys using sbctl

**Independent Test**: Run key generation and verify all 12 files (PK, KEK, db × 4 formats each) are created with correct permissions (private keys 600, public files 644) in /var/lib/sbctl/keys/

### Implementation for User Story 1

- [ ] T009 [P] [US1] Create scripts/secureboot-generate-keys.sh with shebang and basic structure
- [ ] T010 [US1] Implement argument parsing for --output-dir and --force flags in scripts/secureboot-generate-keys.sh
- [ ] T011 [US1] Implement pre-condition checks in scripts/secureboot-generate-keys.sh (root user, sbctl available, output dir writable)
- [ ] T012 [US1] Implement existing key detection logic in scripts/secureboot-generate-keys.sh (exit 2 if keys exist and --force not set)
- [ ] T013 [US1] Implement sbctl create-keys invocation with error handling in scripts/secureboot-generate-keys.sh
- [ ] T014 [US1] Implement post-generation validation in scripts/secureboot-generate-keys.sh (verify 12 files created, check permissions)
- [ ] T015 [US1] Implement JSON success output in scripts/secureboot-generate-keys.sh per Contract 1 spec
- [ ] T016 [US1] Implement JSON error output in scripts/secureboot-generate-keys.sh for all failure modes (exit codes 1-4)
- [ ] T017 [US1] Add performance tracking (durationSeconds) to scripts/secureboot-generate-keys.sh output
- [ ] T018 [US1] Make scripts/secureboot-generate-keys.sh executable (chmod +x)

**Checkpoint**: User Story 1 complete - can generate keys independently and verify with quickstart.md workflow

---

## Phase 4: User Story 2 - Enroll Custom Keys in VM Firmware (Priority: P2)

**Goal**: Enroll generated keys into UEFI firmware, transitioning from Setup Mode (SetupMode=1) to User Mode (SetupMode=0, SecureBoot=1)

**Independent Test**: Provide pre-generated keys, run enrollment script, verify firmware variables show SetupMode=0, SecureBoot=1, and PK/KEK/db are populated (use bootctl status or od to read EFI variables)

### Implementation for User Story 2

- [ ] T019 [P] [US2] Create scripts/secureboot-enroll-keys.sh with shebang and basic structure
- [ ] T020 [US2] Implement argument parsing for --key-dir, --microsoft, and --verify-only flags in scripts/secureboot-enroll-keys.sh
- [ ] T021 [US2] Implement pre-condition checks in scripts/secureboot-enroll-keys.sh (root, sbctl available, keys exist, efivars mounted)
- [ ] T022 [US2] Implement Setup Mode verification in scripts/secureboot-enroll-keys.sh (read SetupMode variable, exit 2 if already enrolled)
- [ ] T023 [US2] Implement --verify-only dry-run mode in scripts/secureboot-enroll-keys.sh (check Setup Mode and exit without enrolling)
- [ ] T024 [US2] Implement pre-enrollment status capture in scripts/secureboot-enroll-keys.sh (read SetupMode, SecureBoot, PK variables)
- [ ] T025 [US2] Implement sbctl enroll-keys invocation in scripts/secureboot-enroll-keys.sh (with --yes-this-might-brick-my-machine for custom-only)
- [ ] T026 [US2] Implement Microsoft certificate enrollment variant in scripts/secureboot-enroll-keys.sh (sbctl enroll-keys --microsoft if --microsoft flag set)
- [ ] T027 [US2] Implement post-enrollment verification in scripts/secureboot-enroll-keys.sh (confirm SetupMode=0, SecureBoot=1, PK/KEK/db enrolled)
- [ ] T028 [US2] Implement JSON success output in scripts/secureboot-enroll-keys.sh with pre/post enrollment states per Contract 2
- [ ] T029 [US2] Implement JSON error output in scripts/secureboot-enroll-keys.sh for all failure modes (exit codes 1-4)
- [ ] T030 [US2] Add performance tracking (durationSeconds) to scripts/secureboot-enroll-keys.sh output
- [ ] T031 [US2] Make scripts/secureboot-enroll-keys.sh executable (chmod +x)

**Checkpoint**: User Story 2 complete - can enroll keys independently (depends on generated keys from US1)

---

## Phase 5: User Story 3 - Verify Secure Boot Enabled Status (Priority: P3)

**Goal**: Automated verification of Secure Boot status with structured JSON output for test automation integration

**Independent Test**: Run verification script against VMs in known states (setup mode vs user mode) and verify correct status detection, JSON formatting, and exit codes

### Implementation for User Story 3

- [ ] T032 [P] [US3] Create scripts/secureboot-verify.sh with shebang and basic structure
- [ ] T033 [US3] Implement argument parsing for --format (json|text) and --expected-mode (setup|user|disabled) in scripts/secureboot-verify.sh
- [ ] T034 [US3] Implement pre-condition checks in scripts/secureboot-verify.sh (bootctl available, efivars mounted, UEFI system)
- [ ] T035 [US3] Implement bootctl status parsing in scripts/secureboot-verify.sh (extract Secure Boot status, Setup Mode, firmware info)
- [ ] T036 [US3] Implement fallback EFI variable reading in scripts/secureboot-verify.sh (if bootctl unavailable, use od + efivars)
- [ ] T037 [US3] Implement firmware variable detection in scripts/secureboot-verify.sh (read SetupMode, SecureBoot, check PK/KEK/db enrollment)
- [ ] T038 [US3] Implement status aggregation logic in scripts/secureboot-verify.sh (derive mode: setup|user|disabled|unknown)
- [ ] T039 [US3] Implement JSON output formatting in scripts/secureboot-verify.sh per Contract 3 spec (status, enforcing, firmware, variables)
- [ ] T040 [US3] Implement text output formatting in scripts/secureboot-verify.sh (human-readable summary)
- [ ] T041 [US3] Implement --expected-mode validation in scripts/secureboot-verify.sh (exit 10 if mismatch, 0 if match)
- [ ] T042 [US3] Implement exit code logic in scripts/secureboot-verify.sh (0=success, 1=unknown, 2=setup, 3=disabled, 10=mismatch)
- [ ] T043 [US3] Add timestamp (verifiedAt) and method (bootctl/efi-variables) to scripts/secureboot-verify.sh JSON output
- [ ] T044 [US3] Make scripts/secureboot-verify.sh executable (chmod +x)

**Checkpoint**: User Story 3 complete - verification script works independently for any Secure Boot state

---

## Phase 6: Test Integration (bin/test-deployment)

**Purpose**: Integrate Secure Boot verification into automated VM deployment testing workflow

**Depends on**: User Story 3 (verification script must exist)

- [ ] T045 Add import json at top of bin/test-deployment (for parsing verification output)
- [ ] T046 Create verify_secureboot_enabled() function in bin/test-deployment per Contract 4 spec
- [ ] T047 Implement SSH-based verification script invocation in verify_secureboot_enabled() (call scripts/secureboot-verify.sh via ssh_vm)
- [ ] T048 Implement JSON parsing and status logging in verify_secureboot_enabled() (parse status, enforcing, key enrollment)
- [ ] T049 Implement error handling for verification failures in verify_secureboot_enabled() (exit codes 2, 3, 10)
- [ ] T050 Add verification step to main() workflow in bin/test-deployment (after deployment, before final verification)
- [ ] T051 Update total_steps count in main() to include Secure Boot verification step
- [ ] T052 Add print_step() call for "Verifying Secure Boot enabled" in bin/test-deployment
- [ ] T053 Implement failure handling in main() if verify_secureboot_enabled() returns False
- [ ] T054 Update success output in main() to include Secure Boot status confirmation

**Checkpoint**: End-to-end workflow complete - deployment test includes Secure Boot verification

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements affecting multiple scripts and documentation

- [ ] T055 [P] Add usage examples and help text to all three scripts (--help flag)
- [ ] T056 [P] Add script version identifiers and change log comments
- [ ] T057 [P] Validate JSON output formatting across all scripts (ensure valid JSON, consistent structure)
- [ ] T058 [P] Add comprehensive error messages with suggestions for common failures (keys exist, not in Setup Mode, bootctl missing)
- [ ] T059 Test complete workflow per quickstart.md guide (VM creation → key generation → enrollment → verification)
- [ ] T060 [P] Update CLAUDE.md with Secure Boot workflow documentation (how to use new scripts)
- [ ] T061 [P] Create examples/secureboot-enrollment.md with real usage examples
- [ ] T062 Validate performance criteria (SC-001: generation <30s, SC-002: enrollment <60s, SC-003: immediate verification)
- [ ] T063 Test edge cases (existing keys, non-Setup Mode, partial enrollment, bootctl unavailable)
- [ ] T064 Run full deployment test with --hard-reset to verify end-to-end integration

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User Story 1 (P1): Independent - can start after Foundational
  - User Story 2 (P2): Independent (can use pre-generated keys for testing) - can start after Foundational
  - User Story 3 (P3): Independent (read-only, works with any state) - can start after Foundational
- **Test Integration (Phase 6)**: Depends on User Story 3 (needs verification script)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: No dependencies on other stories - purely key generation
- **User Story 2 (P2)**: Runtime dependency on US1 (needs keys to enroll), but can be implemented/tested with pre-generated keys
- **User Story 3 (P3)**: No dependencies on other stories - read-only verification works independently

### Within Each User Story

**User Story 1** (Generate Keys):
1. Create script file (T009)
2. Argument parsing (T010)
3. Pre-conditions → Key detection → sbctl invocation → Post-validation → Output formatting (T011-T017)
4. Make executable (T018)

**User Story 2** (Enroll Keys):
1. Create script file (T019)
2. Argument parsing (T020)
3. Pre-conditions → Setup Mode check → Enrollment → Post-verification → Output formatting (T021-T030)
4. Make executable (T031)

**User Story 3** (Verify Status):
1. Create script file (T032)
2. Argument parsing (T033)
3. Pre-conditions → Status detection → Aggregation → Output formatting → Exit codes (T034-T042)
4. Timestamp/method metadata (T043)
5. Make executable (T044)

**Test Integration**:
1. Import dependencies (T045)
2. Create verification function (T046-T049)
3. Integrate into main workflow (T050-T054)

### Parallel Opportunities

- **Setup phase**: T002, T003, T004 can run in parallel (different checks/files)
- **Foundational phase**: T006, T007 can run in parallel (different utility functions)
- **User Story 1**: T009 (file creation) can run in parallel with documentation tasks
- **User Story 2**: T019 (file creation) can run in parallel with US1 or US3
- **User Story 3**: T032 (file creation) can run in parallel with US1 or US2
- **Polish phase**: T055, T056, T057, T058, T060, T061 can run in parallel (different files)

**Between User Stories**: Once Foundational (Phase 2) is complete, all three user stories can be implemented in parallel by different developers.

---

## Parallel Example: Foundational Phase

```bash
# Can launch these tasks together:
Task: "Create error handling helper functions for JSON error output (reusable across all scripts)"
Task: "Create pre-condition check functions (root user, sbctl available, efivars mounted)"
```

---

## Parallel Example: User Story Scripts

```bash
# After Foundational phase completes, launch all user story implementations in parallel:
Task: "Create scripts/secureboot-generate-keys.sh with shebang and basic structure"
Task: "Create scripts/secureboot-enroll-keys.sh with shebang and basic structure"
Task: "Create scripts/secureboot-verify.sh with shebang and basic structure"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Foundational (T005-T008) - CRITICAL checkpoint
3. Complete Phase 3: User Story 1 (T009-T018) - Key generation working
4. **STOP and VALIDATE**: Test key generation independently using quickstart.md
   - Run: `sudo scripts/secureboot-generate-keys.sh`
   - Verify: 12 files created with correct permissions
   - Test: --force flag overwrites existing keys
   - Test: JSON output formatting
5. Demo/deploy if ready (minimal viable Secure Boot key generation)

### Incremental Delivery

1. **Setup + Foundational** → Foundation ready (T001-T008)
2. **Add User Story 1** → Test independently → Key generation works! (MVP)
3. **Add User Story 2** → Test independently → Enrollment works! (keys can be enrolled)
4. **Add User Story 3** → Test independently → Verification works! (status detection)
5. **Add Test Integration** → Full automation (bin/test-deployment includes verification)
6. **Polish** → Production-ready (error handling, docs, edge cases)

Each story adds value without breaking previous stories.

### Parallel Team Strategy

With 3 developers after Foundational phase (T008) completes:

- **Developer A**: User Story 1 (T009-T018) - Key generation script
- **Developer B**: User Story 2 (T019-T031) - Enrollment script
- **Developer C**: User Story 3 (T032-T044) - Verification script

Then:
- **Developer D**: Test Integration (T045-T054) - depends on Developer C completing
- **All developers**: Polish phase (T055-T064) - parallelizable tasks

---

## Task Checklist Summary

**Total Tasks**: 64
- **Phase 1 (Setup)**: 4 tasks
- **Phase 2 (Foundational)**: 4 tasks (CRITICAL - blocks all user stories)
- **Phase 3 (User Story 1 - P1)**: 10 tasks (MVP)
- **Phase 4 (User Story 2 - P2)**: 13 tasks
- **Phase 5 (User Story 3 - P3)**: 13 tasks
- **Phase 6 (Test Integration)**: 10 tasks
- **Phase 7 (Polish)**: 10 tasks

**Parallel Opportunities**: 15 tasks marked [P] (can run concurrently within phases)

**Independent Test Criteria**:
- **US1**: Key generation produces 12 files with correct permissions, JSON output valid
- **US2**: Enrollment transitions SetupMode 1→0, SecureBoot 0→1, PK/KEK/db enrolled
- **US3**: Verification correctly detects setup/user/disabled modes, JSON output valid, exit codes correct

**Suggested MVP Scope**: Phases 1-3 only (Setup + Foundational + User Story 1 = Key generation working)

**Format Validation**: ✅ All tasks follow checklist format with checkboxes, IDs, optional [P] markers, [Story] labels for user story phases, and file paths

---

## Notes

- [P] tasks can run in parallel (different files, no blocking dependencies)
- [Story] labels (US1, US2, US3) map tasks to user stories for traceability
- Each user story is independently completable and testable
- No tests requested in spec - focus on implementation and integration
- Commit after logical task groups or checkpoints
- Validate independently at each checkpoint before proceeding
- Scripts follow contracts in contracts/script-interfaces.md
- Reference quickstart.md for manual testing workflow
