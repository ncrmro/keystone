# Tasks: TUI Local Installer

**Input**: Design documents from `/specs/011-tui-local-installer/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Manual VM testing only (no automated unit tests per spec)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **TUI Source**: `packages/keystone-installer-ui/src/`
- **NixOS Modules**: `modules/`
- **Documentation**: `docs/`
- **Contracts (reference)**: `specs/011-tui-local-installer/contracts/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and shared TypeScript types

- [X] T001 Create shared types file at `packages/keystone-installer-ui/src/types.ts` with all interfaces from data-model.md (BlockDevice, NetworkInterface, InstallationState, etc.)
- [X] T002 [P] Add DEV_MODE constant and CONFIG_BASE_PATH to types.ts for dev mode support
- [X] T003 [P] Add jq package to `modules/iso-installer.nix` environment.systemPackages
- [X] T004 [P] Add tpm2-tools package to `modules/iso-installer.nix` environment.systemPackages

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core modules that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Create disk.ts module at `packages/keystone-installer-ui/src/disk.ts` with detectDisks(), getByIdPath(), formatDiskSize(), hasTPM2() functions per contracts/disk-operations.ts
- [X] T006 [P] Create config-generator.ts module at `packages/keystone-installer-ui/src/config-generator.ts` with validateHostname(), validateUsername() functions per contracts/config-generator.ts
- [X] T007 [P] Create installation.ts module at `packages/keystone-installer-ui/src/installation.ts` with logOperation(), DEV_MODE constants per contracts/installation.ts
- [X] T008 Add new Screen types to App.tsx: 'method-selection', 'disk-selection', 'disk-confirmation', 'encryption-choice', 'hostname-input', 'username-input', 'password-input', 'system-type-selection', 'repository-url', 'repository-cloning', 'host-selection', 'installing', 'summary', 'complete', 'error' at `packages/keystone-installer-ui/src/App.tsx`
- [X] T009 Add state variables to App.tsx for installation flow: selectedMethod, selectedDisk, encryptionChoice, hostname, username, password, systemType, repositoryUrl, clonedHosts, fileOperations, installProgress, installError

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Network Setup and Status Display (Priority: P1) 🎯 MVP

**Goal**: User boots ISO and sees network status with IP addresses. Can configure WiFi if needed.

**Independent Test**: Boot ISO in VM, verify network detection displays correctly within 5 seconds. Test WiFi setup flow if no Ethernet.

**Note**: This functionality already exists in current App.tsx. Tasks verify it works and ensure smooth transition to new screens.

### Implementation for User Story 1

- [X] T010 [US1] Verify existing network detection in App.tsx correctly shows "Network Connected" with interface name and IP within 5 seconds at `packages/keystone-installer-ui/src/App.tsx`
- [X] T011 [US1] Verify WiFi setup flow works: scan networks, select SSID, enter password, connect at `packages/keystone-installer-ui/src/App.tsx`
- [X] T012 [US1] Modify 'ethernet-connected' screen to show "Continue to Installation" button instead of only showing SSH command at `packages/keystone-installer-ui/src/App.tsx`
- [X] T013 [US1] Modify 'wifi-connected' screen to show "Continue to Installation" button at `packages/keystone-installer-ui/src/App.tsx`

**Checkpoint**: User Story 1 complete - Network setup displays correctly, user can proceed to method selection

---

## Phase 4: User Story 2 - Installation Method Selection (Priority: P1) 🎯 MVP

**Goal**: User sees three installation options with descriptions and can select one.

**Independent Test**: Navigate to method selection, verify all three options display with descriptions. Select each and verify correct next screen loads.

### Implementation for User Story 2

- [X] T014 [US2] Implement 'method-selection' screen with three SelectInput options: "Remote via SSH", "Local installation", "Clone from repository" at `packages/keystone-installer-ui/src/App.tsx`
- [X] T015 [US2] Add descriptions for each method explaining when to use it at `packages/keystone-installer-ui/src/App.tsx`
- [X] T016 [US2] Handle "Remote via SSH" selection: transition to screen showing nixos-anywhere command with current IP at `packages/keystone-installer-ui/src/App.tsx`
- [X] T017 [US2] Handle "Local installation" selection: transition to 'disk-selection' screen at `packages/keystone-installer-ui/src/App.tsx`
- [X] T018 [US2] Handle "Clone from repository" selection: transition to 'repository-url' screen at `packages/keystone-installer-ui/src/App.tsx`

