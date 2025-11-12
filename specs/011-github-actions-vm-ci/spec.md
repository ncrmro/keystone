# Feature Specification: GitHub Copilot Agent VM Access for System Configuration Testing

**Feature Branch**: `011-github-actions-vm-ci`
**Created**: 2025-11-12
**Status**: Draft
**Input**: User description: "We need to get Github Actions to be able to create a VM and install nixos in it, this is to enable nicer CI. But more so it so allow github copilot agent to be able to iterate on the nix flake by setting up a vim in @.github/workflows/copilot-setup-steps.yml . Ideally using https://github.com/etchdroid/qemu-kvm-action and nixos-rebuilds built in ability to create vms if possible."

## Clarifications

### Session 2025-11-12

- Q: How should the system handle multiple simultaneous workflow executions triggered by the same or different Copilot agents? → A: Queue with single active run per branch - One workflow runs at a time per branch; subsequent triggers queue and auto-cancel older pending runs
- Q: What structured format should the system use to return test execution results to Copilot agents? → A: JSON with predefined schema - Structured JSON object with fields for status, phase, errors, logs, timestamps
- Q: What should happen when a VM successfully boots but the system initialization hangs indefinitely? → A: Timeout with partial results - Wait up to 5 minutes for boot completion; if timeout occurs, return partial logs showing which services started and which are pending
- Q: How should the system handle network failures when fetching packages during the build process? → A: Fail immediately - Mark build as failed on first network error without retry
- Q: What should the system do when hardware acceleration (KVM) is unavailable on the CI runner? → A: Fail immediately - Mark workflow as failed if hardware acceleration is not available (to be addressed if this issue arises)

## User Scenarios & Testing

### User Story 1 - Copilot Agent Iterative Configuration Development (Priority: P1)

GitHub Copilot agents can access a running VM to test system configurations, receive feedback about what works or fails, and iteratively refine configurations based on real execution results.

**Why this priority**: This is the core value proposition. Copilot agents need a real environment to test system configurations because static analysis isn't sufficient for catching runtime issues like service failures, dependency problems, or boot issues. Without this, agents can only guess whether configurations work.

**Independent Test**: Can be fully tested by having a Copilot agent propose a configuration change, trigger the testing workflow, test the configuration in a VM, receive structured feedback, and propose an improved version based on the results.

**Acceptance Scenarios**:

1. **Given** a Copilot agent proposes a configuration modification, **When** the agent triggers the testing workflow, **Then** a VM is created and the configuration is tested, returning success/failure status with logs
2. **Given** a configuration that fails to build, **When** the Copilot agent receives the error output, **Then** the agent can parse the error messages and propose a corrected version
3. **Given** a successfully built configuration, **When** the VM attempts to boot and run the system, **Then** runtime errors (service failures, missing dependencies) are captured and returned to the agent
4. **Given** a working configuration, **When** the Copilot agent receives confirmation of success, **Then** the agent can finalize the changes or continue with additional modifications

---

### User Story 2 - VM Environment Provisioning in CI (Priority: P2)

The automated workflow provisions a VM environment with hardware acceleration where system configurations can be built, installed, and executed for testing purposes.

**Why this priority**: This is the infrastructure that enables P1. Without a reliable VM environment in the CI system, Copilot agents have nowhere to test their configurations. This must work before agent iteration is possible.

**Independent Test**: Can be fully tested by manually triggering the workflow and verifying that it successfully creates a VM, has system configuration tooling available, and can execute basic build and deployment commands.

**Acceptance Scenarios**:

1. **Given** the workflow is triggered, **When** the VM provisioning step executes, **Then** a VM is created with hardware acceleration enabled
2. **Given** a VM has been created, **When** querying available resources, **Then** the VM has sufficient CPU, memory, and disk space to build and run system configurations
3. **Given** the VM environment is ready, **When** configuration build commands are executed, **Then** package repositories are accessible and dependencies can be fetched
4. **Given** a workflow completes or is cancelled, **When** cleanup executes, **Then** all VM resources are released and temporary files are deleted

---

### User Story 3 - Automated Configuration Validation (Priority: P3)

Developers pushing system configuration changes automatically receive validation feedback through the same VM testing infrastructure used by Copilot agents, providing continuous integration benefits.

**Why this priority**: This is a valuable side benefit of having the VM infrastructure in place. Traditional CI workflows can leverage the same mechanism, but it's not the primary driver. The infrastructure exists primarily for Copilot agent iteration.

**Independent Test**: Can be fully tested by pushing a commit to a branch and verifying that the CI system automatically runs the VM-based validation and reports results.

**Acceptance Scenarios**:

1. **Given** a developer pushes a valid configuration change, **When** the CI workflow runs automatically, **Then** the configuration is tested in a VM and reports success
2. **Given** a developer pushes an invalid configuration, **When** the CI workflow runs, **Then** the workflow fails with specific error messages
3. **Given** a pull request is open, **When** viewing the PR status checks, **Then** the VM validation status is visible alongside other checks

---

### Edge Cases

