# Feature Specification: TUI Local Installer

**Feature Branch**: `011-tui-local-installer`
**Created**: 2025-12-07
**Status**: Draft
**Input**: User description: "Users would like a TUI installer that supports local installation without requiring network access. The installer should create a local NixOS flake configuration at ~/nixos-config/ with proper host folder structure and be transparent about all file operations."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Network Setup and Status Display (Priority: P1)

A user boots the Keystone ISO on their target machine and sees the TUI installer. The installer automatically detects network connectivity (Ethernet or WiFi) and displays the current network status with IP addresses. If no network is available, the user can configure WiFi through the TUI.

**Why this priority**: Network connectivity is the foundation for both remote (SSH) and local installation workflows. Without knowing the network status and IP address, users cannot proceed with any installation method.

**Independent Test**: Can be fully tested by booting ISO in VM, verifying network detection, and confirming IP address display. Delivers immediate value by showing users their connectivity status.

**Acceptance Scenarios**:

1. **Given** the ISO is booted with Ethernet connected, **When** the installer starts, **Then** it displays "Network Connected" with the interface name and IP address within 5 seconds
2. **Given** the ISO is booted without network, **When** the installer starts, **Then** it displays a prompt to configure WiFi or proceed without network
3. **Given** WiFi configuration is selected, **When** the user selects a network and enters credentials, **Then** the installer connects and displays the obtained IP address

---

### User Story 2 - Installation Method Selection (Priority: P1)

After network setup, the user is presented with clear installation options: (A) Remote installation via SSH from another machine, (B) Local installation on this machine, or (C) Clone from an existing git repository. Each option includes a brief description of when to use it.

**Why this priority**: Users need to understand their options and choose the appropriate installation path. This is the critical decision point that determines the rest of the workflow.

**Independent Test**: Can be tested by navigating to the method selection screen and verifying all options are displayed with descriptions. Delivers value by educating users about their choices.

**Acceptance Scenarios**:

1. **Given** network setup is complete, **When** the user proceeds, **Then** they see three installation methods with descriptions
2. **Given** the installation methods are displayed, **When** the user selects "Remote via SSH", **Then** they see instructions with the nixos-anywhere command including their IP address
3. **Given** the installation methods are displayed, **When** the user selects "Local installation", **Then** they proceed to disk selection

---

### User Story 3 - Local Installation with Disk Selection (Priority: P2)

A user chooses local installation and selects a target disk from detected storage devices. The installer warns about data destruction and requires explicit confirmation before proceeding.

**Why this priority**: Local installation is the primary new capability being added. It enables users without a second machine to complete installation.

**Independent Test**: Can be tested by selecting local installation, viewing disk list, and verifying warning/confirmation flow. Delivers value by enabling standalone installation.

**Acceptance Scenarios**:

1. **Given** local installation is selected, **When** the disk selection screen loads, **Then** all detected storage devices are listed with size and model information
2. **Given** a disk is selected, **When** the user confirms selection, **Then** a warning about data destruction is displayed requiring explicit confirmation
3. **Given** the user confirms disk selection, **When** installation proceeds, **Then** the installer partitions, formats, and installs NixOS to the selected disk

---

### User Story 4 - Host Configuration Creation (Priority: P2)

During installation, the installer creates a NixOS flake configuration at ~/nixos-config/ with a host-specific folder containing disk-config.nix, hardware-configuration.nix, and default.nix. The user provides a hostname, and the installer transparently shows each file being created.

**Why this priority**: Creating proper configuration structure is essential for users to manage their system after installation. Transparency builds user familiarity with NixOS.

**Independent Test**: Can be tested by completing installation and verifying file structure exists with correct content. Delivers value by providing a working, manageable configuration.

**Acceptance Scenarios**:

1. **Given** installation is in progress, **When** the hostname prompt appears, **Then** the user can enter a valid hostname (alphanumeric, hyphens, 1-63 characters)
2. **Given** a hostname is provided, **When** configuration files are created, **Then** the installer displays each file path and a summary of what it contains
3. **Given** configuration is complete, **When** the user reviews the output, **Then** they see ~/nixos-config/hosts/{hostname}/ containing disk-config.nix, hardware-configuration.nix, and default.nix
4. **Given** the OS is installed on the target disk, **When** the installer finalizes, **Then** the configuration directory is copied from the live ISO environment to the installed system's home directory

---

### User Story 5 - Clone from Existing Repository (Priority: P3)

A user who already has a NixOS flake configuration in a git repository can clone it during installation and select a host configuration to deploy.

**Why this priority**: Supports advanced users who want to reinstall or deploy existing configurations. Lower priority because it requires pre-existing configuration.

**Independent Test**: Can be tested by providing a git URL, cloning, and selecting a host. Delivers value for users with existing configurations.

**Acceptance Scenarios**:

1. **Given** "Clone from repository" is selected, **When** the repository URL prompt appears, **Then** the user can enter a git URL (HTTPS or SSH format)
2. **Given** a valid repository URL is entered, **When** cloning completes, **Then** the installer lists available host configurations from the hosts/ folder
3. **Given** a host is selected from the cloned repository, **When** installation proceeds, **Then** the system is deployed using that host's configuration

