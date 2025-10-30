# Tasks: Secure Boot Automation with Lanzaboote

**Input**: Design documents from `/specs/003-secureboot-automation/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/test-deployment-cli.md

**Tests**: Not required for this feature (test automation script)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- Single project structure
- Main implementation: `bin/test-deployment`
- Configuration examples: `examples/test-server.nix`
- VM configuration: `vms/server.conf`, `vms/server.conf.example`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Ensure VM firmware and configuration support Secure Boot testing

- [X] T001 Update `vms/server.conf.example` to document OVMF Secure Boot requirements
- [X] T002 [P] Verify OVMF firmware with Secure Boot support is accessible on development machine
- [X] T003 [P] Document VM configuration prerequisites in `specs/003-secureboot-automation/quickstart.md` (already done, verify complete)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core helper functions and state management that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Add TestPhase enum values for Secure Boot phases in `bin/test-deployment`
- [X] T005 [P] Create `check_uefi_mode()` helper function in `bin/test-deployment`
- [X] T006 [P] Create `run_ssh_command()` helper function for remote commands in `bin/test-deployment`
- [X] T007 Update `main()` function to calculate total_steps including Secure Boot phases in `bin/test-deployment`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Automated Secure Boot Enrollment (Priority: P1) 🎯 MVP

**Goal**: Automatically enroll custom Secure Boot keys using lanzaboote after successful ZFS encrypted deployment

**Independent Test**: Run `./bin/test-deployment` and verify:
1. Script detects Secure Boot capability
2. Keys enrolled without manual intervention
3. System boots with Secure Boot enforcing
4. SSH access maintained to deployed system

### Implementation for User Story 1

- [X] T008 [P] [US1] Create `check_secure_boot_capability()` function in `bin/test-deployment`
- [X] T009 [P] [US1] Create `detect_secure_boot_support()` function in `bin/test-deployment`
- [X] T010 [US1] Create `enroll_secure_boot_keys()` function in `bin/test-deployment`
- [X] T011 [US1] Create `trigger_reboot_after_enrollment()` function in `bin/test-deployment`
- [X] T012 [US1] Add Secure Boot capability check phase in `main()` function in `bin/test-deployment`
- [X] T013 [US1] Add Secure Boot enrollment phase in `main()` function in `bin/test-deployment`
- [X] T014 [US1] Add post-enrollment reboot phase in `main()` function in `bin/test-deployment`
- [X] T015 [US1] Update lanzaboote configuration in `examples/test-server.nix`
- [X] T016 [US1] Add logging for all Secure Boot enrollment operations in `bin/test-deployment`

**Checkpoint**: At this point, User Story 1 should be fully functional - automated enrollment working end-to-end

---

## Phase 4: User Story 2 - Automated Post-Enrollment Verification (Priority: P2)

**Goal**: Automatically verify that Secure Boot is properly configured and functional after enrollment

**Independent Test**: Run `./bin/test-deployment` and verify:
1. All verification checks execute
2. Clear pass/fail indicators for each check
3. Detailed error messages if any check fails
4. Script returns appropriate exit code

### Implementation for User Story 2

- [X] T017 [P] [US2] Create `check_secure_boot_status()` function using sysfs in `bin/test-deployment`
- [X] T018 [P] [US2] Create `verify_setup_mode_disabled()` function in `bin/test-deployment`
- [X] T019 [P] [US2] Create `verify_secure_boot_enabled()` function using bootctl in `bin/test-deployment`
- [X] T020 [P] [US2] Create `verify_boot_files_signed()` function using sbctl in `bin/test-deployment`
- [X] T021 [US2] Create `verify_secure_boot()` function that runs all checks in `bin/test-deployment`
- [X] T022 [US2] Add Secure Boot verification phase in `main()` function in `bin/test-deployment`
- [X] T023 [US2] Update existing `verify_deployment()` to include Secure Boot checks in `bin/test-deployment`
- [X] T024 [US2] Add detailed error reporting for failed verification checks in `bin/test-deployment`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - enrollment + verification complete

---

## Phase 5: User Story 3 - Graceful Fallback for Unsupported Hardware (Priority: P3)

**Goal**: Detect when Secure Boot is not supported and skip enrollment gracefully while continuing other tests

**Independent Test**: Run `./bin/test-deployment` on VM without Secure Boot support and verify:
1. Unsupported platform detected early
2. Clear warning message displayed
3. Secure Boot phases skipped
4. Other deployment tests continue normally
5. Final summary indicates Secure Boot was not tested

### Implementation for User Story 3

- [X] T025 [P] [US3] Add `--skip-secureboot` command-line flag parsing in `bin/test-deployment`
- [X] T026 [P] [US3] Create `should_skip_secure_boot()` decision function in `bin/test-deployment`
- [X] T027 [US3] Add fallback logic in Secure Boot capability check phase in `bin/test-deployment`
- [X] T028 [US3] Update phase skip logic in `main()` for unsupported platforms in `bin/test-deployment`
- [X] T029 [US3] Add warning messages for skipped Secure Boot phases in `bin/test-deployment`
- [X] T030 [US3] Update final summary to indicate Secure Boot test status in `bin/test-deployment`
- [X] T031 [US3] Update help text with `--skip-secureboot` option in `bin/test-deployment`

**Checkpoint**: All user stories should now be independently functional - complete graceful handling

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements and documentation that affect multiple user stories

- [X] T032 [P] Add Python type hints to all new functions in `bin/test-deployment`
- [X] T033 [P] Update `specs/003-secureboot-automation/quickstart.md` with final usage examples
- [X] T034 [P] Add examples for all command-line flags in `bin/test-deployment --help` output
- [X] T035 [P] Update CLAUDE.md with Secure Boot automation workflow documentation
- [X] T036 Code cleanup: Extract repeated SSH command patterns into helpers in `bin/test-deployment` (already done - `run_ssh_command_on_vm`)
- [X] T037 Add timeout handling for Secure Boot operations in `bin/test-deployment` (already implemented in all functions)
- [X] T038 Performance: Reduce wait times by checking status instead of fixed delays in `bin/test-deployment` (wait_for_ssh already uses retry logic)
- [X] T039 Validate quickstart.md instructions match actual implementation (validated - all instructions accurate)
- [X] T040 Update contracts/test-deployment-cli.md if any CLI changes were made (no contract changes needed - backward compatible)

---

## Phase 7: End-to-End Secure Boot Validation 🎯 **CRITICAL**

**Purpose**: Validate that Secure Boot actually works end-to-end with real VM

**⚠️ BLOCKER**: This phase MUST be completed before the feature can be considered done. All previous phases only tested the graceful fallback path (`--skip-secureboot`).

### Prerequisites for Testing
- [X] T041 Verify OVMF firmware with Secure Boot support is available at the correct path
- [X] T042 Update `vms/server.conf` to use OVMF with `secureboot="on"` (quickemu syntax)
- [X] T043 Configure `vms/test-server/configuration.nix` to enable lanzaboote module
- [X] T044 Verify `flake.nix` has lanzaboote input configured

### Actual Secure Boot Testing
- [ ] T045 Run `./bin/test-deployment --hard-reset --rebuild-iso` (WITHOUT --skip-secureboot)
- [ ] T046 Verify UEFI Secure Boot capability is detected during deployment
- [ ] T047 Verify Secure Boot keys are enrolled automatically
- [ ] T048 Verify Setup Mode transitions from enabled to disabled
- [ ] T049 Verify all boot files are properly signed by sbctl
- [ ] T050 Verify final summary shows "Secure Boot: Fully configured and functional"
- [ ] T051 SSH into deployed VM and manually verify: `bootctl status | grep "Secure Boot: enabled"`
- [ ] T052 SSH into deployed VM and manually verify: `sbctl status` shows Secure Boot enabled

### Failure Scenarios
- [ ] T053 Test on VM without Secure Boot support and verify graceful skip
- [ ] T054 Verify error messages are clear if Secure Boot enrollment fails
- [ ] T055 Verify script continues to work with both `--skip-secureboot` and without it

**Checkpoint**: ONLY after this phase can the feature be considered complete and ready for production use.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - Can proceed sequentially in priority order (P1 → P2 → P3)
  - Recommended: Complete US1, validate independently, then proceed
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Builds on US1 but enhances it (verification)
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Adds graceful handling to US1/US2

**Note**: While US2 and US3 build on US1 conceptually, they can be developed independently by adding their code paths. US1 provides the core enrollment, US2 adds verification, US3 adds fallback logic.

### Within Each User Story

- Helper functions before main integration
- Core functionality before error handling
- Individual checks before aggregated verification
- Story complete and tested before moving to next priority

### Parallel Opportunities

- **Setup tasks**: T001, T002, T003 can run in parallel
- **Foundational tasks**: T005, T006 can run in parallel (T004, T007 sequential)
- **US1 Implementation**: T008, T009 can run in parallel; T015, T016 can run in parallel
- **US2 Implementation**: T017, T018, T019, T020 can run in parallel (all independent check functions)
- **US3 Implementation**: T025, T026 can run in parallel
- **Polish tasks**: T032, T033, T034, T035 can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch independent helper functions together:
Task: "Create check_secure_boot_capability() function in bin/test-deployment"
Task: "Create detect_secure_boot_support() function in bin/test-deployment"

# Launch documentation updates together:
Task: "Update lanzaboote configuration in examples/test-server.nix"
Task: "Add logging for all Secure Boot enrollment operations in bin/test-deployment"
```