- What happens when the VM creation times out or the CI platform runs out of available execution time?
- Network failures during package fetching: System fails immediately on first network error without retry, returning clear error messages indicating which package or repository was unreachable. Agents can re-trigger the workflow if they suspect transient network issues.
- Multiple concurrent workflow triggers: System queues workflow runs per branch, allowing only one active execution at a time. New triggers automatically cancel older pending runs in the queue, ensuring agents always test the latest configuration.
- Boot hangs and initialization delays: System waits up to 5 minutes for boot completion. If the boot process hangs or services fail to start within the timeout, the workflow returns partial results including logs showing which services successfully started and which are pending or failed, enabling agents to diagnose the specific hang point.
- Hardware acceleration unavailable: System fails immediately with clear error message if hardware acceleration (KVM) is not available on the CI runner. Fallback strategies will be addressed if this limitation becomes problematic.
- How does the workflow handle partial failures (build succeeds, installation fails, boot succeeds but services fail)?

## Requirements

### Functional Requirements

- **FR-001**: System MUST provide an automated workflow that GitHub Copilot agents can trigger to test configuration changes
- **FR-002**: System MUST create isolated virtual machine environments for testing configurations
- **FR-002a**: System MUST verify hardware acceleration availability and fail immediately with clear error message if not available
- **FR-003**: System MUST support building system configurations from flake-based definitions
- **FR-003a**: System MUST fail immediately on network errors during package fetching without retry attempts, providing clear error messages identifying the unreachable package or repository
- **FR-004**: System MUST test configurations through full lifecycle: build, installation, and boot verification
- **FR-004a**: System MUST implement a 5-minute timeout for boot completion, returning partial results with service startup status if timeout is exceeded
- **FR-005**: System MUST capture and return structured feedback as JSON with a predefined schema including fields for execution status, test phase, error details, logs, and timestamps that Copilot agents can parse programmatically
- **FR-006**: System MUST support testing both server and desktop system configurations
- **FR-007**: System MUST support iterative testing where multiple configuration attempts can be tested in sequence
- **FR-008**: System MUST queue workflow runs per branch, allowing only one active execution at a time, with new triggers automatically canceling older pending runs
- **FR-009**: System MUST clean up test environment resources after each workflow run to prevent resource exhaustion
- **FR-010**: System MUST report execution status in a way that both automated agents and human developers can access
- **FR-011**: System MUST distinguish between different failure modes (build errors, installation errors, runtime errors, service failures)
- **FR-012**: System MUST provide error messages that identify which phase of testing failed and why
- **FR-013**: System MUST complete typical test cycles within platform time limits for automated workflows

### Key Entities

- **System Configuration**: The declarative configuration definition being tested, including system modules, packages, and service definitions
- **Test Environment**: The isolated virtual machine instance where configurations are built, installed, and executed for validation
- **Automated Workflow**: The continuous integration process specifically designed for agent interaction, providing structured input/output interfaces
- **Test Execution Result**: A JSON-formatted structured output with predefined schema containing execution status (success/failure), test phase identifier (build/install/boot/runtime), error details, log excerpts, timestamps, and system state that agents use to make iterative decisions
- **Workflow Execution Context**: The runtime environment including available resources, environment metadata, and execution constraints

## Success Criteria

### Measurable Outcomes

- **SC-001**: Copilot agents can successfully test a system configuration and receive actionable feedback within 15 minutes
- **SC-002**: Agents can complete 3 or more test iterations (propose change → test → receive feedback → refine) within 30 minutes
- **SC-003**: Test results contain sufficient detail that agents correctly identify failure causes in 90% of failing configurations
- **SC-004**: VM creation and configuration testing completes within 10 minutes for standard system configurations
- **SC-005**: Workflow executions clean up resources successfully in 100% of runs (including cancellations and failures)
- **SC-006**: Copilot agents can distinguish between build-time failures, installation failures, and runtime failures based on returned data
- **SC-007**: Human developers can read and understand the same test output that agents consume, supporting manual debugging when needed

## Assumptions

- Continuous integration platform supports hardware-accelerated virtualization
- Automated agents can trigger workflows through standard platform APIs
- System configuration tooling is compatible with the CI environment
- Workflow execution time limits are sufficient for full build and test cycles
- Network bandwidth supports downloading system packages and dependencies
- The repository uses declarative, reproducible configuration definitions
- Automated agents can parse structured output formats for decision-making

## Dependencies

- CI platform permissions to create and manage virtual machines
- Virtualization support in CI runner environments
- System configuration tooling available in CI environment
- Network access to package repositories and binary caches
- Sufficient CI runner resources (CPU, memory, disk space) for VM operations
- Platform API access for agents to trigger and monitor workflows

## Scope Boundaries

### In Scope

- VM provisioning in CI environment for system configuration testing
- Workflow interface specifically designed for GitHub Copilot agent interaction
- Structured feedback mechanisms (build logs, error messages, execution status)
- Iterative testing capability allowing multiple test cycles
- Basic system health validation (boot success, critical services running)
- Resource cleanup after workflow execution
- Automated CI validation as a side benefit of the VM infrastructure

### Out of Scope

- Performance benchmarking or load testing of system configurations
- Security scanning or vulnerability assessment
- Production deployment automation
- Persistent VM instances that survive across workflow runs
- Interactive debugging or manual access to VMs during workflow execution
- Testing alternative operating systems or configuration formats beyond the project scope
- Integration testing between multiple VMs or distributed systems
- Advanced monitoring or telemetry collection from test VMs
