# Tasks: GitHub Actions VM CI for Copilot Agent Iteration

**Input**: Design documents from `/specs/011-github-actions-vm-ci/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Tests are NOT explicitly requested in this feature specification. Focus on implementation and validation scripts only.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This is a GitHub Actions workflow project with NixOS configurations:
- `.github/workflows/` for workflow definitions
- `tests/ci/` for CI testing scripts
- `vms/ci-test/` for CI-specific VM configurations

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure for CI testing infrastructure

- [ ] T001 Create CI testing directory structure: `tests/ci/` and `vms/ci-test/`
- [ ] T002 [P] Add `.gitignore` entries for QCOW2 disk images and temporary VM files
- [ ] T003 [P] Document CI testing approach in CLAUDE.md Active Technologies section

**Checkpoint**: Project structure ready for workflow and script implementation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core testing scripts that MUST be complete before workflow can function

**⚠️ CRITICAL**: The GitHub Actions workflow cannot function without these helper scripts

- [ ] T004 [P] Create boot status validation script in `tests/ci/check-boot-status.sh`
- [ ] T005 [P] Create service validation script in `tests/ci/validate-services.sh`
- [ ] T006 Create results formatting script with JSON schema implementation in `tests/ci/format-results.sh`
- [ ] T007 [P] Make all CI scripts executable: `chmod +x tests/ci/*.sh`

**Checkpoint**: Foundation ready - workflow implementation can now begin

---

## Phase 3: User Story 1 - Copilot Agent Iterative Configuration Development (Priority: P1) 🎯 MVP

**Goal**: Enable GitHub Copilot agents to trigger VM testing workflows, receive structured JSON feedback about build/boot/service failures, and iteratively refine NixOS configurations based on real execution results.

**Independent Test**: A Copilot agent can trigger the workflow via GitHub API (workflow_dispatch), poll for completion, download test results JSON from artifacts, parse error messages to identify failures (build/boot/service phases), and propose configuration fixes based on structured feedback.

### Implementation for User Story 1

- [ ] T008 [P] [US1] Create GitHub Actions workflow file at `.github/workflows/copilot-vm-test.yml`
- [ ] T009 [P] [US1] Implement workflow_dispatch trigger with config_name input (terminal/desktop/server) in `.github/workflows/copilot-vm-test.yml`
- [ ] T010 [P] [US1] Configure concurrency control (group by workflow + ref, cancel-in-progress) in `.github/workflows/copilot-vm-test.yml`
- [ ] T011 [US1] Add checkout and Nix installation steps using cachix/install-nix-action in `.github/workflows/copilot-vm-test.yml`
- [ ] T012 [US1] Add KVM availability check step (verify /dev/kvm exists, fail with clear error if missing) in `.github/workflows/copilot-vm-test.yml`
- [ ] T013 [US1] Implement build step using nixos-rebuild build-vm with error capture in `.github/workflows/copilot-vm-test.yml`
- [ ] T014 [US1] Implement VM boot step with 5-minute timeout and SSH connectivity check in `.github/workflows/copilot-vm-test.yml`
- [ ] T015 [US1] Integrate validate-services.sh script call in workflow in `.github/workflows/copilot-vm-test.yml`
- [ ] T016 [US1] Integrate format-results.sh script to generate JSON output conforming to test-result-schema.json in `.github/workflows/copilot-vm-test.yml`
- [ ] T017 [US1] Add workflow job outputs for status and phase (for programmatic access via GitHub API) in `.github/workflows/copilot-vm-test.yml`
- [ ] T018 [US1] Add artifact upload step for test-result.json with 90-day retention in `.github/workflows/copilot-vm-test.yml`
- [ ] T019 [US1] Add GITHUB_STEP_SUMMARY markdown output for human-readable results in `.github/workflows/copilot-vm-test.yml`
- [ ] T020 [US1] Add cleanup step to kill VMs and remove QCOW2 disk images (runs always) in `.github/workflows/copilot-vm-test.yml`

**Checkpoint**: At this point, Copilot agents can trigger workflows, receive structured JSON feedback, and iterate on configurations. User Story 1 is fully functional.

---

## Phase 4: User Story 2 - VM Environment Provisioning in CI (Priority: P2)

**Goal**: Ensure the CI environment reliably provisions VMs with hardware acceleration, sufficient resources (CPU/memory/disk), and proper cleanup to prevent resource exhaustion.

**Independent Test**: Manually trigger the workflow and verify: (1) VM is created with KVM acceleration, (2) VM has 2 vCPUs and 4GB RAM configured, (3) Build completes within resource limits, (4) Cleanup step successfully removes all VM artifacts after workflow completion.

### Implementation for User Story 2

- [ ] T021 [US2] Create minimal CI test VM configuration at `vms/ci-test/configuration.nix` with optimized resource allocation
- [ ] T022 [US2] Configure VM resource limits (2 cores, 4GB RAM, 8GB disk) in `vms/ci-test/configuration.nix`
- [ ] T023 [US2] Add CI test configuration flake output in `flake.nix` as `build-vm-ci-test`
- [ ] T024 [US2] Implement Cachix binary cache integration in workflow for faster builds in `.github/workflows/copilot-vm-test.yml`
- [ ] T025 [US2] Add workflow timeout-minutes: 30 to enforce SC-001 requirement in `.github/workflows/copilot-vm-test.yml`
- [ ] T026 [US2] Enhance cleanup step to verify all resources released (check for stray processes, disk images) in `.github/workflows/copilot-vm-test.yml`

**Checkpoint**: At this point, VMs provision reliably with proper resource constraints and cleanup. User Stories 1 AND 2 are both independently functional.

---

## Phase 5: User Story 3 - Automated Configuration Validation (Priority: P3)

**Goal**: Developers pushing configuration changes automatically receive VM-based validation feedback through the same infrastructure used by Copilot agents, providing continuous integration benefits.

**Independent Test**: Push a commit modifying `modules/`, `flake.nix`, or `vms/` to any branch and verify: (1) Workflow automatically triggers, (2) Configuration is tested in VM, (3) Results appear in GitHub UI as status check, (4) PR shows validation status if applicable.

### Implementation for User Story 3

- [ ] T027 [US3] Add push trigger with path filters (modules/**, vms/**, home-manager/**, flake.nix, flake.lock) in `.github/workflows/copilot-vm-test.yml`
- [ ] T028 [US3] Implement automatic config_name detection for push events (default to terminal) in `.github/workflows/copilot-vm-test.yml`
- [ ] T029 [US3] Add workflow status badge generation in README.md showing CI test status
- [ ] T030 [US3] Configure workflow to post summary comment on pull requests (optional enhancement)

**Checkpoint**: All user stories are now independently functional. Developers get automatic validation, Copilot agents can iterate, and VMs provision reliably.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and prepare for production use

- [ ] T031 [P] Add comprehensive workflow documentation in `specs/011-github-actions-vm-ci/quickstart.md` with Copilot agent usage examples
- [ ] T032 [P] Document workflow inputs and outputs in `.github/workflows/copilot-vm-test.yml` inline comments
- [ ] T033 [P] Add error handling improvements across all CI scripts (tests/ci/*.sh)
- [ ] T034 [P] Implement debug mode support (verbose logging when debug input is true) in `tests/ci/format-results.sh`
- [ ] T035 Validate test-result.json output conforms to `contracts/test-result-schema.json` using ajv-cli
- [ ] T036 Run quickstart.md validation: Test manual workflow trigger, test automatic push trigger, verify artifact download
- [ ] T037 Update CLAUDE.md Recent Changes section with feature summary and technologies added
- [ ] T038 [P] Add workflow performance optimization notes (Nix cache usage, VM resource tuning) in plan.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) - Core MVP functionality
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) - Can run in parallel with US1 but US1 is higher priority
- **User Story 3 (Phase 5)**: Depends on Foundational (Phase 2) AND User Story 1 (Phase 3) - Reuses US1 workflow
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1) - Copilot Agent Iteration**:
  - Can start after Foundational (Phase 2)
  - No dependencies on other stories
  - **MVP SCOPE**: This story alone provides the core value proposition

- **User Story 2 (P2) - VM Environment Provisioning**:
  - Can start after Foundational (Phase 2)
  - Enhances US1 with resource optimization and cleanup guarantees
  - Can be developed in parallel with US1 but lower priority

- **User Story 3 (P3) - Automated Configuration Validation**:
  - Requires User Story 1 (Phase 3) to be complete (reuses the workflow)
  - Adds push trigger and automatic validation on top of US1 infrastructure
  - Lowest priority - nice-to-have feature

### Within Each User Story

**User Story 1 (P1)**:
- T008-T010 can run in parallel (different workflow sections)
- T011-T020 must run sequentially (each step depends on previous)
- Tests not applicable (no test framework requested)

**User Story 2 (P2)**:
- T021-T023 can run in parallel (different files: vms/ci-test/configuration.nix, flake.nix)
- T024-T026 modify workflow created in US1 (must run after US1 complete)

**User Story 3 (P3)**:
- T027-T030 all modify workflow from US1 (must run sequentially after US1)

### Parallel Opportunities

- **Phase 1 (Setup)**: T002, T003 can run in parallel (different files)
- **Phase 2 (Foundational)**: T004, T005, T007 can run in parallel (different script files)
- **Phase 3 (US1)**: T008, T009, T010 can run in parallel (different sections of same YAML file with no conflicts)
- **Phase 4 (US2)**: T021, T022, T023 can run in parallel (vms/ci-test/configuration.nix vs flake.nix)
- **Phase 6 (Polish)**: T031, T032, T033, T034, T038 can run in parallel (different files)

---

## Parallel Example: User Story 1 Setup

```bash
# Launch workflow structure tasks together (different sections of YAML):
Task: "Create GitHub Actions workflow file at .github/workflows/copilot-vm-test.yml"
Task: "Implement workflow_dispatch trigger with config_name input in .github/workflows/copilot-vm-test.yml"
Task: "Configure concurrency control in .github/workflows/copilot-vm-test.yml"
```

## Parallel Example: User Story 2 Configuration

```bash
# Launch VM configuration tasks together (different files):
Task: "Create minimal CI test VM configuration at vms/ci-test/configuration.nix"
Task: "Configure VM resource limits in vms/ci-test/configuration.nix"
Task: "Add CI test configuration flake output in flake.nix as build-vm-ci-test"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only) - RECOMMENDED

1. **Phase 1: Setup** (T001-T003) - 30 minutes
   - Create directory structure
   - Update .gitignore and CLAUDE.md

2. **Phase 2: Foundational** (T004-T007) - 2 hours
   - Implement all CI helper scripts
   - CRITICAL: Workflow cannot function without these

3. **Phase 3: User Story 1** (T008-T020) - 4-6 hours
   - Implement complete workflow for Copilot agent iteration
   - **STOP and VALIDATE**: Test workflow manually, verify JSON output
   - Deploy to branch for Copilot agents to use

**MVP Delivery**: At this point, Copilot agents can iterate on configurations with structured feedback. This is the core value proposition.

### Incremental Delivery

1. **Foundation** (Setup + Foundational) → ~2.5 hours
2. **MVP** (User Story 1) → ~6.5 hours total → **Deploy and use**
3. **Enhancement** (User Story 2) → ~8.5 hours total → Resource optimization
4. **Automation** (User Story 3) → ~10 hours total → Automatic validation on push
5. **Production Ready** (Polish) → ~12 hours total → Documentation and validation

### Parallel Team Strategy

With multiple developers (not typical for infrastructure work):

1. **Team completes Setup + Foundational together** (~2.5 hours)
2. Once Foundational is done:
   - **Developer A**: User Story 1 (workflow implementation) - HIGHEST PRIORITY
   - **Developer B**: User Story 2 (VM configuration) - Can start in parallel
   - **Developer C**: Polish work (documentation) - Can start early
3. User Story 3 must wait for User Story 1 to complete

---

## Notes

- **[P] tasks**: Different files or non-conflicting sections, no dependencies, can run in parallel
- **[Story] label**: Maps task to specific user story for traceability and independent testing
- **Tests omitted**: Feature specification does not request test framework implementation
- **Focus on validation**: CI scripts (check-boot-status.sh, validate-services.sh) serve as validation layer
- **Commit frequently**: Commit after each task or logical group (e.g., all scripts in Phase 2)
- **Independent stories**: Each user story should be testable independently via quickstart.md scenarios
- **MVP scope**: User Story 1 provides complete value - stories 2 and 3 are enhancements

---

## Task Count Summary

- **Phase 1 (Setup)**: 3 tasks
- **Phase 2 (Foundational)**: 4 tasks (BLOCKS all user stories)
- **Phase 3 (US1 - MVP)**: 13 tasks
- **Phase 4 (US2)**: 6 tasks
- **Phase 5 (US3)**: 4 tasks
- **Phase 6 (Polish)**: 8 tasks
- **Total**: 38 tasks

**Parallel Opportunities**: 12 tasks marked [P] (31% parallelizable)

**MVP Scope**: Phases 1-3 only (20 tasks, ~6.5 hours estimated)

---

## Format Validation

✅ All tasks follow required checklist format: `- [ ] [ID] [P?] [Story] Description with file path`
✅ Sequential task IDs (T001-T038)
✅ Story labels present for all user story phases (US1, US2, US3)
✅ Exact file paths included in all implementation tasks
✅ Tasks organized by user story for independent implementation and testing
