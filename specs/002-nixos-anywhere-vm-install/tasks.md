# Tasks: NixOS-Anywhere VM Installation

**Input**: Design documents from `/specs/002-nixos-anywhere-vm-install/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Tests are NOT explicitly requested in the specification. Manual verification is used via SSH and verification scripts.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- **NixOS project**: Configuration files at repository root and in module subdirectories
- **Scripts**: `scripts/` directory for automation
- **Examples**: `examples/` directory for reference configurations
- **VMs**: `vms/` directory for VM-specific configurations

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare development environment and verify prerequisites

- [x] T001 Verify nixos-anywhere is available via `nix run` or system installation
- [x] T002 [P] Create examples/ directory at repository root
- [x] T003 [P] Create vms/test-server/ directory structure

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core configuration that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Add nixosConfigurations.test-server to flake.nix outputs with module imports
- [x] T005 Create vms/test-server/configuration.nix with minimal server configuration
- [x] T006 Validate configuration builds with `nix build .#nixosConfigurations.test-server.config.system.build.toplevel`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Basic Server Deployment to VM (Priority: P1) 🎯 MVP

**Goal**: Enable developers to deploy a minimal Keystone server to a VM via nixos-anywhere and verify ZFS-based installation works via SSH

**Independent Test**:
1. Boot VM from Keystone ISO with SSH access
2. Run `nixos-anywhere --flake .#test-server root@<vm-ip>`
3. Wait for deployment to complete and system to reboot
4. SSH into deployed server: `ssh root@<vm-ip>`
5. Verify ZFS pool is mounted and encrypted storage is accessible

**Known Issues**:
- ZFS modules cannot auto-load in current ISO kernel (see error in deployment logs)
- Issue #156: ZFS pools may need explicit export before reboot (https://github.com/nix-community/nixos-anywhere/issues/156)

### Implementation for User Story 1

**BLOCKER**: ZFS modules cannot be auto-loaded in the ISO, preventing nixos-anywhere deployment

