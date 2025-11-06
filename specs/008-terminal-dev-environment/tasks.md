# Tasks: Terminal Development Environment Module

**Input**: Design documents from `/specs/008-terminal-dev-environment/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: No test tasks included - manual integration testing via VM will be used per research.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- **Home-manager module**: `home-manager/modules/terminal-dev-environment/`
- **Examples**: `examples/`
- **Documentation**: `docs/modules/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create module directory structure per plan.md

- [ ] T001 Create home-manager module directory at home-manager/modules/terminal-dev-environment/
- [ ] T002 Create examples directory for usage demonstrations
- [ ] T003 [P] Create docs directory at docs/modules/ for module documentation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core module orchestration that MUST be complete before ANY tool-specific implementation

**⚠️ CRITICAL**: No tool implementation can begin until this phase is complete

- [ ] T004 Create main module orchestrator in home-manager/modules/terminal-dev-environment/default.nix with module structure (imports, options, config sections)
- [ ] T005 Define top-level enable option in home-manager/modules/terminal-dev-environment/default.nix using lib.mkEnableOption
- [ ] T006 Define tools category toggles (git, editor, shell, multiplexer, terminal) in home-manager/modules/terminal-dev-environment/default.nix
- [ ] T007 Define extraPackages option in home-manager/modules/terminal-dev-environment/default.nix using lib.mkOption with list type
- [ ] T008 Add meta.maintainers section to home-manager/modules/terminal-dev-environment/default.nix

**Checkpoint**: Foundation ready - tool implementation can now begin in parallel

---

## Phase 3: User Story 1 - Enable Terminal Development Environment (Priority: P1) 🎯 MVP

**Goal**: A developer can enable a complete terminal development stack (helix, git, zsh, zellij, lazygit, ghostty) with a single module import, getting all tools installed and configured with sensible defaults

**Independent Test**: Enable module in home-manager configuration, rebuild, verify all tools available in PATH and configured correctly (can be tested in VM using bin/virtual-machine)

### Implementation for User Story 1

#### Git Configuration (Entity: GitConfig)
- [ ] T009 [P] [US1] Create git sub-module in home-manager/modules/terminal-dev-environment/git.nix with programs.git configuration
- [ ] T010 [P] [US1] Configure Git LFS support in home-manager/modules/terminal-dev-environment/git.nix (enableLfs = true)
- [ ] T011 [P] [US1] Add Git aliases (s, f, p, b, st, co, c) in home-manager/modules/terminal-dev-environment/git.nix using lib.mkDefault
- [ ] T012 [P] [US1] Configure git extraConfig (push.autoSetupRemote, init.defaultBranch) in home-manager/modules/terminal-dev-environment/git.nix

#### Lazygit Configuration (Entity: LazygitConfig)
- [ ] T013 [P] [US1] Add lazygit package installation in home-manager/modules/terminal-dev-environment/git.nix when tools.git enabled
- [ ] T014 [P] [US1] Enable programs.lazygit in home-manager/modules/terminal-dev-environment/git.nix using lib.mkDefault

#### Helix Editor Configuration (Entity: HelixConfig)
- [ ] T015 [P] [US1] Create helix sub-module in home-manager/modules/terminal-dev-environment/helix.nix with programs.helix configuration
- [ ] T016 [P] [US1] Configure helix editor settings (line-number: relative, mouse: true, cursor-shape) in home-manager/modules/terminal-dev-environment/helix.nix using lib.mkDefault
- [ ] T017 [P] [US1] Add essential language server packages (bash-language-server, yaml-language-server, dockerfile-language-server-nodejs, vscode-langservers-extracted, marksman, nixfmt) to home.packages in home-manager/modules/terminal-dev-environment/helix.nix
- [ ] T018 [P] [US1] Configure helix language servers in programs.helix.languages.language-server section in home-manager/modules/terminal-dev-environment/helix.nix
- [ ] T019 [P] [US1] Configure helix language configurations in programs.helix.languages.language array in home-manager/modules/terminal-dev-environment/helix.nix for nix, bash, yaml, dockerfile, json, markdown
- [ ] T020 [P] [US1] Set EDITOR and VISUAL environment variables to "hx" in home-manager/modules/terminal-dev-environment/helix.nix

