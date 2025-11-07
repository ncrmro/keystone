# Tasks: Hyprland Desktop Environment

**Input**: Design documents from `/home/ncrmro/code/ncrmro/keystone/specs/009-hyprland-desktop/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: Tests are not explicitly requested in the specification. Implementation focuses on manual VM testing per the constitution.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Status**: 42/50 tasks completed (84%) - Implementation complete, VM testing pending

**Testing**: Use `bin/test-deployment` followed by `bin/test-desktop` for automated testing workflow.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- NixOS modules: `modules/client/desktop/`
- Home-manager modules: `home-manager/modules/desktop/hyprland/`
- Documentation: `specs/009-hyprland-desktop/`

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Create directory structure for NixOS desktop modules at modules/client/desktop/
- [x] T002 [P] Create directory structure for home-manager desktop modules at home-manager/modules/desktop/hyprland/
- [x] T003 [P] Review existing modules/client/default.nix to understand integration patterns

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Create base NixOS module skeleton at modules/client/desktop/hyprland.nix with enable option
- [x] T005 [P] Create base home-manager module skeleton at home-manager/modules/desktop/hyprland/default.nix with enable option
- [x] T006 Export new modules in flake.nix nixosModules and homeManagerModules outputs
- [x] T007 Document module options structure in modules/client/desktop/hyprland.nix

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Graphical Session Login (Priority: P1) 🎯 MVP

**Goal**: Enable users to boot the system and log into a Hyprland session via greetd

**Independent Test**: Deploy to VM using bin/virtual-machine, boot, and verify greetd login prompt appears and successfully launches Hyprland session via uwsm

### Implementation for User Story 1

- [x] T008 [P] [US1] Implement greetd service configuration in modules/client/desktop/greetd.nix
- [x] T009 [P] [US1] Configure greetd to launch uwsm for Hyprland in modules/client/desktop/greetd.nix
- [x] T010 [US1] Import greetd module in modules/client/desktop/hyprland.nix
- [x] T011 [US1] Add Hyprland package to system packages in modules/client/desktop/hyprland.nix
- [x] T012 [US1] Configure uwsm integration in home-manager/modules/desktop/hyprland/default.nix
- [x] T013 [US1] Add basic Hyprland configuration in home-manager/modules/desktop/hyprland/default.nix
- [x] T014 [US1] Create test VM configuration at vms/test-hyprland/configuration.nix
- [ ] T015 [US1] Test boot-to-login flow using bin/test-deployment and bin/test-desktop
- [ ] T016 [US1] Verify successful Hyprland session launch via uwsm

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Basic Desktop Interaction (Priority: P2)

**Goal**: Provide a minimal but functional desktop with status bar, notifications, and essential applications

**Independent Test**: After logging in, verify waybar displays, mako shows notifications, and chromium/ghostty can be launched

### Implementation for User Story 2

- [x] T017 [P] [US2] Create waybar configuration module at home-manager/modules/desktop/hyprland/waybar.nix
- [x] T018 [P] [US2] Create mako notification configuration at home-manager/modules/desktop/hyprland/mako.nix
- [x] T019 [P] [US2] Create hyprpaper wallpaper configuration at home-manager/modules/desktop/hyprland/hyprpaper.nix
- [x] T020 [US2] Import waybar, mako, and hyprpaper modules in home-manager/modules/desktop/hyprland/default.nix
- [x] T021 [P] [US2] Add chromium to system packages in modules/client/desktop/packages.nix
- [x] T022 [P] [US2] Add ghostty and essential Hyprland packages to home packages in home-manager/modules/desktop/hyprland/default.nix
- [x] T023 [US2] Add essential Hyprland utilities (hyprshot, hyprpicker, hyprsunset, brightnessctl, pamixer, playerctl, gnome-themes-extra, pavucontrol, wl-clipboard, glib) to home packages
- [x] T024 [US2] Configure waybar to auto-start with Hyprland session
- [x] T025 [US2] Configure mako to auto-start with Hyprland session
- [x] T026 [US2] Configure hyprpaper to auto-start with Hyprland session
- [ ] T027 [US2] Test desktop components using quickstart.md verification steps
- [ ] T028 [US2] Verify all applications launch successfully

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Session Security and Power Management (Priority: P3)

**Goal**: Implement automatic screen locking and power management for session security

**Independent Test**: Leave session idle and verify hyprlock activates automatically, and user can unlock with password

### Implementation for User Story 3

- [x] T029 [P] [US3] Create hyprlock configuration module at home-manager/modules/desktop/hyprland/hyprlock.nix
- [x] T030 [P] [US3] Create hypridle configuration module at home-manager/modules/desktop/hyprland/hypridle.nix
- [x] T031 [US3] Import hyprlock and hypridle modules in home-manager/modules/desktop/hyprland/default.nix
- [x] T032 [P] [US3] Add hyprlock to system packages in modules/client/desktop/packages.nix
- [x] T033 [P] [US3] Add hypridle to system packages in modules/client/desktop/packages.nix
- [x] T034 [US3] Configure hypridle to trigger hyprlock after 5 minutes idle
- [x] T035 [US3] Configure hyprlock with authentication settings
- [ ] T036 [US3] Test idle detection and automatic locking
- [ ] T037 [US3] Verify unlock functionality with password

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T038 [P] Add module documentation comments in modules/client/desktop/hyprland.nix
- [x] T039 [P] Add module documentation comments in home-manager/modules/desktop/hyprland/default.nix
- [x] T040 Ensure minimal configurability per requirement FR-006
- [x] T041 Verify integration with existing terminal-dev-environment module
- [x] T042 Create test VM configuration at vms/test-hyprland/configuration.nix
- [x] T043 Update flake outputs to properly export new modules
- [x] T044 Create bin/test-desktop script for automated desktop testing
- [x] T045 Update quickstart.md with automated testing workflow
- [x] T046 Fix chromium, hyprlock, hypridle package placement (FR-004)
- [x] T047 Fix mako deprecated options to use settings format
- [x] T048 Build and verify configuration compiles successfully
- [ ] T049 Run full quickstart.md validation on VM
- [ ] T050 Verify all success criteria from spec.md are met

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Depends on User Story 1 completion (requires working Hyprland session)
- **User Story 3 (P3)**: Depends on User Story 1 completion (requires working Hyprland session)

### Within Each User Story

- NixOS modules before home-manager modules (system setup enables user config)
- Configuration modules before integration
- Core implementation before testing
- Story complete before moving to next priority

### Parallel Opportunities

- **Setup (Phase 1)**: T002, T003 can run in parallel
- **Foundational (Phase 2)**: T004, T005 can run in parallel
- **User Story 1**: T008, T009 can run in parallel
- **User Story 2**: T017, T018, T019, T021, T022 can run in parallel
- **User Story 3**: T029, T030, T032, T033 can run in parallel
- **Polish**: T038, T039 can run in parallel

---

## Parallel Example: User Story 2

```bash
# Launch all component configurations together:
Task: "Create waybar configuration module at home-manager/modules/desktop/hyprland/waybar.nix"
Task: "Create mako notification configuration at home-manager/modules/desktop/hyprland/mako.nix"
Task: "Create hyprpaper wallpaper configuration at home-manager/modules/desktop/hyprland/hyprpaper.nix"
Task: "Add chromium to system packages in modules/client/desktop/hyprland.nix"
Task: "Add ghostty and essential Hyprland packages to home packages"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently using quickstart.md
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
   - Developer A: User Story 1 (priority)
   - After US1 complete:
     - Developer B: User Story 2
     - Developer C: User Story 3
3. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Use bin/virtual-machine for all VM testing per constitution
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Follow NixOS module standards: use types.attrsOf, enable options, assertions
- Minimize configuration options per FR-006
