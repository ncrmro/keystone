# Feature Specification: SSH-Enabled ISO with VM Testing

**Feature Branch**: `001-ssh-iso-vm-testing`
**Created**: 2025-10-16
**Status**: Draft (Updated)
**Input**: User description: "User should be able to build an iso with their public ssh key and be able to ssh into a vm created using quickemu."

## Current Implementation Status

**Note**: This feature builds upon existing work in the `feat/quickemu-server` branch.

### Already Implemented ✅
- **ISO Building with SSH Keys** (`bin/build-iso` script)
  - Accepts SSH keys via file path (`--ssh-key ~/.ssh/id_ed25519.pub`)
  - Accepts SSH keys via string input (`--ssh-key "ssh-ed25519..."`)
  - Validates SSH key format
  - Embeds keys in ISO via `modules/iso-installer.nix`
- **Basic Quickemu Configuration** (`vms/server.conf`)
  - VM configuration file exists
  - SSH port forwarding configured (port 22220)
  - Makefile target `make vm-server` to launch VM

### Remaining Work 🚧
- Automated VM lifecycle management
- SSH connection helper/display
- Integration testing workflow

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automated VM Testing Workflow (Priority: P1)

A developer wants to quickly test a Keystone ISO by launching it in a VM and connecting via SSH using a single streamlined workflow.

**Why this priority**: While individual components exist (ISO building, quickemu config), they need to be integrated into a cohesive testing workflow that reduces manual steps and potential errors.

**Independent Test**: Can be fully tested by running a single command that builds an ISO, launches a VM, and provides SSH connection details.

**Acceptance Scenarios**:

1. **Given** a developer has an SSH public key, **When** they run the VM test command, **Then** the system builds an ISO with their key, launches a VM, and displays SSH connection instructions
2. **Given** an ISO already exists with SSH keys, **When** they run the VM launch command, **Then** a VM starts and SSH connection details are displayed
3. **Given** a VM is already running, **When** they run the VM status command, **Then** current VM state and SSH connection details are shown

---

### User Story 2 - VM Lifecycle Management (Priority: P2)

A developer wants to manage VM lifecycle (start, stop, status, clean) without manually editing configuration files or running complex quickemu commands.

**Why this priority**: Developers need simple commands to manage test VMs without quickemu expertise, preventing resource waste from forgotten VMs.

**Independent Test**: Can be fully tested by starting, checking status, stopping, and cleaning up a VM using dedicated commands.

**Acceptance Scenarios**:

1. **Given** no VM is running, **When** a developer runs the start command, **Then** a new VM launches with the current ISO
2. **Given** a VM is running, **When** a developer runs the stop command, **Then** the VM shuts down gracefully
3. **Given** any VM state, **When** a developer runs the status command, **Then** current VM state and process information is displayed
4. **Given** VM artifacts exist, **When** a developer runs the clean command, **Then** VM disk and state files are removed

---

### User Story 3 - SSH Connection Helper (Priority: P3)

A developer wants the system to automatically detect and display the correct SSH connection command based on the current VM and key configuration.

**Why this priority**: This eliminates guesswork about ports, usernames, and key paths, making the testing process more efficient.

**Independent Test**: Can be fully tested by verifying correct SSH command generation for various configurations.

**Acceptance Scenarios**:

1. **Given** a VM is running with SSH forwarding, **When** a developer requests connection info, **Then** the exact SSH command with correct port and key is displayed
2. **Given** multiple SSH keys were embedded, **When** connection info is shown, **Then** instructions indicate which keys will work
3. **Given** the VM's SSH service is ready, **When** the provided SSH command is executed, **Then** connection succeeds without additional configuration

---

### Edge Cases

- What happens when quickemu is not installed or available on the system?
- How does the system handle port conflicts when the default SSH port (22220) is already in use?
- What happens when the ISO file is missing or corrupted during VM launch?
- How does the system handle VMs that fail to boot or hang during startup?
- What happens when trying to launch a second VM while one is already running?
- How does the system handle stale VM state files from crashed instances?

## Requirements *(mandatory)*

### Functional Requirements

#### Already Implemented ✅
- **FR-001**: ✅ System accepts SSH public key input during ISO build via file path
- **FR-002**: ✅ System accepts SSH public key input during ISO build via direct string input
- **FR-003**: ✅ System generates bootable installer ISO with embedded SSH authorized_keys configuration
- **FR-004**: ✅ System validates SSH public key format before embedding in ISO
- **FR-005**: ✅ System configures SSH service to start automatically when ISO boots
- **FR-009**: ✅ System supports building ISO without SSH keys (original behavior)
- **FR-010**: ✅ System uses secure defaults for SSH configuration (disable password auth when key is present)

#### Remaining Requirements 🚧
- **FR-006**: System MUST provide integrated command to build ISO and launch VM in one step
- **FR-007**: System MUST display SSH connection command with correct port and authentication details
- **FR-008**: System MUST detect if quickemu is installed and provide clear error if missing
- **FR-011**: System MUST manage VM lifecycle (start, stop, status) through simple commands
- **FR-012**: System MUST detect and handle port conflicts for SSH forwarding
- **FR-013**: System MUST verify ISO exists and is valid before VM launch
- **FR-014**: System MUST provide VM status information (running, stopped, not created)
- **FR-015**: System MUST clean up VM artifacts (disk, logs, state) on request
- **FR-016**: System MUST wait for SSH service availability before declaring VM ready
- **FR-017**: System MUST preserve existing quickemu configuration compatibility

### Key Entities

- **VM Configuration**: quickemu settings in `vms/server.conf` (already exists)
- **VM State**: Runtime information including PID, ports, disk location
- **SSH Connection Info**: Port mapping (22220), username (root), key requirements
- **VM Artifacts**: Disk image, OVMF vars, logs, port files in `vms/server/`
- **Build Artifacts**: ISO file in `vms/keystone-installer.iso`

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Complete test workflow (build ISO → launch VM → SSH connect) executable in under 3 minutes
- **SC-002**: SSH connection available within 30 seconds of VM boot completion
- **SC-003**: Single command launches VM and displays connection details without manual steps
- **SC-004**: VM lifecycle commands (start/stop/status/clean) complete in under 5 seconds
- **SC-005**: 100% success rate for SSH connections when using displayed connection command
- **SC-006**: Clear error messages provided for all failure scenarios (missing quickemu, port conflicts, etc.)