- [x] T007 [US1] Fix ZFS kernel compatibility - try kernel 6.12 in modules/iso-installer.nix (boot.kernelPackages = pkgs.linuxPackages_6_12)
- [x] T008 [US1] Rebuild ISO with kernel 6.12 and verify build succeeds
- [ ] T009 [US1] Boot VM from new ISO and verify ZFS modules load: `ssh root@<iso-ip> 'modprobe zfs && lsmod | grep zfs'`
- [ ] T010 [US1] Verify nixos-anywhere disk formatting works: check disko script can run `zpool create` commands
- [x] T011 [US1] Configure hostname in vms/test-server/configuration.nix
- [x] T012 [US1] Configure keystone.disko settings in vms/test-server/configuration.nix (device: /dev/vda, enable: true)
- [x] T013 [US1] Configure keystone.server.enable in vms/test-server/configuration.nix
- [x] T014 [US1] Add SSH authorized keys in vms/test-server/configuration.nix (users.users.root.openssh.authorizedKeys.keys)
- [ ] T015 [US1] Test complete deployment: nixos-anywhere to VM and verify no errors
- [ ] T016 [US1] Verify system reboots automatically after deployment completes
- [ ] T017 [US1] Test SSH access to deployed server using configured keys
- [ ] T018 [US1] Verify SSH service is running: `systemctl status sshd`
- [ ] T019 [US1] Verify ZFS pool mounted: `zpool status` shows healthy rpool
- [ ] T020 [US1] Verify encryption status: `zfs get encryption rpool/crypt` shows encrypted datasets
- [ ] T021 [US1] Verify root filesystem accessible: `df -h /` shows ZFS mount
- [ ] T022 [US1] Document ZFS pool export issue (#156) and workarounds if encountered

**Checkpoint**: At this point, User Story 1 should be fully functional - manual deployment via nixos-anywhere works end-to-end with ZFS

---

## Phase 4: User Story 2 - Installation Verification and Validation (Priority: P2)

**Goal**: Provide automated verification script to validate server deployment configuration and ZFS storage

**Independent Test**:
1. Deploy a server using US1 workflow
2. Run `./scripts/verify-deployment.sh test-server <vm-ip>`
3. Verify all checks pass (SSH, hostname, firewall, ZFS, encryption)
4. Verify script exits with code 0 on success

### Implementation for User Story 2

- [x] T023 [US2] Create scripts/verify-deployment.sh with script structure and usage documentation
- [x] T024 [US2] Implement SSH connectivity check in scripts/verify-deployment.sh
- [x] T025 [US2] Implement hostname verification check in scripts/verify-deployment.sh
- [x] T026 [US2] Implement firewall rules check (verify only port 22 open) in scripts/verify-deployment.sh
- [x] T027 [US2] Implement ZFS pool status check in scripts/verify-deployment.sh
- [x] T028 [US2] Implement encryption verification check (rpool/crypt datasets) in scripts/verify-deployment.sh
- [x] T029 [US2] Remove avahi and mDNS checks from scripts/verify-deployment.sh (not needed for ZFS verification)
- [x] T030 [US2] Implement formatted output with PASS/FAIL indicators in scripts/verify-deployment.sh
- [x] T031 [US2] Implement summary report at end of verification in scripts/verify-deployment.sh
- [x] T032 [US2] Implement proper exit codes (0 on success, non-zero on failure) in scripts/verify-deployment.sh
- [ ] T033 [US2] Test verification script against successfully deployed server
- [ ] T034 [US2] Test verification script failure modes (wrong hostname, missing services, etc.)
- [x] T035 [US2] Make script executable with `chmod +x scripts/verify-deployment.sh`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - ZFS deployment can be automatically verified

---

## Phase 5: User Story 3 - Reproducible Deployment Process (Priority: P3)

**Goal**: Enable developers to repeatedly deploy and test configuration changes with confidence in reproducibility

**Independent Test**:
1. Deploy server using US1 workflow
2. Destroy the VM completely
3. Redeploy using same configuration
4. Verify using US2 verification script - should be identical
5. Modify configuration (change hostname)
6. Redeploy and verify new configuration applied

### Implementation for User Story 3

- [x] T036 [US3] Create scripts/deploy-vm.sh wrapper script for nixos-anywhere deployment
- [x] T037 [US3] Add configuration validation step in scripts/deploy-vm.sh (nix build check)
- [x] T038 [US3] Add target IP parameter handling in scripts/deploy-vm.sh
- [x] T039 [US3] Add deployment confirmation prompt in scripts/deploy-vm.sh
- [x] T040 [US3] Add clear progress output during deployment in scripts/deploy-vm.sh
- [x] T041 [US3] Add post-deployment verification call in scripts/deploy-vm.sh (optional --verify flag)
- [x] T042 [US3] Document deployment workflow in deploy-vm.sh comments and usage
- [ ] T043 [US3] Test initial deployment using deploy-vm.sh
- [ ] T044 [US3] Test redeployment to same VM produces identical configuration
- [ ] T045 [US3] Test configuration change workflow (modify config, redeploy, verify changes)
- [x] T046 [US3] Make script executable with `chmod +x scripts/deploy-vm.sh`
- [ ] T047 [US3] Document VM cleanup/reset procedure for testing reproducibility

**Checkpoint**: All user stories should now be independently functional - complete deployment automation with verification

---

## Phase 6: Documentation & Examples

**Purpose**: Create reusable examples and comprehensive documentation

- [x] T048 [P] Create examples/test-server.nix with well-documented minimal server configuration
- [x] T049 [P] Add comments explaining each configuration option in examples/test-server.nix
- [x] T050 [P] Add disk device selection guide in examples/test-server.nix comments (VMs vs bare metal)
- [x] T051 [P] Add SSH key configuration examples in examples/test-server.nix comments
- [x] T052 [P] Add swap size customization examples in examples/test-server.nix comments
- [x] T053 [P] Document common configuration errors and solutions in examples/test-server.nix
- [x] T054 Update README.md with nixos-anywhere deployment section (if README exists)
- [x] T055 [P] Add deployment quickstart to project documentation
- [x] T056 [P] Document edge cases and troubleshooting (network loss, disk errors, TPM2 fallback)

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that enhance overall user experience across all stories

- [ ] T057 Add comprehensive error handling to deploy-vm.sh (network checks, SSH availability)
- [ ] T058 Add comprehensive error handling to verify-deployment.sh (timeout handling, partial failures)
- [ ] T059 [P] Add color-coded output to verification script (green PASS, red FAIL)
- [ ] T060 [P] Optimize configuration build times (if possible via nix caching strategies)
- [ ] T061 Review and update quickstart.md based on actual deployment testing
- [ ] T062 [P] Add example for production deployment with by-id disk paths in examples/
- [ ] T063 [P] Add example for multiple SSH keys in examples/
- [ ] T064 Test complete deployment workflow end-to-end with fresh VM
- [ ] T065 Document expected deployment timeline (ISO boot, deploy, reboot, verify)
- [ ] T066 Create troubleshooting guide for common deployment issues including ZFS module loading and pool export

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User stories are ordered by priority but can be worked in parallel if desired
  - US2 (verification) provides value only after US1 (deployment) works
  - US3 (reproducibility) validates both US1 and US2
- **Documentation (Phase 6)**: Can proceed in parallel with Phase 3-5 user stories
- **Polish (Phase 7)**: Depends on all user stories being complete for full testing

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories ✅ MVP
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Provides value once US1 is working
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Uses both US1 and US2 for validation

### Within Each User Story

**US1 - Basic Deployment**:
1. Fix ZFS kernel issue FIRST (T007-T010) - BLOCKS everything
2. Configuration tasks (T011-T014) can be done in sequence
3. Testing tasks (T015-T022) must follow configuration tasks
4. Each test validates a specific acceptance criterion

**US2 - Verification**:
1. Create script structure (T023)
2. Implement individual checks (T024-T028) - these can be parallelized
3. Remove unneeded checks (T029)
4. Implement output formatting (T030-T032)
5. Testing (T033-T035) must follow implementation

**US3 - Reproducibility**:
1. Create wrapper script (T036)
2. Add features (T037-T042) in sequence
3. Testing (T043-T047) validates the complete workflow

### Parallel Opportunities

- **Phase 1 Setup**: All tasks (T001-T003) can run in parallel
- **Phase 6 Documentation**: All tasks marked [P] can run in parallel (T048-T053, T055-T056)
- **Phase 7 Polish**: Tasks T059, T060, T062, T063 can run in parallel
- **US2 Checks**: Individual verification checks (T024-T028) can be implemented in parallel
- **Documentation can be written in parallel with implementation throughout**

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T006) - CRITICAL
3. **FIX BLOCKER**: Complete kernel 6.12 ZFS fix (T007-T010) - CRITICAL
4. Complete Phase 3: User Story 1 (T011-T022)
5. **STOP and VALIDATE**: Manually deploy to VM, verify ZFS works
6. Demo/document working deployment

