# Tasks: Secure Boot Integration with Disko

**Feature**: Secure Boot Integration with Disko
**Branch**: `005-secureboot-disko-integration`
**Dependencies**: lanzaboote flake input, sbctl package

## Phase 1: Setup

**Goal**: Initialize project structure and dependencies

- [X] T001 Add lanzaboote as flake input in flake.nix
- [X] T002 Add sbctl to installer environment in modules/iso-installer.nix
- [X] T003 Create modules/secure-boot directory structure

## Phase 2: Foundational

**Goal**: Create base module structure and configuration options

- [X] T004 Create modules/secure-boot/default.nix with module skeleton
- [X] T005 Define keystone.secureBoot options (enable, includeMS, autoEnroll, pkiBundle)
- [X] T006 Add module assertions and validation logic in modules/secure-boot/default.nix

## Phase 3: User Story 1 - Automatic Key Generation [US1]

**Goal**: Generate Secure Boot keys during disko partitioning
**Test**: Keys exist at /var/lib/sbctl/keys after disko execution

- [X] T007 [US1] Create secure boot hook script in modules/secure-boot/hook.sh
- [X] T008 [US1] Implement Setup Mode detection logic in modules/secure-boot/hook.sh
- [X] T009 [US1] Implement key generation with sbctl in modules/secure-boot/hook.sh
- [X] T010 [US1] Add error handling for key generation failures in modules/secure-boot/hook.sh
- [X] T011 [P] [US1] Integrate hook into disko module at modules/disko-single-disk-root/default.nix

## Phase 4: User Story 2 - Key Enrollment [US2]

**Goal**: Enroll keys in UEFI firmware and transition to User Mode
**Test**: UEFI transitions from Setup Mode to User Mode

- [ ] T012 [US2] Implement key enrollment logic in modules/secure-boot/hook.sh
- [ ] T013 [US2] Handle Microsoft certificate inclusion option in modules/secure-boot/hook.sh
- [ ] T014 [US2] Add Setup Mode to User Mode transition verification in modules/secure-boot/hook.sh
- [ ] T015 [US2] Implement graceful handling of already-enrolled systems in modules/secure-boot/hook.sh

## Phase 5: User Story 3 - Lanzaboote Integration [US3]

**Goal**: Configure lanzaboote to sign bootloader with generated keys
**Test**: Lanzaboote module enabled with correct pkiBundle path

- [ ] T016 [US3] Configure boot.lanzaboote options in modules/secure-boot/default.nix
- [ ] T017 [US3] Set pkiBundle path based on module options in modules/secure-boot/default.nix
- [ ] T018 [US3] Ensure lanzaboote only enables when secureBoot.enable is true in modules/secure-boot/default.nix
- [ ] T019 [P] [US3] Add secure-boot module import to modules/server/default.nix
- [ ] T020 [P] [US3] Update vms/test-server/configuration.nix to verify module integration

## Phase 6: User Story 4 - Verification [US4]

**Goal**: Verify Secure Boot is fully functional after deployment
**Test**: bootctl status shows "Secure Boot: enabled (user)"

- [ ] T021 [US4] Create verification script in bin/verify-secureboot
- [ ] T022 [US4] Update bin/test-deployment to remove post-install-provisioner call
- [ ] T023 [US4] Add Secure Boot verification to bin/test-deployment verification phase
- [ ] T024 [P] [US4] Create example configuration in examples/secure-boot-vm.nix
- [ ] T025 [P] [US4] Create example for dual-boot in examples/secure-boot-dual-boot.nix

## Phase 7: Polish & Cross-Cutting Concerns

**Goal**: Documentation, cleanup, and final testing

- [ ] T026 [P] Update README.md with Secure Boot feature documentation
- [ ] T027 [P] Mark bin/post-install-provisioner as deprecated with migration notice
- [ ] T028 [P] Add module documentation comments in modules/secure-boot/default.nix
- [ ] T029 Create integration test for complete deployment workflow
- [ ] T030 Test VM deployment with bin/test-deployment --hard-reset

## Dependencies & Execution Order

### Story Dependencies
```
Setup → Foundational → US1 (Key Generation) → US2 (Enrollment) → US3 (Lanzaboote) → US4 (Verification) → Polish
```

### Critical Path
1. Flake input (T001) blocks all lanzaboote tasks
2. Module creation (T004-T006) blocks all module configuration
3. Hook script (T007-T010) blocks disko integration
4. Key generation must complete before enrollment
5. Enrollment must complete before lanzaboote configuration

### Parallel Execution Opportunities

**Within US1** (after T007):
- T008, T009, T010 can be developed in parallel (different functions in hook.sh)

**Within US3** (after T016):
- T019 and T020 can be done in parallel (different files)

**Within US4**:
- T024 and T025 can be done in parallel (independent examples)

**Within Polish**:
- T026, T027, T028 can all be done in parallel (independent documentation)

## Implementation Strategy

### MVP Scope (Minimal Viable Product)
Complete Phases 1-3 (US1 only) for basic key generation functionality:
- Tasks T001-T011
- Provides: Keys generated during deployment
- Missing: Enrollment, signing, verification

### Incremental Delivery
1. **Iteration 1**: Setup + US1 (Key Generation) - Keys exist but not enrolled
2. **Iteration 2**: US2 (Key Enrollment) - Keys enrolled, firmware in User Mode
3. **Iteration 3**: US3 (Lanzaboote) - Bootloader signed
4. **Iteration 4**: US4 (Verification) - Full end-to-end validation
5. **Iteration 5**: Polish - Production ready

### Risk Mitigation
- Test each story independently before integration
- Keep existing post-install-provisioner as fallback until US4 complete
- Use VM testing throughout to avoid hardware issues

## Summary

- **Total Tasks**: 30
- **Setup Tasks**: 3
- **Foundational Tasks**: 3
- **US1 Tasks**: 5
- **US2 Tasks**: 4
- **US3 Tasks**: 5
- **US4 Tasks**: 5
- **Polish Tasks**: 5
- **Parallel Opportunities**: 9 tasks marked with [P]
- **Story-Specific Tasks**: 19 tasks marked with story labels

Each user story can be independently implemented and tested, enabling incremental delivery and reducing integration risk.