#### Zsh Shell Configuration (Entity: ZshConfig)
- [ ] T021 [P] [US1] Create zsh sub-module in home-manager/modules/terminal-dev-environment/zsh.nix with programs.zsh configuration
- [ ] T022 [P] [US1] Enable zsh with completion, autosuggestion, and syntax highlighting in home-manager/modules/terminal-dev-environment/zsh.nix
- [ ] T023 [P] [US1] Configure oh-my-zsh with plugins (git, colored-man-pages) and robbyrussell theme in home-manager/modules/terminal-dev-environment/zsh.nix using lib.mkDefault
- [ ] T024 [P] [US1] Add shell aliases (l, ls, grep, g, lg, hx) in home-manager/modules/terminal-dev-environment/zsh.nix using lib.mkDefault
- [ ] T025 [P] [US1] Enable and configure starship prompt in home-manager/modules/terminal-dev-environment/zsh.nix using lib.mkDefault
- [ ] T026 [P] [US1] Enable and configure zoxide with zsh integration in home-manager/modules/terminal-dev-environment/zsh.nix using lib.mkDefault
- [ ] T027 [P] [US1] Enable and configure direnv with nix-direnv and zsh integration in home-manager/modules/terminal-dev-environment/zsh.nix using lib.mkDefault
- [ ] T028 [P] [US1] Add utility packages (eza, ripgrep, tree, jq, htop) to home.packages in home-manager/modules/terminal-dev-environment/zsh.nix

#### Zellij Multiplexer Configuration (Entity: ZellijConfig)
- [ ] T029 [P] [US1] Create zellij sub-module in home-manager/modules/terminal-dev-environment/zellij.nix with programs.zellij configuration
- [ ] T030 [P] [US1] Configure zellij settings (theme: tokyo-night-dark, startup_tips: false) in home-manager/modules/terminal-dev-environment/zellij.nix using lib.mkDefault
- [ ] T031 [P] [US1] Disable zellij zsh integration (enableZshIntegration = false) in home-manager/modules/terminal-dev-environment/zellij.nix to avoid auto-nesting

#### Ghostty Terminal Configuration (Entity: GhosttyConfig)
- [ ] T032 [P] [US1] Create ghostty sub-module in home-manager/modules/terminal-dev-environment/ghostty.nix with programs.ghostty configuration
- [ ] T033 [P] [US1] Enable ghostty zsh integration in home-manager/modules/terminal-dev-environment/ghostty.nix using lib.mkDefault
- [ ] T034 [P] [US1] Add empty settings attrset in home-manager/modules/terminal-dev-environment/ghostty.nix for user overrides

#### Module Orchestration
- [ ] T035 [US1] Import all tool sub-modules (git.nix, helix.nix, zsh.nix, zellij.nix, ghostty.nix) in home-manager/modules/terminal-dev-environment/default.nix
- [ ] T036 [US1] Add conditional configs using lib.mkIf for each tool toggle (tools.git, tools.editor, tools.shell, tools.multiplexer, tools.terminal) in home-manager/modules/terminal-dev-environment/default.nix
- [ ] T037 [US1] Add extraPackages to home.packages in home-manager/modules/terminal-dev-environment/default.nix config section

#### Documentation & Examples
- [ ] T038 [P] [US1] Create basic usage example in examples/terminal-dev-environment-example.nix showing minimal configuration with all defaults
- [ ] T039 [P] [US1] Create module documentation in docs/modules/terminal-dev-environment.md with option descriptions and quickstart

#### Integration Testing (bin/test-home-manager script)
- [ ] T040 [US1] Create bin/test-home-manager self-contained test script following bin/test-deployment pattern (Python, colored output, checks array)
- [ ] T041 [US1] Create testuser home-manager configuration in vms/test-server/home-manager/home.nix importing terminal-dev-environment module with git identity
- [ ] T042 [US1] Implement home-manager installation logic in bin/test-home-manager (nix-channel add/update, nix-shell install)
- [ ] T043 [US1] Implement config copy and home-manager switch in bin/test-home-manager (copy to ~/.config/home-manager/, run switch as testuser)
- [ ] T044 [US1] Implement verification checks in bin/test-home-manager (tools in PATH, zsh default, helix LSPs, lazygit, zellij theme, aliases, starship, zoxide)
- [ ] T045 [US1] Add call to bin/test-home-manager in bin/test-deployment main() after ZFS user permissions check (new step in workflow)

**Checkpoint**: User Story 1 complete - full terminal development environment functional with single enable = true, verified via bin/test-home-manager script as non-root testuser

---

## Phase 4: User Story 2 - Customize Configuration (Priority: P2)

**Goal**: A developer can override specific tool configurations (helix theme, zsh aliases, git settings) while keeping other defaults from the module intact

**Independent Test**: Override a single option (e.g., helix theme), rebuild, verify only that setting changed while others remain as module defaults

### Implementation for User Story 2

