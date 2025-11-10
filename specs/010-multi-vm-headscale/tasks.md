# Tasks: Multi-VM Headscale Connectivity Testing

**Input**: Design documents from `/specs/010-multi-vm-headscale/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: This feature uses bash validation scripts instead of traditional unit/integration tests. Each user story includes validation tasks that execute acceptance criteria from spec.md.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each connectivity scenario.

---

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create project structure, libvirt networks, and reusable NixOS modules

- [ ] T001 Create test directory structure at `test/multi-vm-headscale/` with subdirectories: vms/, networks/, orchestration/lib/
- [ ] T002 [P] Create modules directory structure at `modules/headscale-server/` and `modules/tailscale-client/`
- [ ] T003 [P] Create libvirt network XML for subnet-a (192.168.1.0/24) at `test/multi-vm-headscale/networks/subnet-a.xml`
- [ ] T004 [P] Create libvirt network XML for subnet-b (10.0.0.0/24) at `test/multi-vm-headscale/networks/subnet-b.xml`
- [ ] T005 [P] Create bash library for VM utilities at `test/multi-vm-headscale/orchestration/lib/vm-utils.sh` (ssh exec, wait functions)
- [ ] T006 [P] Create bash library for validation utilities at `test/multi-vm-headscale/orchestration/lib/validation-utils.sh` (assert functions, log formatting)
- [ ] T007 [P] Create configuration file at `test/multi-vm-headscale/orchestration/config.sh` (environment variables for IPs, timeouts, SSH options)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core NixOS modules and VM configurations that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T008 Implement Headscale server NixOS module at `modules/headscale-server/default.nix` (services.headscale config with MagicDNS, SQLite)
- [ ] T009 Implement Tailscale client NixOS module at `modules/tailscale-client/default.nix` (services.tailscale + registration systemd service)
- [ ] T010 [P] Create Headscale server VM configuration at `test/multi-vm-headscale/vms/headscale-server.nix` (IP: 192.168.1.5, subnet-a)
- [ ] T011 [P] Create client-node-1 VM configuration at `test/multi-vm-headscale/vms/client-node-1.nix` (IP: 192.168.1.10, subnet-a)
- [ ] T012 [P] Create client-node-2 VM configuration at `test/multi-vm-headscale/vms/client-node-2.nix` (IP: 10.0.0.10, subnet-b)
- [ ] T013 [P] Create client-node-3 VM configuration at `test/multi-vm-headscale/vms/client-node-3.nix` (IP: 10.0.0.11, subnet-b)
- [ ] T014 Update flake.nix to expose headscale-server and tailscale-client modules, add VM configurations
- [ ] T015 Implement base setup script at `test/multi-vm-headscale/orchestration/setup-test-env.sh` (create networks, build VMs, start VMs, wait for SSH)

**Checkpoint**: Foundation ready - all VMs can be built and started. User story validation can now begin.

---

## Phase 3: User Story 1 - Basic Mesh Network Connectivity (Priority: P1) 🎯 MVP

**Goal**: Verify three VMs establish encrypted mesh network with bidirectional connectivity

**Independent Test**: Deploy Headscale server + 3 client VMs, register clients, verify all nodes appear in `headscale nodes list` with "online" status, test ping between all pairs

**Acceptance Criteria from spec.md**:
1. All three VMs appear in Headscale node list with "connected" status
2. VM-A can ping VM-B successfully
3. VM-A can ping VM-C successfully
4. VM-B can ping VM-C successfully
5. VM automatically rejoins mesh after connectivity loss

### Implementation for User Story 1

- [ ] T016 [US1] Add Headscale namespace creation to setup script (headscale namespaces create default)
- [ ] T017 [US1] Add pre-authentication key generation to setup script (headscale preauthkeys create --reusable --expiration 24h)
- [ ] T018 [US1] Add preauth key injection to client VM configurations (pass via specialArgs or environment)
- [ ] T019 [US1] Implement Tailscale registration logic in tailscale-client module (tailscale up --login-server --authkey --accept-dns)
- [ ] T020 [US1] Add registration wait logic to setup script (poll until 3 nodes appear in headscale nodes list)
- [ ] T021 [US1] Extract mesh IPs from headscale CLI output in setup script (store in variables for test use)

### Validation for User Story 1

- [ ] T022 [US1] Create validation script at `test/multi-vm-headscale/orchestration/validate-us1-basic-connectivity.sh`
- [ ] T023 [US1] Implement node registration validation (verify 3 nodes in headscale nodes list with "online" status)
- [ ] T024 [US1] Implement bidirectional ping tests (node-1 ↔ node-2, node-1 ↔ node-3, node-2 ↔ node-3, total 6 tests)
- [ ] T025 [US1] Implement ping latency validation (confirm < 50ms for all pairs)
- [ ] T026 [US1] Implement connection status verification (all nodes show "connected" in tailscale status)
- [ ] T027 [US1] Implement reconnection test (tailscale down on node-1, wait, tailscale up, verify rejoin within 30s)
- [ ] T028 [US1] Integrate US1 validation into main test runner at `test/multi-vm-headscale/orchestration/run-connectivity-tests.sh`

**Checkpoint**: At this point, basic mesh connectivity is fully functional. You can ping between any VMs using mesh IPs. This is the MVP!

---

## Phase 4: User Story 2 - Cross-Network Communication (Priority: P2)

**Goal**: Validate VMs on different subnets communicate via mesh (simulates home network → cloud VPS scenario)

**Independent Test**: Verify node-1 (subnet-a: 192.168.1.10) can ping nodes 2&3 (subnet-b: 10.0.0.10, 10.0.0.11) via mesh IPs, confirm direct physical IP ping fails (network isolation)

**Acceptance Criteria from spec.md**:
1. VM-A (192.168.1.0/24) can reach VM-B (10.0.0.0/24) via mesh IP
2. Traffic routed through encrypted WireGuard tunnel, not underlying network
3. Communication succeeds despite restrictive firewall (simulated by network isolation)

### Implementation for User Story 2

- [ ] T029 [US2] Verify VM network attachments in VM configurations (node-1 on subnet-a, nodes 2&3 on subnet-b)
- [ ] T030 [US2] Add physical IP extraction to setup script (query via `ssh root@<vm> "ip addr show"` for each node's physical interface)
- [ ] T031 [US2] Add WireGuard tunnel status check utility to vm-utils.sh (extract endpoint info from tailscale status)

### Validation for User Story 2

- [ ] T032 [US2] Create validation script at `test/multi-vm-headscale/orchestration/validate-us2-cross-network.sh`
- [ ] T033 [US2] Implement cross-subnet connectivity test (node-1 ping nodes 2&3 via mesh IPs, verify success)
- [ ] T034 [US2] Implement WireGuard tunnel verification (confirm traffic shows "via <physical-endpoint>" in tailscale ping output)
- [ ] T035 [US2] Implement network isolation test (direct ping from 192.168.1.10 to 10.0.0.10 should fail - no route)
- [ ] T036 [US2] Integrate US2 validation into main test runner

**Checkpoint**: Cross-network communication validated. Mesh works across subnet boundaries.

---

## Phase 5: User Story 3 - Service Binding to Mesh Network (Priority: P3)

**Goal**: Verify services can bind exclusively to mesh interface, accessible only via mesh network

**Independent Test**: Deploy nginx on node-1 bound to mesh IP only, verify accessible from nodes 2&3 via mesh, NOT accessible from physical network

**Acceptance Criteria from spec.md**:
1. nginx listening on mesh interface responds to HTTP requests from mesh peers
2. External client connecting to physical IP fails (connection refused/timeout)
3. nginx accessible from different subnet (node-2/3 → node-1) via mesh IP
4. Hostname-based access works (http://client-node-1.mesh.internal)

### Implementation for User Story 3

- [ ] T037 [US3] Create nginx configuration template for mesh-only binding at `test/multi-vm-headscale/vms/nginx-mesh-config.nix`
- [ ] T038 [US3] Add nginx service to client-node-1 VM configuration (bind to mesh IP, listen on port 80)
- [ ] T039 [US3] Add nginx deployment to setup script (rebuild client-node-1 with nginx enabled, restart VM if needed)
- [ ] T040 [US3] Add mesh interface detection utility to vm-utils.sh (extract tailscale0 IP address)

### Validation for User Story 3

- [ ] T041 [US3] Create validation script at `test/multi-vm-headscale/orchestration/validate-us3-service-binding.sh`
- [ ] T042 [US3] Implement nginx binding verification (ssh to node-1, run `ss -tlnp | grep nginx`, confirm bound to 100.64.x.x:80 not 0.0.0.0)
- [ ] T043 [US3] Implement mesh accessibility test (curl from node-2 and node-3 to node-1 mesh IP, verify HTTP 200 response)
- [ ] T044 [US3] Implement physical network isolation test (attempt curl from host or node-2 to node-1 physical IP, expect connection refused)
- [ ] T045 [US3] Implement hostname-based access test (curl http://client-node-1.mesh.internal from node-2, verify success)
- [ ] T046 [US3] Implement cross-subnet service access test (curl from node-3 on subnet-b to node-1 on subnet-a via mesh)
- [ ] T047 [US3] Integrate US3 validation into main test runner

**Checkpoint**: Service binding validated. nginx only accessible via mesh, demonstrating security isolation.

---

## Phase 6: User Story 4 - Distributed DNS Resolution (Priority: P4)

**Goal**: Verify MagicDNS provides hostname resolution across mesh network

**Independent Test**: Query hostname of each node from all other nodes, verify resolution to correct mesh IP in < 1 second

**Acceptance Criteria from spec.md**:
1. VM-A can resolve VM-B's hostname to correct mesh IP
2. New VM's hostname resolves on all existing nodes within 30 seconds of joining
3. Hostname changes propagate to all nodes
4. Deregistered VM's hostname returns NXDOMAIN

### Implementation for User Story 4

- [ ] T048 [US4] Verify MagicDNS enabled in Headscale server configuration (magic_dns: true, base_domain: mesh.internal in modules/headscale-server/default.nix)
- [ ] T049 [US4] Verify Tailscale clients accept DNS (--accept-dns=true in registration command in modules/tailscale-client/default.nix)
- [ ] T050 [US4] Add DNS resolution test utility to validation-utils.sh (nslookup wrapper with timeout and validation)

### Validation for User Story 4

- [ ] T051 [US4] Create validation script at `test/multi-vm-headscale/orchestration/validate-us4-dns-resolution.sh`
- [ ] T052 [US4] Implement hostname resolution matrix test (node-1 resolves node-2/3, node-2 resolves node-1/3, node-3 resolves node-1/2, total 6 tests)
- [ ] T053 [US4] Implement DNS resolution latency test (verify all queries complete in < 1 second)
- [ ] T054 [US4] Implement DNS server verification (confirm queries go to Tailscale resolver 100.100.100.100 not system resolver)
- [ ] T055 [US4] Implement new node DNS propagation test (add temporary 4th node, verify hostname resolves within 30s on existing nodes)
- [ ] T056 [US4] Implement DNS negative test (deregister node-3, verify hostname query from node-1 returns NXDOMAIN)
- [ ] T057 [US4] Integrate US4 validation into main test runner

**Checkpoint**: All user stories validated. Full mesh networking with encrypted tunnels, cross-network communication, service isolation, and DNS resolution working end-to-end.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup, documentation, and final integration

- [ ] T058 [P] Create main test orchestration script at `test/multi-vm-headscale/orchestration/run-connectivity-tests.sh` (execute US1-US4 validations sequentially, halt on first failure)
- [ ] T059 [P] Create cleanup script at `test/multi-vm-headscale/orchestration/cleanup-test-env.sh` (deregister nodes, destroy VMs, remove networks)
- [ ] T060 [P] Create test suite README at `test/multi-vm-headscale/README.md` (quickstart instructions, troubleshooting)
- [ ] T061 [P] Add logging infrastructure to orchestration scripts (timestamped logs to orchestration/logs/ directory)
- [ ] T062 [P] Add error handling and rollback to setup script (cleanup on failure, descriptive error messages)
- [ ] T063 Add pre-flight checks to setup script (verify libvirt running, sufficient disk space, nix available)
- [ ] T064 Add success summary to test runner (total passed/failed, execution time, mesh IP assignments)
- [ ] T065 Verify quickstart.md accuracy (run through steps, update any outdated commands or outputs)
- [ ] T066 [P] Add bash script linting (shellcheck) to all orchestration scripts
- [ ] T067 Final end-to-end test (execute setup → US1 → US2 → US3 → US4 → cleanup, verify all pass)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational (Phase 2) completion
  - User Story 1 (P1): MUST complete first - establishes basic mesh connectivity
  - User Story 2 (P2): Depends on US1 - requires working mesh to test cross-network
  - User Story 3 (P3): Depends on US1 - requires working mesh to test service binding
  - User Story 4 (P4): Depends on US1 - requires working mesh to test DNS resolution
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories (MVP!)
- **User Story 2 (P2)**: Can start after US1 complete - Uses US1's mesh connectivity + adds cross-network validation
- **User Story 3 (P3)**: Can start after US1 complete - Uses US1's mesh connectivity + adds nginx service binding
- **User Story 4 (P4)**: Can start after US1 complete - Uses US1's mesh connectivity + adds DNS resolution

**Note**: US2, US3, US4 are relatively independent of each other (all build on US1), but in practice should be implemented sequentially (P2→P3→P4) for easier debugging.

### Within Each User Story

- Implementation tasks before validation tasks
- VM configurations before orchestration scripts
- Bash utilities before validation scripts that use them
- Individual validation tests can run in parallel (but orchestration script runs them sequentially for clarity)

### Parallel Opportunities

- **Phase 1 (Setup)**: T003, T004, T005, T006, T007 can all run in parallel (different files)
- **Phase 2 (Foundational)**: T010, T011, T012, T013 can run in parallel (different VM configs)
- **Phase 7 (Polish)**: T058, T059, T060, T061, T062, T066 can run in parallel (different files)

**Within User Stories**: Implementation tasks marked [P] within same story can run in parallel

---

## Parallel Example: Phase 1 Setup

```bash
# Launch all setup tasks together (different files, no dependencies):
Task: "Create libvirt network XML for subnet-a at test/multi-vm-headscale/networks/subnet-a.xml"
Task: "Create libvirt network XML for subnet-b at test/multi-vm-headscale/networks/subnet-b.xml"
Task: "Create bash library for VM utilities at test/multi-vm-headscale/orchestration/lib/vm-utils.sh"
Task: "Create bash library for validation utilities at test/multi-vm-headscale/orchestration/lib/validation-utils.sh"
Task: "Create configuration file at test/multi-vm-headscale/orchestration/config.sh"
```

---

## Parallel Example: Phase 2 Foundational VM Configurations

```bash
# Launch all VM configuration tasks together (different files):
Task: "Create Headscale server VM configuration at test/multi-vm-headscale/vms/headscale-server.nix"
Task: "Create client-node-1 VM configuration at test/multi-vm-headscale/vms/client-node-1.nix"
Task: "Create client-node-2 VM configuration at test/multi-vm-headscale/vms/client-node-2.nix"
Task: "Create client-node-3 VM configuration at test/multi-vm-headscale/vms/client-node-3.nix"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T007) → Project structure ready
2. Complete Phase 2: Foundational (T008-T015) → VMs can be built and started
3. Complete Phase 3: User Story 1 (T016-T028) → Basic mesh connectivity working
4. **STOP and VALIDATE**: Run validate-us1-basic-connectivity.sh
5. **SUCCESS**: You now have 3 VMs in a working mesh network! Can ping between any nodes. This is the MVP.