---

### User Story 6 - File Operations Transparency (Priority: P3)

Throughout the installation process, the installer clearly shows all file operations: files created, files modified, and the purpose of each change. This helps users learn NixOS conventions.

**Why this priority**: Educational value and user trust. Users build familiarity with NixOS structure, reducing future support needs.

**Independent Test**: Can be tested by observing file operation logs during any installation flow. Delivers value by building user knowledge.

**Acceptance Scenarios**:

1. **Given** any file is created, **When** the operation completes, **Then** the installer displays the full path and a one-line description of the file's purpose
2. **Given** any file is modified, **When** the operation completes, **Then** the installer displays the file path and what was changed
3. **Given** installation completes, **When** the summary screen appears, **Then** it lists all files created/modified with their locations

---

### Edge Cases

- What happens when no disks are detected? Display error message and suggest checking hardware connections
- What happens when disk partitioning fails? Display error, offer to retry or select different disk
- What happens when git clone fails? Display error with reason (network, auth, invalid URL) and allow retry
- What happens when hostname conflicts with existing host folder? Prompt user to overwrite, rename, or cancel
- What happens when ~/nixos-config/ already exists? Offer to use existing, backup and create new, or cancel
- How does the installer handle network disconnection mid-installation? Checkpoint progress and allow resume when reconnected
- What happens when the user presses Ctrl+C during installation? Confirm exit, warn about incomplete state, offer to continue or abort
- What happens if copying configuration files to the installed disk fails? Display error with reason, offer retry, and warn that config files exist only in RAM until successfully copied

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Installer MUST auto-start on TTY1 when ISO boots
- **FR-002**: Installer MUST detect and display all network interfaces with IP addresses
- **FR-003**: Installer MUST support WiFi configuration via interactive SSID selection and password entry
- **FR-004**: Installer MUST display three installation methods: Remote (SSH), Local, and Clone Repository
- **FR-005**: Installer MUST detect and list all block storage devices with size and model information
- **FR-006**: Installer MUST require explicit confirmation before any destructive disk operations
- **FR-007**: Installer MUST create configuration directory at ~/nixos-config/ by default
- **FR-008**: Installer MUST create host-specific folder structure: hosts/{hostname}/disk-config.nix, hardware-configuration.nix, default.nix
- **FR-009**: Installer MUST display each file operation with path and purpose as it occurs
- **FR-010**: Installer MUST validate hostname format (alphanumeric and hyphens, 1-63 characters)
- **FR-011**: Installer MUST support cloning git repositories via HTTPS or SSH URLs
- **FR-012**: Installer MUST initialize a git repository in ~/nixos-config/ for new installations
- **FR-013**: Installer MUST generate hardware-configuration.nix based on detected hardware
- **FR-014**: Installer MUST allow navigation back to previous screens without losing entered data
- **FR-015**: Installer MUST provide clear error messages with suggested remediation actions
- **FR-016**: Installer MUST copy the configuration directory from the live ISO environment to the installed system's home directory after OS installation completes (since the live ISO runs in RAM, files must be persisted to the target disk)

### Key Entities

- **Host Configuration**: A collection of NixOS configuration files for a specific machine, identified by hostname. Contains disk configuration, hardware configuration, and system defaults.
- **Installation Method**: The approach used to deploy NixOS (Remote/SSH, Local, Clone). Determines workflow and required user inputs.
- **Storage Device**: A block device (disk, NVMe, etc.) that can be selected as installation target. Has attributes: path, size, model, current partitions.
- **Network Interface**: A detected network adapter (Ethernet or WiFi) with connection status and IP address when connected.
- **Configuration Directory**: The root directory (~/nixos-config/) containing the NixOS flake and all host configurations.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete local installation from ISO boot to working system in under 15 minutes (excluding download time)
- **SC-002**: 95% of users who start the installer successfully reach the installation method selection screen
- **SC-003**: All file operations during installation are displayed to the user with path and purpose
- **SC-004**: Users without network access can complete local installation using the TUI
- **SC-005**: The generated ~/nixos-config/ structure allows users to rebuild their system with `nixos-rebuild switch` after installation
- **SC-006**: Error messages include actionable remediation steps, reducing user confusion
- **SC-007**: Users can navigate back to correct mistakes without restarting the installer

## Assumptions

- Users have basic familiarity with terminal interfaces (can read text, use arrow keys, press Enter)
- Target machines have at least one storage device with sufficient space for NixOS (minimum 8GB)
- The ISO includes all necessary tools for disk partitioning, formatting, and NixOS installation
- WiFi hardware is supported by the Linux kernel included in the ISO
- Users installing via "Clone Repository" have valid git credentials configured if using SSH URLs
- The installer runs as root with full system access
- The live ISO environment runs entirely in RAM; any files created during installation (including ~/nixos-config/) exist only in memory until explicitly copied to the target disk
- The installed system's disk is mounted at a known location (e.g., /mnt) during installation, allowing the installer to copy configuration files to the final destination before unmounting
- The default configuration directory will be placed in the primary user's home directory on the installed system (e.g., /mnt/home/{user}/nixos-config/ during install, becoming ~/nixos-config/ after reboot)