**Checkpoint**: User Story 2 complete - All three installation methods accessible from TUI

---

## Phase 5: User Story 3 - Local Installation with Disk Selection (Priority: P2)

**Goal**: User selects a target disk, chooses encryption preference, and confirms destructive operation.

**Independent Test**: Select "Local installation", verify disk list shows all devices with size/model. Select disk, verify encryption choice and warning appear.

### Implementation for User Story 3

- [X] T019 [US3] Implement 'disk-selection' screen that calls detectDisks() and displays SelectInput list with disk name, size, model at `packages/keystone-installer-ui/src/App.tsx`
- [X] T020 [US3] Show warning icon for disks with hasData=true in disk list at `packages/keystone-installer-ui/src/App.tsx`
- [X] T021 [US3] Implement 'disk-confirmation' screen showing selected disk details and requiring explicit "Yes, erase this disk" confirmation at `packages/keystone-installer-ui/src/App.tsx`
- [X] T022 [US3] Implement 'encryption-choice' screen with SelectInput for "Encrypted (ZFS + TPM2)" vs "Unencrypted (ext4)" at `packages/keystone-installer-ui/src/App.tsx`
- [X] T023 [US3] Call hasTPM2() when encrypted is selected; if false, show warning about password-only fallback and require acknowledgment at `packages/keystone-installer-ui/src/App.tsx`
- [X] T024 [US3] Implement formatDiskEncrypted() in disk.ts using disko module pattern from modules/disko-single-disk-root/ at `packages/keystone-installer-ui/src/disk.ts`
- [X] T025 [US3] Implement formatDiskUnencrypted() in disk.ts using parted/mkfs commands at `packages/keystone-installer-ui/src/disk.ts`
- [X] T026 [US3] Implement mountFilesystems() and unmountFilesystems() in disk.ts at `packages/keystone-installer-ui/src/disk.ts`

**Checkpoint**: User Story 3 complete - Disk selection and formatting flow works in dev mode

---

## Phase 6: User Story 4 - Host Configuration Creation (Priority: P2)

**Goal**: User enters hostname, username, password, system type. Installer creates configuration files and shows each file operation.

**Independent Test**: Complete disk selection, enter valid hostname/username/password, select system type. Verify files created in /tmp/keystone-dev/ (dev mode) or /mnt (real mode).

### Implementation for User Story 4

- [X] T027 [US4] Implement 'hostname-input' screen with TextInput and real-time validation using validateHostname() at `packages/keystone-installer-ui/src/App.tsx`
- [X] T028 [US4] Implement 'username-input' screen with TextInput and real-time validation using validateUsername() at `packages/keystone-installer-ui/src/App.tsx`
- [X] T029 [US4] Implement 'password-input' screen with masked TextInput, require confirmation entry at `packages/keystone-installer-ui/src/App.tsx`
- [X] T030 [US4] Implement 'system-type-selection' screen with SelectInput for "Server" vs "Client (Hyprland desktop)" at `packages/keystone-installer-ui/src/App.tsx`
- [X] T031 [US4] Implement generateFlakeNix() in config-generator.ts producing valid flake.nix content at `packages/keystone-installer-ui/src/config-generator.ts`
- [X] T032 [US4] Implement generateHostDefaultNix() in config-generator.ts producing hosts/{hostname}/default.nix at `packages/keystone-installer-ui/src/config-generator.ts`
- [X] T033 [US4] Implement generateDiskConfigEncrypted() in config-generator.ts producing disk-config.nix for ZFS at `packages/keystone-installer-ui/src/config-generator.ts`
- [X] T034 [US4] Implement generateDiskConfigUnencrypted() in config-generator.ts producing disk-config.nix for ext4 at `packages/keystone-installer-ui/src/config-generator.ts`
- [X] T035 [US4] Implement generateHardwareConfig() in config-generator.ts calling nixos-generate-config at `packages/keystone-installer-ui/src/config-generator.ts`
- [X] T036 [US4] Implement generateConfiguration() in config-generator.ts orchestrating all file generation at `packages/keystone-installer-ui/src/config-generator.ts`
- [X] T037 [US4] Implement initGitRepository() in config-generator.ts running git init and initial commit at `packages/keystone-installer-ui/src/config-generator.ts`