- [ ] T047 [P] [US2] Add example configuration in examples/terminal-dev-environment-example.nix showing selective tool disabling (tools.multiplexer = false)
- [ ] T048 [P] [US2] Add example configuration in examples/terminal-dev-environment-example.nix showing helix theme override (programs.helix.settings.theme = "gruvbox")
- [ ] T049 [P] [US2] Add example configuration in examples/terminal-dev-environment-example.nix showing custom zsh aliases (vim = "helix")
- [ ] T050 [P] [US2] Add example configuration in examples/terminal-dev-environment-example.nix showing git SSH signing configuration
- [ ] T051 [P] [US2] Add example configuration in examples/terminal-dev-environment-example.nix showing extraPackages usage (ripgrep, fd, bat)
- [ ] T052 [US2] Update documentation in docs/modules/terminal-dev-environment.md with customization examples and lib.mkDefault explanation
- [ ] T053 [US2] Test configuration override: enable module, override helix theme, verify theme changes but other settings remain default
- [ ] T054 [US2] Test configuration override: add custom zsh alias, verify both custom and default aliases available
- [ ] T055 [US2] Test configuration override: disable tools.multiplexer, verify zellij not installed but other tools work
- [ ] T056 [US2] Test extraPackages: add custom packages, verify they're available in environment

**Checkpoint**: User Story 2 complete - users can customize module while maintaining sensible defaults

---

## Phase 5: User Story 3 - Integration with Existing Keystone Modules (Priority: P3)

**Goal**: Terminal development environment works seamlessly with Keystone's client module, with ghostty as default terminal for Hyprland and works standalone on headless servers

**Independent Test**: Enable both client and terminal-dev-environment modules, open terminal in Hyprland, verify ghostty launches with zsh

### Implementation for User Story 3

- [ ] T057 [P] [US3] Add example configuration in examples/terminal-dev-environment-with-client.nix showing integration with keystone.client module
- [ ] T058 [P] [US3] Add TERMINAL environment variable configuration to examples showing home.sessionVariables.TERMINAL = "ghostty"
- [ ] T059 [P] [US3] Add example configuration in examples/terminal-dev-environment-server.nix showing headless server usage (tools.terminal = false)
- [ ] T060 [US3] Update documentation in docs/modules/terminal-dev-environment.md with Keystone client integration section
- [ ] T061 [US3] Update documentation in docs/modules/terminal-dev-environment.md with headless server usage section
- [ ] T062 [US3] Test desktop integration: enable client + terminal-dev-environment modules, verify ghostty as $TERMINAL
- [ ] T063 [US3] Test desktop integration: open terminal via Hyprland (Super+Enter), verify ghostty launches with zsh
- [ ] T064 [US3] Test headless server: disable tools.terminal, SSH into system, verify zsh is default with all other tools available

**Checkpoint**: User Story 3 complete - module integrates with Keystone client and works on servers

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Finalize documentation, handle edge cases, optimize module

- [ ] T065 [P] Add assertions in home-manager/modules/terminal-dev-environment/default.nix for conflicting options validation
- [ ] T066 [P] Add module option documentation using mkOption description fields throughout all sub-modules
- [ ] T067 [P] Update main README or integration guide in docs/ with terminal-dev-environment module information
- [ ] T068 [P] Add edge case handling documentation in docs/modules/terminal-dev-environment.md (conflicting configs, missing packages, SSH keys)
- [ ] T069 Run quickstart.md validation - follow quickstart guide end-to-end in fresh VM
- [ ] T070 Performance test: measure module evaluation time (should be <5 seconds per plan.md)
- [ ] T071 Performance test: measure first shell startup time (should be <2 seconds per plan.md)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational (Phase 2) completion
  - User Story 1 (P1) - MVP: Can start after Foundational - No dependencies on other stories
  - User Story 2 (P2): Can start after User Story 1 completion (needs examples from US1)
  - User Story 3 (P3): Can start after User Story 1 completion (needs base module from US1)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Foundation complete → Independent implementation → MVP ready
- **User Story 2 (P2)**: US1 complete → Adds customization examples → Independently testable
- **User Story 3 (P3)**: US1 complete → Adds integration examples → Independently testable

### Within Each User Story

For User Story 1:
1. Foundation from Phase 2 must be complete
2. All tool sub-modules marked [P] can be created in parallel:
   - T009-T014 (Git + Lazygit)
   - T015-T020 (Helix)
   - T021-T028 (Zsh)
   - T029-T031 (Zellij)
   - T032-T034 (Ghostty)
3. After tool sub-modules complete: T035-T037 (orchestration)
4. Documentation T038-T039 can be done in parallel with orchestration
5. Integration testing T040-T046 done sequentially after implementation

For User Story 2:
1. US1 must be complete
2. All example additions T047-T051 marked [P] can be done in parallel
3. Documentation T052 after examples
4. Testing T053-T056 done sequentially

