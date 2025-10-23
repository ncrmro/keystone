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

- [ ] T001 Verify nixos-anywhere is available via `nix run` or system installation
- [ ] T002 [P] Create examples/ directory at repository root
- [ ] T003 [P] Create vms/test-server/ directory structure

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core configuration that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Add nixosConfigurations.test-server to flake.nix outputs with module imports
- [ ] T005 Create vms/test-server/configuration.nix with minimal server configuration
- [ ] T006 Validate configuration builds with `nix build .#nixosConfigurations.test-server.config.system.build.toplevel`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Basic Server Deployment to VM (Priority: P1) 🎯 MVP

**Goal**: Enable developers to deploy a minimal Keystone server to a VM via nixos-anywhere and verify it works via SSH

**Independent Test**:
1. Boot VM from Keystone ISO with SSH access
2. Run `nixos-anywhere --flake .#test-server root@<vm-ip>`
3. Wait for deployment to complete and system to reboot
4. SSH into deployed server: `ssh root@<vm-ip>`
5. Verify hostname, ZFS pool status, and services running

### Implementation for User Story 1

- [ ] T007 [US1] Configure hostname in vms/test-server/configuration.nix
- [ ] T008 [US1] Configure keystone.disko settings in vms/test-server/configuration.nix (device: /dev/vda, enable: true)
- [ ] T009 [US1] Configure keystone.server.enable in vms/test-server/configuration.nix
- [ ] T010 [US1] Add SSH authorized keys placeholder with documentation in vms/test-server/configuration.nix
- [ ] T011 [US1] Document disk device selection for different VM types in vms/test-server/configuration.nix comments
- [ ] T012 [US1] Test deployment to VM booted from ISO and verify completion without errors
- [ ] T013 [US1] Verify system reboots automatically after deployment
- [ ] T014 [US1] Test SSH access to deployed server using configured keys
- [ ] T015 [US1] Verify essential services running: systemctl status sshd avahi-daemon systemd-resolved
- [ ] T016 [US1] Verify ZFS pool status with `zpool status` shows healthy rpool
- [ ] T017 [US1] Verify encryption status: datasets under rpool/crypt are encrypted
- [ ] T018 [US1] Document TPM2 password prompt behavior on first boot in quickstart
- [ ] T019 [US1] Verify mDNS resolution: `ping test-server.local` from dev machine

**Checkpoint**: At this point, User Story 1 should be fully functional - manual deployment via nixos-anywhere works end-to-end

---

## Phase 4: User Story 2 - Installation Verification and Validation (Priority: P2)

**Goal**: Provide automated verification script to validate server deployment configuration and security

**Independent Test**:
1. Deploy a server using US1 workflow
2. Run `./scripts/verify-deployment.sh test-server <vm-ip>`
3. Verify all checks pass (SSH, hostname, firewall, ZFS, encryption, services, mDNS)
4. Verify script exits with code 0 on success

### Implementation for User Story 2

- [ ] T020 [US2] Create scripts/verify-deployment.sh with script structure and usage documentation
- [ ] T021 [US2] Implement SSH connectivity check in scripts/verify-deployment.sh
- [ ] T022 [US2] Implement hostname verification check in scripts/verify-deployment.sh
- [ ] T023 [US2] Implement firewall rules check (verify only port 22 open) in scripts/verify-deployment.sh
- [ ] T024 [US2] Implement ZFS pool status check in scripts/verify-deployment.sh
- [ ] T025 [US2] Implement encryption verification check (rpool/crypt datasets) in scripts/verify-deployment.sh
- [ ] T026 [US2] Implement essential services status check (sshd, avahi, systemd-resolved) in scripts/verify-deployment.sh
- [ ] T027 [US2] Implement mDNS advertisement check in scripts/verify-deployment.sh
- [ ] T028 [US2] Implement formatted output with PASS/FAIL indicators in scripts/verify-deployment.sh
- [ ] T029 [US2] Implement summary report at end of verification in scripts/verify-deployment.sh
- [ ] T030 [US2] Implement proper exit codes (0 on success, non-zero on failure) in scripts/verify-deployment.sh
- [ ] T031 [US2] Test verification script against successfully deployed server
- [ ] T032 [US2] Test verification script failure modes (wrong hostname, missing services, etc.)
- [ ] T033 [US2] Make script executable with `chmod +x scripts/verify-deployment.sh`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - deployment can be automatically verified

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

- [ ] T034 [US3] Create scripts/deploy-vm.sh wrapper script for nixos-anywhere deployment
- [ ] T035 [US3] Add configuration validation step in scripts/deploy-vm.sh (nix build check)
- [ ] T036 [US3] Add target IP parameter handling in scripts/deploy-vm.sh
- [ ] T037 [US3] Add deployment confirmation prompt in scripts/deploy-vm.sh
- [ ] T038 [US3] Add clear progress output during deployment in scripts/deploy-vm.sh
- [ ] T039 [US3] Add post-deployment verification call in scripts/deploy-vm.sh (optional --verify flag)
- [ ] T040 [US3] Document deployment workflow in deploy-vm.sh comments and usage
- [ ] T041 [US3] Test initial deployment using deploy-vm.sh
- [ ] T042 [US3] Test redeployment to same VM produces identical configuration
- [ ] T043 [US3] Test configuration change workflow (modify config, redeploy, verify changes)
- [ ] T044 [US3] Make script executable with `chmod +x scripts/deploy-vm.sh`
- [ ] T045 [US3] Document VM cleanup/reset procedure for testing reproducibility

**Checkpoint**: All user stories should now be independently functional - complete deployment automation with verification

---

## Phase 6: Documentation & Examples

