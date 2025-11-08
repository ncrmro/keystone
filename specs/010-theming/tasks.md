# Tasks: Dynamic Theming System

**Input**: Design documents from `/specs/010-theming/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not required by specification - manual verification strategy documented in plan.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This is a NixOS home-manager module project:
- `home-manager/modules/omarchy-theming/` - Module implementation
- `flake.nix` - Flake configuration (omarchy input)
- `examples/theming/` - Usage examples
- `docs/modules/` - User documentation

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, flake configuration, and module structure

- [ ] T001 Add omarchy source as flake input in flake.nix
- [ ] T002 [P] Create module directory structure at home-manager/modules/omarchy-theming/
- [ ] T003 [P] Create examples directory at examples/theming/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core module framework that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Create main module file at home-manager/modules/omarchy-theming/default.nix with enable option
- [ ] T005 [P] Create binaries submodule at home-manager/modules/omarchy-theming/binaries.nix for omarchy binary installation
- [ ] T006 [P] Create activation submodule at home-manager/modules/omarchy-theming/activation.nix for symlink management
- [ ] T007 Import omarchy-theming module in home-manager/modules/terminal-dev-environment/default.nix
- [ ] T008 Add module option validation assertions in home-manager/modules/omarchy-theming/default.nix

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Default Theme Installation and Activation (Priority: P1) 🎯 MVP

**Goal**: Install default Omarchy theme and apply it to Helix and Ghostty terminal applications automatically when theming is enabled

**Independent Test**: Enable `programs.omarchy-theming.enable = true`, run `bin/test-home-manager`, verify:
- Default theme files exist in `~/.config/omarchy/themes/default/`
- Active theme symlink exists at `~/.config/omarchy/current/theme`
- Omarchy binaries exist in `~/.local/share/omarchy/bin/` and are in PATH
- Helix displays theme colors when opened
- Ghostty displays theme colors when opened

### Implementation for User Story 1

- [ ] T009 [P] [US1] Implement binary installation logic in home-manager/modules/omarchy-theming/binaries.nix using builtins.readDir
- [ ] T010 [P] [US1] Add PATH configuration for omarchy binaries in home-manager/modules/omarchy-theming/binaries.nix
- [ ] T011 [P] [US1] Install default theme files via home.file in home-manager/modules/omarchy-theming/default.nix
- [ ] T012 [P] [US1] Install omarchy logo.txt via home.file in home-manager/modules/omarchy-theming/default.nix
- [ ] T013 [US1] Implement activation script for initial symlink creation in home-manager/modules/omarchy-theming/activation.nix
- [ ] T014 [US1] Add idempotency check to activation script (skip if symlink exists) in home-manager/modules/omarchy-theming/activation.nix
- [ ] T015 [US1] Create terminal integration submodule at home-manager/modules/omarchy-theming/terminal.nix
- [ ] T016 [US1] Extend Helix configuration to include theme in home-manager/modules/terminal-dev-environment/helix.nix
- [ ] T017 [US1] Extend Ghostty configuration to include theme via config-file directive in home-manager/modules/terminal-dev-environment/ghostty.nix
- [ ] T018 [US1] Add terminal.enable and terminal.applications options in home-manager/modules/omarchy-theming/default.nix
- [ ] T019 [US1] Test default theme installation with bin/test-home-manager script
- [ ] T020 [US1] Verify theme application in Helix and Ghostty manually in VM

**Checkpoint**: At this point, User Story 1 should be fully functional - users can enable theming and see consistent styling in Helix/Ghostty

---

## Phase 4: User Story 2 - Theme Cycling and Switching (Priority: P2)

**Goal**: Enable users to switch between installed themes using omarchy-theme-next command

**Independent Test**: Install a second theme (or use bin/test-home-manager with multiple themes), run `omarchy-theme-next`, restart applications, verify:
- Theme symlink updated to next theme
- Applications display new theme colors
- Desktop notification appears (if desktop environment running)
- Wrapping works (last theme → first theme)

### Implementation for User Story 2

- [ ] T021 [US2] Verify omarchy-theme-next binary is functional (already installed in US1)
- [ ] T022 [US2] Verify omarchy-theme-set binary is functional (already installed in US1)
- [ ] T023 [US2] Test theme switching with multiple themes using omarchy-theme-next command
- [ ] T024 [US2] Verify theme persistence after system rebuild (run home-manager switch, check symlink unchanged)
- [ ] T025 [US2] Test alphabetical ordering and wrap-around behavior with 3+ themes
- [ ] T026 [US2] Verify desktop notifications appear (requires notify-send package)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - themes install and users can switch between them

---

## Phase 5: User Story 4 - Persistent Theme Configuration Across System Rebuilds (Priority: P2)

**Goal**: Ensure user's theme selection persists across system rebuilds without being reset

**Independent Test**: Select non-default theme with `omarchy-theme-set <theme>`, run `nixos-rebuild switch` or `home-manager switch`, verify:
- Active theme symlink still points to selected theme (not reset to default)
- Applications still display selected theme after rebuild
- No warnings or errors during activation

### Implementation for User Story 4

- [ ] T027 [US4] Validate activation script preserves existing symlinks (already implemented in T014)
- [ ] T028 [US4] Test theme persistence across multiple rebuilds with bin/test-home-manager
- [ ] T029 [US4] Verify theme source updates don't affect active selection (update theme files in flake, rebuild, check symlink)
- [ ] T030 [US4] Document symlink preservation behavior in activation script comments

**Checkpoint**: Theme persistence is validated - user preferences survive system updates

---

## Phase 6: User Story 3 - Installing Custom Themes (Priority: P3)

**Goal**: Users can install community themes from Git repositories using omarchy-theme-install

**Independent Test**: Run `omarchy-theme-install https://github.com/catppuccin/omarchy-catppuccin`, verify:
- Theme cloned to `~/.config/omarchy/themes/catppuccin/`
- Theme automatically activated (symlink updated)
- Theme appears in theme list (`ls ~/.config/omarchy/themes/`)
- Applications display new theme after restart

