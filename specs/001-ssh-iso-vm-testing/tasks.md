# Tasks: SSH-Enabled ISO with VM Testing

**Input**: Design documents from `/specs/001-ssh-iso-vm-testing/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Not requested - implementation only

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- Makefile targets at repository root
- Shell scripts in `bin/` directory (if needed for complex logic)
- VM artifacts in `vms/` directory

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify existing infrastructure and prepare for new targets

- [X] T001 Verify existing bin/build-iso script functionality
- [X] T002 Verify existing vms/server.conf quickemu configuration (created)
- [X] T003 Test existing make vm-server target functionality (implemented)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Ensure quickemu and dependencies are available

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Add quickemu prerequisite check to Makefile
- [X] T005 Verify SSH port 22220 availability in environment

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Automated VM Testing Workflow (Priority: P1) 🎯 MVP

**Goal**: Single command to build ISO, launch VM, and provide SSH connection details

**Independent Test**: Run `make vm-test` with SSH key and successfully connect to VM

### Implementation for User Story 1

- [X] T006 [US1] Add vm-test target to Makefile with ISO build integration
- [X] T007 [US1] Implement VM launch logic in vm-test target in Makefile
- [X] T008 [US1] Add SSH readiness check loop to vm-test target in Makefile
- [X] T009 [US1] Add SSH connection display logic to vm-test target in Makefile

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - VM Lifecycle Management (Priority: P2)

**Goal**: Simple commands to manage VM lifecycle without quickemu expertise

**Independent Test**: Start, stop, check status, and clean VM using make targets

### Implementation for User Story 2

- [X] T010 [P] [US2] Add vm-stop target to Makefile with pkill logic
- [X] T011 [P] [US2] Add vm-clean target to Makefile for artifact cleanup
- [X] T012 [US2] Add error handling for VM already running in vm-test target
- [X] T013 [US2] Add force cleanup option handling to vm-clean target in Makefile

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - SSH Connection Helper (Priority: P3)

**Goal**: Automatically display correct SSH connection command

**Independent Test**: Run `make vm-ssh` and get correct connection string

### Implementation for User Story 3

- [X] T014 [US3] Add vm-ssh target to Makefile with connection info display
- [X] T015 [US3] Add environment variable support for custom SSH port in vm-ssh target
- [X] T016 [US3] Update vm-test target to reference vm-ssh for connection display

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and improvements that affect multiple user stories

- [X] T017 [P] Update README.md with VM testing workflow documentation
- [X] T018 [P] Add help text to each Makefile target using ## comments
- [X] T019 Add .PHONY declarations for all new Makefile targets
- [X] T020 Test complete workflow end-to-end with all targets

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Independent of US1
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Benefits from US1 completion but not required

### Within Each User Story

- All tasks within a story are sequential (Makefile targets build on each other)
- Story complete before moving to next priority

### Parallel Opportunities

- Setup tasks T001-T003 are verification only (can be done in parallel)
- User Story 2 tasks T010-T011 marked [P] can run in parallel (different targets)
- Polish tasks T017-T018 marked [P] can run in parallel (different files)
- Different user stories can be worked on in parallel by different team members

---

## Parallel Example: User Story 2

```bash
# Launch both lifecycle management targets together:
Task: "Add vm-stop target to Makefile with pkill logic"
Task: "Add vm-clean target to Makefile for artifact cleanup"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (verify existing infrastructure)
2. Complete Phase 2: Foundational (ensure quickemu available)
3. Complete Phase 3: User Story 1 (vm-test target)
4. **STOP and VALIDATE**: Test vm-test target independently
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo
4. Add User Story 3 → Test independently → Deploy/Demo
5. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (vm-test target)
   - Developer B: User Story 2 (vm-stop, vm-clean targets)
   - Developer C: User Story 3 (vm-ssh target)
3. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files/targets, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Makefile targets are simple - complex logic can be extracted to shell scripts if needed
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: complex bash in Makefile, breaking existing vm-server target