**Checkpoint**: User Story 4 complete - Config files generate correctly, can be inspected in /tmp/keystone-dev/

---

## Phase 7: User Story 5 - Clone from Existing Repository (Priority: P3)

**Goal**: User clones existing git repo and selects a host configuration to deploy.

**Independent Test**: Select "Clone from repository", enter valid git URL, verify clone succeeds and host list appears.

### Implementation for User Story 5

- [X] T038 [US5] Implement 'repository-url' screen with TextInput for git URL and validation using validateGitUrl() at `packages/keystone-installer-ui/src/App.tsx`
- [X] T039 [US5] Implement 'repository-cloning' screen showing Spinner during git clone at `packages/keystone-installer-ui/src/App.tsx`
- [X] T040 [US5] Implement cloneRepository() in installation.ts supporting HTTPS and SSH URLs at `packages/keystone-installer-ui/src/installation.ts`
- [X] T041 [US5] Implement scanForHosts() in installation.ts to find hosts/ directory and list available hosts at `packages/keystone-installer-ui/src/installation.ts`
- [X] T042 [US5] Implement 'host-selection' screen with SelectInput showing available hosts from cloned repo at `packages/keystone-installer-ui/src/App.tsx`
- [X] T043 [US5] Handle clone errors with actionable messages (network error, auth failed, invalid URL) at `packages/keystone-installer-ui/src/App.tsx`

**Checkpoint**: User Story 5 complete - Clone workflow functions with dev mode

---

## Phase 8: User Story 6 - File Operations Transparency (Priority: P3)

**Goal**: All file operations displayed to user with path and purpose. Summary screen shows all operations.

**Independent Test**: Complete any installation flow, verify each file operation logged and displayed. Check summary lists all files.

### Implementation for User Story 6

- [X] T044 [US6] Implement FileOperationDisplay component showing timestamp, action icon, path, purpose at `packages/keystone-installer-ui/src/App.tsx`
- [X] T045 [US6] Update all file-writing functions to call logOperation() callback at `packages/keystone-installer-ui/src/config-generator.ts`
- [X] T046 [US6] Display FileOperation log in 'installing' screen as operations occur at `packages/keystone-installer-ui/src/App.tsx`
- [X] T047 [US6] Implement 'summary' screen showing all configuration choices and file operations list at `packages/keystone-installer-ui/src/App.tsx`
- [X] T048 [US6] Add "View details" / "Confirm reboot" options to summary screen at `packages/keystone-installer-ui/src/App.tsx`

**Checkpoint**: User Story 6 complete - Full transparency into file operations

---

## Phase 9: Installation Orchestration

**Goal**: Wire together disk formatting, config generation, nixos-install, and config copy into complete flow.

**Independent Test**: Run full local installation in VM (not dev mode). Verify system boots and nixos-rebuild works.

### Implementation for Installation Orchestration

- [X] T049 Implement 'installing' screen with progress phases: Partitioning → Formatting → Mounting → Config → Installing → Copying at `packages/keystone-installer-ui/src/App.tsx`
- [X] T050 Implement runInstallation() in installation.ts orchestrating full installation flow at `packages/keystone-installer-ui/src/installation.ts`
- [X] T051 Implement partitionDisk() in installation.ts calling disk.ts functions at `packages/keystone-installer-ui/src/installation.ts`
- [X] T052 Implement runNixosInstall() in installation.ts executing nixos-install --flake command at `packages/keystone-installer-ui/src/installation.ts`
- [X] T053 Implement copyConfigToInstalled() in installation.ts copying config from /tmp to /mnt/home/{user}/ at `packages/keystone-installer-ui/src/installation.ts`
- [X] T054 Implement cleanup() in installation.ts unmounting filesystems at `packages/keystone-installer-ui/src/installation.ts`
- [X] T055 Implement 'complete' screen with success message and "Reboot now" button at `packages/keystone-installer-ui/src/App.tsx`
- [X] T056 Implement 'error' screen with error details, suggestion, and retry/abort options at `packages/keystone-installer-ui/src/App.tsx`