**Purpose**: Create reusable examples and comprehensive documentation

- [ ] T046 [P] Create examples/test-server.nix with well-documented minimal server configuration
- [ ] T047 [P] Add comments explaining each configuration option in examples/test-server.nix
- [ ] T048 [P] Add disk device selection guide in examples/test-server.nix comments (VMs vs bare metal)
- [ ] T049 [P] Add SSH key configuration examples in examples/test-server.nix comments
- [ ] T050 [P] Add swap size customization examples in examples/test-server.nix comments
- [ ] T051 [P] Document common configuration errors and solutions in examples/test-server.nix
- [ ] T052 Update README.md with nixos-anywhere deployment section (if README exists)
- [ ] T053 [P] Add deployment quickstart to project documentation
- [ ] T054 [P] Document edge cases and troubleshooting (network loss, disk errors, TPM2 fallback)

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that enhance overall user experience across all stories

- [ ] T055 Add comprehensive error handling to deploy-vm.sh (network checks, SSH availability)
- [ ] T056 Add comprehensive error handling to verify-deployment.sh (timeout handling, partial failures)
- [ ] T057 [P] Add color-coded output to verification script (green PASS, red FAIL)
- [ ] T058 [P] Optimize configuration build times (if possible via nix caching strategies)
- [ ] T059 Review and update quickstart.md based on actual deployment testing
- [ ] T060 [P] Add example for production deployment with by-id disk paths in examples/
- [ ] T061 [P] Add example for multiple SSH keys in examples/
- [ ] T062 Test complete deployment workflow end-to-end with fresh VM
- [ ] T063 Document expected deployment timeline (ISO boot, deploy, reboot, verify)
- [ ] T064 Create troubleshooting guide for common deployment issues

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
1. Configuration tasks (T007-T011) can be done in sequence
2. Testing tasks (T012-T019) must follow configuration tasks
3. Each test validates a specific acceptance criterion

**US2 - Verification**:
1. Create script structure (T020)
2. Implement individual checks (T021-T027) - these can be parallelized
3. Implement output formatting (T028-T030)
4. Testing (T031-T033) must follow implementation

**US3 - Reproducibility**:
1. Create wrapper script (T034)
2. Add features (T035-T040) in sequence
3. Testing (T041-T045) validates the complete workflow

### Parallel Opportunities

- **Phase 1 Setup**: All tasks (T001-T003) can run in parallel
- **Phase 6 Documentation**: All tasks marked [P] can run in parallel (T046-T051, T053-T054)
- **Phase 7 Polish**: Tasks T057, T058, T060, T061 can run in parallel
- **US2 Checks**: Individual verification checks (T021-T027) can be implemented in parallel
- **Documentation can be written in parallel with implementation throughout**

---

## Parallel Example: User Story 2 Checks

```bash
# These verification check implementations can all be done in parallel:
Task T022: "Implement hostname verification check"
Task T023: "Implement firewall rules check"
Task T024: "Implement ZFS pool status check"
Task T025: "Implement encryption verification check"
Task T026: "Implement essential services status check"
Task T027: "Implement mDNS advertisement check"

# Each developer can work on a different check function simultaneously
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T006) - CRITICAL
3. Complete Phase 3: User Story 1 (T007-T019)
4. **STOP and VALIDATE**: Manually deploy to VM, verify all acceptance criteria
5. Demo/document working deployment

**At this point, you have a working minimal deployment system that can be used immediately.**

### Incremental Delivery

1. **Milestone 1**: Foundation Ready (Phases 1-2)
   - Configuration builds successfully
   - Ready for first deployment

2. **Milestone 2**: Manual Deployment Works (Phase 3 - US1)
   - Can deploy via nixos-anywhere
   - Can SSH into deployed server
   - All services operational
   - **MVP - ship it!**

3. **Milestone 3**: Automated Verification (Phase 4 - US2)
   - Verification script validates deployments
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

### Parallel Team Strategy

With multiple developers:

1. **Team completes Setup + Foundational together** (T001-T006)
2. **Once Foundational is done:**
   - Developer A: US1 Basic Deployment (T007-T019)
   - Developer B: Documentation (Phase 6 in parallel)
3. **After US1 works:**
   - Developer A: US2 Verification (T020-T033)
   - Developer B: US3 Reproducibility (T034-T045)
4. **Final integration and polish** (Phase 7 together)

---

## Task Count Summary

- **Phase 1 (Setup)**: 3 tasks
- **Phase 2 (Foundational)**: 3 tasks - BLOCKS all stories
- **Phase 3 (US1 - MVP)**: 13 tasks
- **Phase 4 (US2)**: 14 tasks
- **Phase 5 (US3)**: 12 tasks
- **Phase 6 (Documentation)**: 9 tasks
- **Phase 7 (Polish)**: 10 tasks

**Total**: 64 tasks

**MVP Scope** (Minimum to ship): 19 tasks (Phases 1-3)
**Full Feature**: 64 tasks (all phases)

---

## Notes

- **[P] tasks**: Can run in parallel (different files, no dependencies)
- **[Story] label**: Maps task to specific user story for traceability
- **NixOS testing**: Uses VM infrastructure from feature 001
- **No tests requested**: Manual verification via SSH and scripts instead of automated test suite
- **Idempotent**: nixos-anywhere deployments can be retried on failure
- **Security**: All configurations use encryption by default (disko module)
- **Verification**: US2 provides automated validation of security and configuration
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
- ✅ **SC-006**: Disk encryption configured and functional (100% of deployments)
- ✅ **SC-007**: Deployment is reproducible (identical results on redeploy)

Run the verification script (US2) and deployment wrapper (US3) to validate all success criteria are met.
