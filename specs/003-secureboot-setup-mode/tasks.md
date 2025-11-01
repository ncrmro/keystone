# Tasks: Secure Boot Setup Mode for VM Testing

**Input**: Design documents from `/specs/003-secureboot-setup-mode/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are OPTIONAL - only include them if explicitly requested in the feature specification. This feature does not request tests.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- **Script**: `bin/virtual-machine` (Python script using uv shebang)
- **Documentation**: `docs/examples/vm-secureboot-testing.md`
- **VM Files**: `vms/<vm-name>/OVMF_VARS.fd` (NVRAM), `vms/<vm-name>/disk.qcow2` (disk)

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No new infrastructure needed - enhancing existing bin/virtual-machine script

*This phase is minimal as we're enhancing an existing script, not creating new project structure.*

- [X] T001 Review existing bin/virtual-machine script to understand current OVMF firmware discovery and NVRAM initialization logic (bin/virtual-machine:1)

**Checkpoint**: Understanding of current implementation ready for enhancement

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational blocking tasks - this is a single script enhancement with no cross-component dependencies

*This feature has no foundational phase as it's a self-contained enhancement to bin/virtual-machine.*

**Checkpoint**: N/A - Proceed directly to User Story implementation

---

## Phase 3: User Story 1 - Boot VM in Secure Boot Setup Mode (Priority: P1) 🎯 MVP

**Goal**: Enable bin/virtual-machine to create VMs that boot into Secure Boot setup mode, verified with `bootctl status` showing "Secure Boot: disabled (setup)"

**Independent Test**: Create VM with `./bin/virtual-machine --name test-setup --start`, boot from Keystone installer ISO, run `bootctl status` and verify output shows "Secure Boot: disabled (setup)"

### Implementation for User Story 1

- [X] T002 [US1] Add `template` attribute to `<nvram>` XML element in create_uefi_secureboot_vm() function in bin/virtual-machine:186
- [X] T003 [US1] Update existing OVMF firmware detection validation to ensure "secure" is in firmware CODE filename in bin/virtual-machine:167-172
- [X] T004 [P] [US1] Add optional NVRAM validation function validate_nvram_setup_mode() to check file size (540,672 bytes) in bin/virtual-machine (new function after find_ovmf_firmware)
- [X] T005 [P] [US1] Enhance help text in print_connection_commands() to include Secure Boot setup mode verification instructions using `bootctl status` in bin/virtual-machine:429-485
- [X] T006 [P] [US1] Update create_uefi_secureboot_vm() docstring to document setup mode postconditions and bootctl verification method in bin/virtual-machine:98
- [X] T007 [P] [US1] Create comprehensive usage examples documentation in docs/examples/vm-secureboot-testing.md showing VM creation, verification, and common workflows
- [X] T008 [US1] Automated verification: Added `verify_secureboot_setup_mode()` function to bin/test-deployment that runs `bootctl status` and verifies "Secure Boot: disabled (setup)" output

**Checkpoint**: At this point, User Story 1 should be fully functional - VMs boot in setup mode and can be verified with bootctl status

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Optional enhancements and documentation improvements

- [X] T009 [P] Add --reset-setup-mode CLI flag to reset existing VM NVRAM to setup mode (delete NVRAM file) in bin/virtual-machine main() function
- [X] T010 [P] Add NVRAM size validation warning when copying OVMF_VARS template to detect pre-enrolled keys in bin/virtual-machine create_uefi_secureboot_vm() function
- [X] T011 [P] Enhance error message for missing OVMF Secure Boot firmware with specific NixOS remediation steps in bin/virtual-machine:150-155
- [X] T012 [P] Update CLAUDE.md VM Testing section with setup mode verification workflow and bootctl usage
- [X] T013 Automated validation: Verification integrated into bin/test-deployment script - runs automatically when script is executed

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: SKIPPED - No foundational tasks for this feature
- **User Story 1 (Phase 3)**: Can start after Setup (T001) - No dependencies on other stories
- **Polish (Phase 4)**: Depends on User Story 1 completion (T002-T008)

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Setup - Single story feature, no cross-story dependencies

### Within User Story 1

- **T001**: Must complete first (understanding current implementation)
- **T002**: Core XML change - should be done early
- **T003**: Can run in parallel with T002 (different function location)
- **T004-T007**: Can all run in parallel after T002 (independent documentation and validation enhancements)
- **T008**: Must run last (manual verification of entire story)

### Parallel Opportunities

- **After T001**: T002 and T003 can run in parallel
- **After T002**: T004, T005, T006, T007 can all run in parallel
- **Polish Phase**: T009, T010, T011, T012 can all run in parallel, T013 runs last

---

## Parallel Example: User Story 1

```bash
# After completing T001 (understanding current code):
# Launch T002 and T003 together:
Task: "Add template attribute to <nvram> XML element in bin/virtual-machine:186"
Task: "Update OVMF firmware detection validation in bin/virtual-machine:167-172"

# After completing T002 (core XML change):
# Launch all documentation and enhancement tasks together:
Task: "Add validate_nvram_setup_mode() function in bin/virtual-machine"
Task: "Enhance help text with verification instructions in bin/virtual-machine:429-485"
Task: "Update create_uefi_secureboot_vm() docstring in bin/virtual-machine:98"
Task: "Create docs/examples/vm-secureboot-testing.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 3: User Story 1 (T002-T008)
3. **STOP and VALIDATE**: Test User Story 1 independently with manual verification
4. Deploy/demo if ready
5. Optional: Add Polish phase enhancements

### Task Breakdown Rationale

**Why Minimal Setup Phase**:
- Enhancing existing script, not creating new infrastructure
- Only need to understand current implementation (T001)

**Why No Foundational Phase**:
- Single script modification with no cross-component dependencies
- No blocking prerequisites that would prevent story implementation

**Why Single User Story**:
- Feature specification has only one user story (P1)
- All requirements map to this single story
- No need for multi-story organization

**Why Small Task Count**:
- Most changes are minor enhancements to existing code
- Core change is 1 line (add `template` attribute to XML)
- Other tasks are documentation, validation, and help text improvements

### Critical Path

```
T001 (Setup) → T002 (Core XML change) → T008 (Verification) → Done
```

**Minimum Viable Implementation**: T001 + T002 + T008 (3 tasks)
**Full Feature**: All tasks T001-T013 (13 tasks)

---

## Notes

- **[P] tasks** = different files/functions, no dependencies - can run in parallel
- **[US1] label** = maps task to User Story 1 for traceability
- User Story 1 is independently completable and testable
- Commit after each task or logical group
- Stop at checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts (all tasks specify exact line numbers or function names)

**File Path Specificity**:
- Every task includes exact file path
- Line numbers provided where applicable (e.g., bin/virtual-machine:186)
- New files clearly marked (e.g., docs/examples/vm-secureboot-testing.md)

**Testing Note**:
- No automated tests requested in specification
- Manual verification sufficient (T008)
- `bootctl status` is the verification method per spec requirements

**Documentation First**:
- T007 creates comprehensive examples before polish phase
- Quickstart validation (T013) ensures docs are accurate
- Help text updates (T005) embedded in main implementation