### Incremental Delivery

1. Complete Setup + Foundational → VMs deployable
2. Add User Story 1 → Test independently → **Demo: Basic mesh network works!**
3. Add User Story 2 → Test independently → **Demo: Cross-network communication works!**
4. Add User Story 3 → Test independently → **Demo: Service isolation on mesh works!**
5. Add User Story 4 → Test independently → **Demo: DNS resolution works!**
6. Each story adds value without breaking previous stories

### Sequential Execution (Recommended)

Since this is infrastructure testing with interdependencies:

1. Phase 1 (Setup): Parallel where possible (network XMLs, bash libs)
2. Phase 2 (Foundational): Parallel VM configs, then build/deploy sequentially
3. Phase 3 (US1): Complete fully before proceeding
4. Phase 4 (US2): Complete fully (builds on US1)
5. Phase 5 (US3): Complete fully (builds on US1)
6. Phase 6 (US4): Complete fully (builds on US1)
7. Phase 7 (Polish): Final integration and documentation

**Rationale for sequential user stories**: Each story validates a different aspect of the same mesh network. Running them sequentially makes debugging easier (isolates failures). US2-US4 could technically run in parallel, but sequential is more practical for troubleshooting.

---

## Task Summary

**Total Tasks**: 67

**Tasks per Phase**:
- Phase 1 (Setup): 7 tasks (5 parallelizable)
- Phase 2 (Foundational): 8 tasks (4 parallelizable)
- Phase 3 (US1 - MVP): 13 tasks
- Phase 4 (US2): 8 tasks
- Phase 5 (US3): 11 tasks
- Phase 6 (US4): 10 tasks
- Phase 7 (Polish): 10 tasks (6 parallelizable)

**Tasks per User Story**:
- US1 (Basic Mesh Connectivity): 13 tasks (MVP core)
- US2 (Cross-Network Communication): 8 tasks
- US3 (Service Binding): 11 tasks
- US4 (Distributed DNS): 10 tasks

**Parallel Opportunities**: 15 tasks marked [P] (22% of total) - can be executed concurrently within their phases

**Independent Testing**: Each user story has dedicated validation script and can be tested independently after US1 (MVP) is complete.

**Suggested MVP Scope**: Phase 1 + Phase 2 + Phase 3 (User Story 1) = 28 tasks = Basic mesh connectivity validated

---

## Notes

- [P] tasks = different files, no dependencies within that phase
- [Story] label maps task to specific user story for traceability
- Each user story should be independently validatable via its validate-usX-*.sh script
- Bash scripts use `set -euo pipefail` for halt-on-first-failure behavior
- Validation scripts exit with code 1 on first assertion failure (per spec.md requirement)
- VM configurations use NixOS declarative modules (per constitution requirement)
- Commit after each task or logical group of related tasks
- Test execution via: `./orchestration/setup-test-env.sh && ./orchestration/run-connectivity-tests.sh`
- Cleanup via: `./orchestration/cleanup-test-env.sh`