### Implementation for User Story 3

- [ ] T031 [US3] Verify omarchy-theme-install binary is functional (already installed in US1)
- [ ] T032 [US3] Test theme installation from git repository (requires git package available)
- [ ] T033 [US3] Verify theme name extraction from repository URL (test with various naming patterns)
- [ ] T034 [US3] Test overwrite behavior when installing theme with existing name
- [ ] T035 [US3] Verify automatic activation after installation
- [ ] T036 [US3] Test error handling for network failures and invalid repositories

**Checkpoint**: All user stories should now be independently functional - complete theme management workflow works

---

## Phase 7: User Story 5 - Desktop Environment Theme Integration (Priority: P3)

**Goal**: Provide architectural foundation for future Hyprland theming without implementing full functionality

**Independent Test**: Enable `programs.omarchy-theming.desktop.enable = true`, rebuild system, verify:
- No build errors or warnings
- Desktop module loads successfully
- `OMARCHY_THEME_PATH` environment variable is set
- Existing Hyprland functionality unaffected (no regressions)

### Implementation for User Story 5

- [ ] T037 [P] [US5] Create desktop stub module at home-manager/modules/omarchy-theming/desktop.nix
- [ ] T038 [US5] Add desktop.enable option in home-manager/modules/omarchy-theming/default.nix
- [ ] T039 [US5] Export OMARCHY_THEME_PATH environment variable in desktop.nix
- [ ] T040 [US5] Add TODO comments for future Hyprland integration in desktop.nix
- [ ] T041 [US5] Test desktop module enablement without errors
- [ ] T042 [US5] Verify environment variable is available in shell session

**Checkpoint**: Desktop module stub is complete - foundation ready for future Hyprland theming work

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, examples, and improvements that affect multiple user stories

- [ ] T043 [P] Create basic usage example at examples/theming/basic.nix
- [ ] T044 [P] Create custom theme example at examples/theming/custom-theme.nix
- [ ] T045 [P] Create terminal-only example at examples/theming/terminal-only.nix
- [ ] T046 [P] Create user documentation at docs/modules/omarchy-theming.md
- [ ] T047 Add inline code comments documenting activation script behavior
- [ ] T048 Add assertions for missing dependencies (terminal-dev-environment not enabled)
- [ ] T049 Add warning messages for partial configuration (e.g., helix theming without helix enabled)
- [ ] T050 Run quickstart.md validation in VM with bin/virtual-machine
- [ ] T051 Test complete workflow from scratch (fresh install to theme switching)
- [ ] T052 Performance validation (verify <2s theme installation, <1s switching)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - US1 (P1) → US2 (P2) → US4 (P2) → US3 (P3) → US5 (P3) recommended order
  - US1 must complete before US2 (theme switching needs theme installation)
  - US2 and US4 can be validated together (both test theme persistence)
  - US3 and US5 are independent of each other
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories ✅ TRUE MVP
- **User Story 2 (P2)**: Requires US1 complete (needs binaries and default theme installed)
- **User Story 4 (P2)**: Requires US1 complete (validates symlink preservation from US1)
- **User Story 3 (P3)**: Requires US1 complete (uses binaries installed in US1)
- **User Story 5 (P3)**: Can start after Foundational (Phase 2) - Independent of terminal stories