For User Story 3:
1. US1 must be complete
2. All example files T057-T059 marked [P] can be done in parallel
3. Documentation T060-T061 can be done in parallel with examples
4. Testing T062-T064 done sequentially

### Parallel Opportunities

**Within Setup (Phase 1):**
- T002 and T003 can run in parallel (different directories)

**Within Foundational (Phase 2):**
- All tasks sequential (same file: default.nix)

**Within User Story 1 (Phase 3):**
- Parallel batch 1: T009-T034 (all tool sub-modules, different files)
- Parallel batch 2: T038-T039 (documentation, different files)

**Within User Story 2 (Phase 4):**
- Parallel batch: T047-T051 (example configurations)

**Within User Story 3 (Phase 5):**
- Parallel batch 1: T057-T059 (example files)
- Parallel batch 2: T060-T061 (documentation sections)

**Within Polish (Phase 6):**
- T065-T068 can all run in parallel (different concerns)

---

## Parallel Example: User Story 1 Tool Sub-Modules

```bash
# Launch all tool sub-module implementations together:
Task: "Create git sub-module in home-manager/modules/terminal-dev-environment/git.nix"
Task: "Create helix sub-module in home-manager/modules/terminal-dev-environment/helix.nix"
Task: "Create zsh sub-module in home-manager/modules/terminal-dev-environment/zsh.nix"
Task: "Create zellij sub-module in home-manager/modules/terminal-dev-environment/zellij.nix"
Task: "Create ghostty sub-module in home-manager/modules/terminal-dev-environment/ghostty.nix"

# These can all be worked on simultaneously as they're separate files with no interdependencies
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003) - ~5 minutes
2. Complete Phase 2: Foundational (T004-T008) - ~30 minutes
   - CHECKPOINT: Foundation ready
3. Complete Phase 3: User Story 1 (T009-T046) - ~4-6 hours
   - Tool sub-modules in parallel: ~2-3 hours
   - Orchestration: ~30 minutes
   - Documentation: ~1 hour
   - Testing: ~1-2 hours
4. **STOP and VALIDATE**: Test User Story 1 independently in VM
5. **MVP COMPLETE**: Users can enable full terminal dev environment with single import

Total MVP time: ~5-7 hours for a complete, functional terminal development environment module

### Incremental Delivery

1. **Milestone 1** (MVP): Setup + Foundational + User Story 1
   - Deliverable: Working terminal dev environment module
   - Value: Users get complete opinionated setup out-of-box
   - Test: Enable module, rebuild, use all tools

2. **Milestone 2**: Add User Story 2
   - Deliverable: Customization examples and documentation
   - Value: Users can tailor environment to preferences
   - Test: Override configs, verify defaults + overrides work

3. **Milestone 3**: Add User Story 3
   - Deliverable: Integration with Keystone ecosystem
   - Value: Seamless desktop integration and server usage
   - Test: Use with client module, test on headless server

4. **Milestone 4**: Polish
   - Deliverable: Production-ready module
   - Value: Edge cases handled, optimized, documented
   - Test: Full quickstart validation, performance checks

### Parallel Team Strategy

With 2 developers after Foundational phase:

**Developer A**: User Story 1 core tools
- T009-T020 (Git, Lazygit, Helix)
- T035-T037 (Orchestration)
- T040-T046 (Testing)

**Developer B**: User Story 1 shell environment
- T021-T034 (Zsh, Zellij, Ghostty)
- T038-T039 (Documentation)

Both complete in parallel, integrate at T035.

---

## Notes

- [P] tasks = different files, no dependencies - can run in parallel
- [Story] label maps task to specific user story (US1, US2, US3) for traceability
- Each user story independently testable - can stop after any story and have working feature
- All defaults use lib.mkDefault for user overrideability per research.md
- Manual VM testing using existing bin/virtual-machine infrastructure per research.md
- Module follows home-manager best practices per research.md (enable options, package options, type safety)
- Each checkpoint represents a fully functional, testable increment
- Commit after completing each tool sub-module or logical group
- Stop at any checkpoint to validate story works independently

---

## Total Task Count: 77 tasks

**By Phase:**
- Phase 1 (Setup): 3 tasks
- Phase 2 (Foundational): 5 tasks
- Phase 3 (User Story 1 - MVP): 44 tasks (includes bin/test-home-manager script)
- Phase 4 (User Story 2): 10 tasks
- Phase 5 (User Story 3): 8 tasks
- Phase 6 (Polish): 7 tasks

**Parallel Opportunities:** 35 tasks marked [P] can run in parallel within their phase

**MVP Scope:** Phases 1-3 (52 tasks) delivers complete working terminal development environment, fully tested via bin/test-home-manager script as non-root user