## Parallel Example: User Story 2

```bash
# Launch all verification check functions together:
Task: "Create check_secure_boot_status() function using sysfs in bin/test-deployment"
Task: "Create verify_setup_mode_disabled() function in bin/test-deployment"
Task: "Create verify_secure_boot_enabled() function using bootctl in bin/test-deployment"
Task: "Create verify_boot_files_signed() function using sbctl in bin/test-deployment"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup → VM firmware ready
2. Complete Phase 2: Foundational → Helper functions ready
3. Complete Phase 3: User Story 1 → Enrollment automation working
4. **STOP and VALIDATE**: Run `./bin/test-deployment` and verify enrollment works
5. Deploy/demo basic Secure Boot automation

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → **MVP Ready: Basic enrollment works!**
3. Add User Story 2 → Test independently → **Enhanced: Full verification added!**
4. Add User Story 3 → Test independently → **Production Ready: Graceful handling complete!**
5. Complete Polish → **Polished: Documentation and optimization done!**

### Sequential Implementation (Recommended for Single Developer)

1. Complete Phase 1 (Setup) - ~30 minutes
2. Complete Phase 2 (Foundational) - ~1 hour
3. Complete Phase 3 (US1 - Enrollment) - ~3-4 hours
   - **Validate**: Test enrollment end-to-end
4. Complete Phase 4 (US2 - Verification) - ~2 hours
   - **Validate**: Test all verification checks
5. Complete Phase 5 (US3 - Fallback) - ~1.5 hours
   - **Validate**: Test on unsupported platform
6. Complete Phase 6 (Polish) - ~1-2 hours

**Total Estimated Time**: 10-12 hours of focused development

---

## Notes

- [P] tasks = different functions/files, no dependencies between them
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Main implementation file: `bin/test-deployment` (Python script)
- Test by running: `./bin/test-deployment` or `./bin/test-deployment --skip-secureboot`
- Validation: SSH into VM at `ssh -p 22220 root@localhost` and run `sbctl status`, `bootctl status`