### Within Each User Story

- Binaries must be installed before activation scripts
- Activation scripts must run before application configuration
- Module structure before submodule imports
- Options definition before implementation that uses those options
- Story complete and tested before moving to next priority

### Parallel Opportunities

- **Setup (Phase 1)**: All three tasks (T001, T002, T003) can run in parallel
- **Foundational (Phase 2)**: T005 and T006 can run in parallel (different files)
- **User Story 1**:
  - T009, T010, T011, T012 can run in parallel (different concerns)
  - T016 and T017 can run in parallel (different applications)
- **User Story 5**:
  - T037 and T038 can run in parallel (module creation + option definition)
- **Polish (Phase 8)**: T043, T044, T045, T046 can all run in parallel (different files)

---

## Parallel Example: User Story 1

```bash
# Launch all foundational file creations together:
Task: "Implement binary installation logic in binaries.nix"
Task: "Add PATH configuration in binaries.nix"
Task: "Install default theme files in default.nix"
Task: "Install omarchy logo.txt in default.nix"

# Later, launch all application integrations together:
Task: "Extend Helix configuration in helix.nix"
Task: "Extend Ghostty configuration in ghostty.nix"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only) ⭐ RECOMMENDED

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T008) - CRITICAL
3. Complete Phase 3: User Story 1 (T009-T020)
4. **STOP and VALIDATE**: Test US1 independently with bin/test-home-manager
5. Deploy/demo if ready - **This is a complete, useful feature**

**Value Delivered**: Users have unified theming across Helix and Ghostty automatically

### Incremental Delivery

1. Complete Setup + Foundational → Module structure ready
2. Add User Story 1 → Test independently → **MVP RELEASE** 🎯
3. Add User Story 2 → Test independently → Users can switch themes
4. Add User Story 4 → Validate with US2 → Theme persistence confirmed
5. Add User Story 3 → Test independently → Community theme support
6. Add User Story 5 → Test independently → Desktop foundation ready
7. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (blocks US2, US3, US4)
   - Developer B: User Story 5 (can start immediately, independent)
3. After US1 completes:
   - Developer A: User Story 2
   - Developer B: User Story 3
   - Developer C: User Story 4 (can validate alongside US2)
4. Polish tasks can be distributed in parallel

---

## Notes

### Task Format Notes

- **[P] tasks**: Different files, no dependencies - safe to execute in parallel
- **[Story] label**: Maps task to specific user story for traceability and independent testing
- Each user story should be independently completable and testable
- Commit after each task or logical group of related tasks

### NixOS-Specific Notes

- Testing requires `bin/test-home-manager` for activation validation
- VM testing via `bin/virtual-machine` for integration testing
- No traditional unit tests - validation is declarative build + manual verification
- Activation scripts must be idempotent (can run multiple times safely)
- Symlinks preserved across rebuilds by checking existence before creation

### Research Insights Applied

- **Lazygit deferred**: Not in initial implementation (see research.md for rationale)
- **Helix integration**: Method TBD based on actual theme file structure (may need adjustment during T016)
- **Ghostty integration**: Uses `config-file` directive (clear path forward)
- **Desktop stub only**: Full Hyprland theming is future work (US5 sets foundation)

### Critical Success Factors

1. **Idempotent activation**: T014 must properly check for existing symlinks
2. **Binary discovery**: T009 must use `builtins.readDir` for automatic binary enumeration
3. **Theme persistence**: T027-T030 validate that rebuilds don't reset user choice
4. **Graceful degradation**: Missing theme files shouldn't break applications (tested in T020)
5. **PATH configuration**: T010 must ensure omarchy binaries are accessible to user

### Checkpoint Validation

After each user story phase, validate:
- ✅ Module builds without errors (`nix build`)
- ✅ Activation completes without errors (`bin/test-home-manager`)
- ✅ User story acceptance criteria met (see spec.md)
- ✅ No regressions in previous user stories
- ✅ Independent test passes (documented in phase goal)

---

## Total Task Summary

- **Total Tasks**: 52
- **Setup**: 3 tasks
- **Foundational**: 5 tasks (BLOCKS all user stories)
- **User Story 1 (MVP)**: 12 tasks ⭐
- **User Story 2**: 6 tasks
- **User Story 4**: 4 tasks
- **User Story 3**: 6 tasks
- **User Story 5**: 6 tasks
- **Polish**: 10 tasks
- **Parallel Opportunities**: 18 tasks marked [P]
- **MVP Scope**: Phases 1-3 (20 tasks total for complete, useful feature)