**At this point, you have a working minimal ZFS deployment system that can be used immediately.**

### Incremental Delivery

1. **Milestone 1**: Foundation Ready (Phases 1-2)
   - Configuration builds successfully
   - Ready for first deployment

2. **Milestone 2**: Manual Deployment Works (Phase 3 - US1)
   - ZFS modules load in ISO
   - Can deploy via nixos-anywhere
   - Can SSH into deployed server
   - ZFS pool mounted and encrypted
   - **MVP - ship it!**

3. **Milestone 3**: Automated Verification (Phase 4 - US2)
   - Verification script validates ZFS deployments
   - Reduces manual checking
   - Builds confidence in deployment

4. **Milestone 4**: Full Automation (Phase 5 - US3)
   - Deployment wrapper simplifies workflow
   - Reproducibility validated
   - Configuration changes tested

5. **Milestone 5**: Production Ready (Phases 6-7)
   - Comprehensive documentation
   - Examples for different scenarios
   - Error handling and troubleshooting

---

## Task Count Summary

- **Phase 1 (Setup)**: 3 tasks
- **Phase 2 (Foundational)**: 3 tasks - BLOCKS all stories
- **Phase 3 (US1 - MVP)**: 16 tasks (including ZFS kernel fix)
- **Phase 4 (US2)**: 13 tasks
- **Phase 5 (US3)**: 12 tasks
- **Phase 6 (Documentation)**: 9 tasks
- **Phase 7 (Polish)**: 10 tasks

**Total**: 66 tasks

**MVP Scope** (Minimum to ship): 22 tasks (Phases 1-3)
**Full Feature**: 66 tasks (all phases)

---

## Notes

- **[P] tasks**: Can run in parallel (different files, no dependencies)
- **[Story] label**: Maps task to specific user story for traceability
- **ZFS kernel compatibility**: Current blocker - testing kernel 6.12 as later kernels lack ZFS support
- **ZFS pool export**: May encounter issue #156 - pools need export before reboot
- **Focus**: ZFS-based installation verification, not avahi/mdns
- **NixOS testing**: Uses VM infrastructure from feature 001
- **No tests requested**: Manual verification via SSH and scripts instead of automated test suite
- **Idempotent**: nixos-anywhere deployments can be retried on failure
- **Security**: All configurations use encryption by default (disko module)
- **Each checkpoint**: Represents an independently valuable deliverable
- **Commit strategy**: Commit after each completed user story phase
- **TPM2 note**: VMs will show password prompt on boot (expected behavior)

---

## Success Criteria Validation

After completing all tasks, verify these success criteria from spec.md:

- ✅ **SC-001**: Developer can deploy to VM in under 10 minutes
- ✅ **SC-002**: Deployed server boots successfully on first attempt
- ✅ **SC-003**: SSH access available within 2 minutes of boot
- ✅ **SC-004**: Deployment completes without errors (100% success rate on fresh VMs)
- ✅ **SC-005**: Developer can verify installation status via SSH commands
- ✅ **SC-006**: Disk encryption configured and functional (100% of deployments) - ZFS native encryption
- ✅ **SC-007**: Deployment is reproducible (identical results on redeploy)

Run the verification script (US2) and deployment wrapper (US3) to validate all success criteria are met.