**Checkpoint**: Full installation flow works end-to-end

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, edge cases, and final polish

- [X] T057 [P] Implement back navigation (Escape key or "Back" option) to return to previous screens without losing data at `packages/keystone-installer-ui/src/App.tsx`
- [ ] T058 [P] Implement Ctrl+C handler with confirmation dialog and incomplete state warning at `packages/keystone-installer-ui/src/App.tsx`
- [X] T059 [P] Handle edge case: no disks detected - show error with hardware check suggestion at `packages/keystone-installer-ui/src/App.tsx`
- [ ] T060 [P] Handle edge case: hostname conflict with existing host folder - offer overwrite/rename/cancel at `packages/keystone-installer-ui/src/App.tsx`
- [ ] T061 [P] Handle edge case: ~/nixos-config/ already exists - offer use existing/backup/cancel at `packages/keystone-installer-ui/src/App.tsx`
- [X] T062 [P] Update documentation at `docs/installer-tui.md` with new local installation workflow
- [X] T063 [P] Update testing guide at `docs/testing-installer-tui.md` with local installation test cases
- [ ] T064 Run full VM test using `bin/virtual-machine` and verify complete installation flow

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 - BLOCKS all user stories
- **User Stories 1-2 (Phases 3-4)**: Depend on Phase 2 - P1 priority, implement first
- **User Stories 3-4 (Phases 5-6)**: Depend on Phase 2 - P2 priority, can parallel with US1-2
- **User Stories 5-6 (Phases 7-8)**: Depend on Phase 2 - P3 priority, can parallel
- **Installation Orchestration (Phase 9)**: Depends on Phases 5-6 (needs disk and config functions)
- **Polish (Phase 10)**: Depends on all story phases being complete

### User Story Dependencies

- **User Story 1 (P1)**: Network setup - Already exists, minimal changes
- **User Story 2 (P1)**: Method selection - Depends on US1 "Continue" button
- **User Story 3 (P2)**: Disk selection - Independent of US1/US2 UI, needs disk.ts
- **User Story 4 (P2)**: Config creation - Independent, needs config-generator.ts
- **User Story 5 (P3)**: Clone repo - Alternative to US3/US4, needs installation.ts
- **User Story 6 (P3)**: Transparency - Cross-cutting, adds to all flows

### Parallel Opportunities

Within Phase 1:
- T002, T003, T004 can run in parallel (different files)

Within Phase 2:
- T005, T006, T007 can run in parallel (different .ts files)

Within each User Story:
- Multiple TUI screen implementations are sequential (same file)
- Module implementations (disk.ts, config-generator.ts) can parallel TUI work

---

## Parallel Example: Foundation Phase

```bash
# Launch all foundation modules together:
Task: "Create disk.ts module at packages/keystone-installer-ui/src/disk.ts"
Task: "Create config-generator.ts module at packages/keystone-installer-ui/src/config-generator.ts"
Task: "Create installation.ts module at packages/keystone-installer-ui/src/installation.ts"
```

---

## Implementation Strategy

### MVP First (User Stories 1-2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1 (Network)
4. Complete Phase 4: User Story 2 (Method Selection)
5. **STOP and VALIDATE**: Test network → method selection flow in dev mode
6. Deploy ISO with method selection (even if local install not complete)

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add US1 + US2 → Test in dev mode → Build ISO (shows method options)
3. Add US3 + US4 → Test in dev mode → Build ISO (local install works)
4. Add US5 + US6 → Test in dev mode → Build ISO (clone + transparency)
5. Complete Installation Orchestration → Full VM test
6. Each increment adds value without breaking previous functionality

### Dev Mode Testing Strategy

1. **Every task**: Test in dev mode first (`DEV_MODE=1 node dist/index.js`)
2. **After each user story**: Verify screens flow correctly
3. **Before Phase 9**: All UI should work in dev mode
4. **Phase 9+**: Requires VM testing for actual installation

---

## Notes

- [P] tasks = different files, no dependencies
- [US*] label maps task to specific user story for traceability
- All disk/install operations check DEV_MODE before executing
- Dev mode writes to /tmp/keystone-dev/ instead of /mnt
- VM testing required only for Phase 9+ (actual installation)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
