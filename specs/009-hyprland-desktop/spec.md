# Feature Specification: Hyprland Desktop Environment

**Feature Branch**: `009-hyprland-desktop`  
**Created**: 2025-11-06  
**Status**: Draft  
**Input**: User description: "we now need to create a desktop nix modules, it contains two parts the nixos module and the home-manager module. The modules work together to setup a hyprland desktop environment. Noting that most of the termal based work is handled in ./home-manager/modules/terminal-dev-environment/ . The desktop needs to ensure hyprlock, hypridle, chromium are installed. It should install ghostty, hyprpaper, waybar, mako. It should not be initially very configurable. # Essential Hyprland packages - cannot be excluded
  hyprlandPackages = with pkgs; [
    hyprshot
    hyprpicker
    hyprsunset
    brightnessctl
    pamixer
    playerctl
    gnome-themes-extra
    pavucontrol
    wl-clipboard
    glib
  ]; It should use uwsm app . Use greetd to laucnh the uswsm agin follow these for examples https://github.com/ncrmro/omarchy-nix/blob/feat/submodule-omarchy-arch/modules/nixos/system.nix"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Graphical Session Login (Priority: P1)

As a user, I want to boot my machine and be presented with a graphical login manager, so that I can log into my Hyprland desktop session.

**Why this priority**: This is the fundamental entry point to the entire desktop environment. Without it, no other desktop functionality is accessible.

**Independent Test**: A NixOS configuration with the new desktop module enabled can be built and deployed to a VM. On boot, the VM displays the `greetd` login prompt. The user can enter their credentials and successfully start a Hyprland session.

**Acceptance Scenarios**:

1. **Given** a NixOS system with the `keystone.client.desktop` module enabled, **When** the system boots, **Then** it MUST display a `greetd` graphical login screen.
2. **Given** the user is at the `greetd` login screen, **When** they enter valid credentials, **Then** a Hyprland desktop session managed by `uwsm` MUST be launched.

---

### User Story 2 - Basic Desktop Interaction (Priority: P2)

As a user, I want a minimal but functional desktop environment with a status bar, notifications, and essential applications so that I can perform basic tasks.

**Why this priority**: This provides the core interactive components of a modern desktop, making the system usable for day-to-day activities.

**Independent Test**: After logging in, the user's desktop displays a `waybar` status bar and a wallpaper set by `hyprpaper`. Opening a terminal and running `notify-send "test"` triggers a `mako` notification. The user can launch `chromium` and `ghostty`.

**Acceptance Scenarios**:

1. **Given** a user has logged into the Hyprland session, **When** the desktop loads, **Then** a `waybar` instance MUST be visible on screen.
2. **Given** the desktop is loaded, **When** a notification is triggered, **Then** `mako` MUST display it.
3. **Given** the desktop is loaded, **When** the user attempts to launch applications, **Then** `chromium` and `ghostty` MUST be available and launch successfully.

---

### User Story 3 - Session Security and Power Management (Priority: P3)

As a user, I want my session to automatically lock when idle and have basic power management controls, so that my session is secure and my hardware is managed efficiently.

**Why this priority**: Automatic locking is a critical security feature for any desktop environment.

**Independent Test**: Leave the desktop session idle. The screen should automatically lock using `hyprlock` after a predefined time. The user must be able to unlock it with their password.

**Acceptance Scenarios**:

1. **Given** a user is logged into a Hyprland session, **When** there is no user activity for a configured duration, **Then** `hypridle` MUST trigger `hyprlock` to lock the screen.
2. **Given** the screen is locked by `hyprlock`, **When** the user enters their correct password, **Then** the session MUST be unlocked.

### Edge Cases

- What happens if `greetd` fails to start? The system should ideally fall back to a TTY login.
- How does the system handle a missing `home-manager` configuration for a user? The session might fail to start or start with a broken default configuration.
- What happens if a user's hardware does not support some of the power management features (e.g., `brightnessctl`)? The system should not fail to build; the control will simply not work.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a NixOS module that sets up a graphical desktop environment based on Hyprland.
- **FR-002**: The system MUST provide a corresponding home-manager module for user-specific desktop configuration.
- **FR-003**: The NixOS module MUST install and configure `greetd` as the login manager to launch a `uwsm` session.
- **FR-004**: The NixOS module MUST install system-level packages including `hyprlock`, `hypridle`, and `chromium`.
- **FR-005**: The home-manager module MUST install user-level packages including `ghostty`, `hyprpaper`, `waybar`, `mako`, and the specified list of essential Hyprland packages (`hyprshot`, `hyprpicker`, etc.).
- **FR-006**: The initial configuration for the modules MUST be minimal and not expose a wide range of options.
- **FR-007**: The desktop environment MUST integrate with the existing `terminal-dev-environment` module for terminal-based functionality.

### Architectural Requirements

#### AR-001: Module Structure and Organization

**AR-001.1 - NixOS Module Structure**: The NixOS desktop components MUST be organized under `modules/client/desktop/` with the following structure:
- `hyprland.nix` - Core Hyprland compositor system configuration
- `greetd.nix` - Login manager (greetd) configuration
- `audio.nix` - PipeWire audio system configuration
- `packages.nix` - System-level desktop package declarations

**AR-001.2 - NixOS Service Structure**: System services related to desktop functionality MUST be organized under `modules/client/services/` with:
- `networking.nix` - NetworkManager configuration (client-specific networking needs)
- `system.nix` - System-level desktop services

**AR-001.3 - Home-Manager Module Structure**: The home-manager desktop components MUST be organized under `home-manager/modules/desktop/hyprland/` with the following structure:
- `default.nix` - Main orchestration module with enable options
- `hyprland-config.nix` - User-specific Hyprland configuration
- `waybar.nix` - Status bar user configuration
- `mako.nix` - Notification daemon user configuration
- `hyprpaper.nix` - Wallpaper manager user configuration
- `hyprlock.nix` - Screen locker user configuration
- `hypridle.nix` - Idle management user configuration

**Rationale**: This structure separates system-level concerns (NixOS modules) from user-level concerns (home-manager modules), allowing for cleaner configuration management and better composability.

#### AR-002: Package Placement Criteria

**AR-002.1 - System-Level Package Criteria**: Packages MUST be installed at the system level (NixOS) when they meet ANY of the following criteria:
- Required for system boot or login (e.g., `greetd`)
- Need root privileges or system services (e.g., `pipewire`, `NetworkManager`)
- Provide system-wide services used by multiple users
- Required before user login occurs
- Hardware-dependent system utilities (e.g., `brightnessctl` for hardware brightness control)

**AR-002.2 - User-Level Package Criteria**: Packages MUST be installed at the user level (home-manager) when they meet ALL of the following criteria:
- Do not require root privileges
- Provide user-specific functionality or configuration
- Can be configured differently per user
- Are launched within a user session (not system services)

**AR-002.3 - Specific Package Placement**: The following package placement MUST be implemented:
- **System-Level (NixOS)**: `chromium` (system-wide browser), system services for `pipewire`, `greetd`, `hyprland` (compositor itself)
- **User-Level (home-manager)**: `ghostty`, `waybar`, `mako`, `hyprpaper`, `hyprshot`, `hyprpicker`, `hyprsunset`, `pamixer`, `playerctl`, `pavucontrol`, `wl-clipboard`, `glib`
- **Dual-Level**: `hyprlock` and `hypridle` MAY be present at system level for service availability but MUST have user-specific configuration in home-manager

**AR-002.4 - Ambiguous Package Resolution**: When package placement is ambiguous, the default MUST be user-level (home-manager) unless the package requires system integration.

#### AR-003: Service Configuration Requirements

**AR-003.1 - Networking Service Placement**: NetworkManager configuration MUST reside in `modules/client/services/networking.nix` (not in server modules) because:
- Client devices need interactive network management (WiFi, VPN)
- Desktop users require GUI network controls
- Mobile/laptop clients have different networking patterns than servers

**AR-003.2 - Bluetooth Service Configuration**: Bluetooth support MUST be configured in `modules/client/services/networking.nix` because:
- Bluetooth is primarily used on client devices (peripherals, audio)
- Requires user interaction for pairing and management
- Not typically needed on headless servers

**AR-003.3 - Audio Service Configuration**: PipeWire audio MUST be configured in `modules/client/desktop/audio.nix` as a system service because:
- Provides system-wide audio server
- Manages hardware audio devices requiring system privileges
- Provides compatibility layers (ALSA, Pulse, Jack)

**AR-003.4 - Login Manager Configuration**: The `greetd` login manager MUST be configured in `modules/client/desktop/greetd.nix` because:
- Runs before user login as a system service
- Manages session launching with `uwsm`
- Requires root privileges for user authentication

**AR-003.5 - Service Dependencies**: The NixOS modules MUST declare system services that the home-manager modules depend on. Home-manager modules MUST NOT attempt to enable system services.

#### AR-004: Home-Manager Integration Requirements

**AR-004.1 - Core Components**: The initial home-manager desktop module MUST include at minimum:
- Hyprland user configuration (`hyprland-config.nix`)
- Status bar (`waybar.nix`)
- Terminal emulator package (`ghostty`)
- Essential Hyprland utilities (as listed in FR-005)

**AR-004.2 - Enable/Disable Options**: The home-manager module MUST provide:
- Top-level `programs.desktop.hyprland.enable` option
- Component-specific enable options under `programs.desktop.hyprland.components.*`
- All component options MUST default to `true` except the top-level enable

**AR-004.3 - NixOS to Home-Manager Reference**: Home-manager modules MAY reference NixOS configuration state (e.g., `config.programs.hyprland.withUWSM`) but MUST NOT modify NixOS options.

**AR-004.4 - User-Specific Configuration**: The home-manager module MUST support configuration per user, allowing different users on the same system to have different desktop setups.

**AR-004.5 - Terminal Integration**: The desktop module MUST integrate with the existing `terminal-dev-environment` home-manager module without duplication of terminal functionality. `ghostty` package installation MAY reside in either module, but configuration MUST be in `terminal-dev-environment`.

**AR-004.6 - Multiple User Support**: The architecture MUST support multiple users with different desktop needs on the same system. Users who do not enable the home-manager desktop module MUST still be able to log in (falling back to a basic Hyprland session).

**AR-004.7 - Activation Mechanism**: The home-manager configuration MUST be activated through the standard home-manager activation process. The NixOS module MUST NOT assume home-manager is installed.

#### AR-005: Module Import and Export Requirements

**AR-005.1 - NixOS Module Imports**: The main `modules/client/default.nix` MUST import all desktop and service modules. Individual modules MUST be importable independently.

**AR-005.2 - Home-Manager Module Imports**: The main `home-manager/modules/desktop/hyprland/default.nix` MUST import all component modules.

**AR-005.3 - Flake Exports**: The repository flake MUST export:
- `nixosModules.client` - The complete client module including desktop
- `homeManagerModules.desktop-hyprland` - The home-manager desktop module (as a distinct export)

**AR-005.4 - Option Namespacing**: NixOS options MUST use the namespace `keystone.client.*`. Home-manager options MUST use the namespace `programs.desktop.hyprland.*`.

**AR-005.5 - Module Documentation**: Each module MUST include inline documentation describing its purpose and key options using NixOS module system documentation features.

#### AR-006: Test Verification Requirements

**AR-006.1 - Test Script Purpose**: A test script MUST verify the presence and basic functionality of the desktop environment after deployment.

**AR-006.2 - Basic Presence Checks**: The test script MUST verify:
1. Greetd service is running (`systemctl status greetd`)
2. Hyprland is available in PATH
3. PipeWire services are active
4. Essential packages are installed (chromium, ghostty, waybar, mako)
5. NetworkManager is active

**AR-006.3 - Home-Manager Verification**: The test script MUST:
- Detect if home-manager is activated for the current user
- If activated, verify home-manager packages are in user PATH
- If not activated, report this state without failing

**AR-006.4 - Test Script Location**: The test script MUST be located at `bin/test-desktop` and follow the existing project testing conventions.

**AR-006.5 - Success Criteria**: The test MUST pass if all system-level components are present and active. Home-manager component presence is informational only.

**AR-006.6 - Failure Reporting**: The test script MUST clearly indicate which component failed and provide diagnostic information (service status, package availability).

#### AR-007: Backward Compatibility and Migration

**AR-007.1 - No Backward Compatibility Required**: As this is a new feature with no prior desktop implementation in this repository, backward compatibility is NOT required.

**AR-007.2 - Future Stability**: Once released, the module structure and option names MUST remain stable. Any future structural changes MUST provide migration paths.

**AR-007.3 - External Configuration Support**: The modules MUST support being imported into external flakes without requiring specific directory structures in those flakes.

#### AR-008: Edge Cases and Error Handling

**AR-008.1 - Missing Home-Manager**: When home-manager is not installed or activated, the system MUST:
- Still provide a functional Hyprland session
- Fall back to system-provided packages only
- Provide clear documentation about reduced functionality

**AR-008.2 - Hardware Compatibility**: The modules MUST gracefully handle:
- Systems without Bluetooth hardware (service fails gracefully)
- Systems without brightness control hardware (`brightnessctl` present but non-functional)
- Different display hardware configurations

**AR-008.3 - Misconfiguration Errors**: The modules MUST:
- Provide clear error messages when required dependencies are missing
- Fail at build time (not runtime) for configuration errors
- Use NixOS assertion mechanisms to validate configuration

**AR-008.4 - Service Failure Handling**: If non-critical services fail (e.g., Bluetooth), the system MUST still allow user login and desktop functionality.

#### AR-009: Dependencies and Assumptions

**AR-009.1 - External Dependencies**: The modules explicitly depend on:
- NixOS 25.05 or later
- home-manager (optional but recommended)
- Hyprland from nixpkgs
- PipeWire audio system

**AR-009.2 - Network/Bluetooth Assumption**: The assumption that networking and Bluetooth configuration differs between client and server is validated by:
- Servers typically use static, non-interactive networking
- Clients require WiFi, VPN, and Bluetooth peripheral support
- Desktop users need GUI network management tools

**AR-009.3 - Terminal Environment Assumption**: The assumption that `terminal-dev-environment` provides terminal functionality is validated. The desktop module MUST NOT duplicate this functionality.

**AR-009.4 - Version Compatibility**: The modules MUST specify minimum versions for critical dependencies (Hyprland, PipeWire) when known compatibility issues exist.

#### AR-010: Documentation Requirements

**AR-010.1 - CLAUDE.md Updates**: The `CLAUDE.md` file MUST be updated to reflect:
- The new module structure under `modules/client/desktop/` and `home-manager/modules/desktop/hyprland/`
- Integration points between NixOS and home-manager modules
- Example configurations using both modules

**AR-010.2 - Plan Updates**: The `plan.md` MUST document:
- The rationale for the chosen structure
- Component placement decisions
- Integration mechanisms

**AR-010.3 - Quickstart Updates**: A `quickstart.md` MUST be created documenting:
- How to enable the desktop module
- Required home-manager configuration
- Basic customization options
- Troubleshooting common issues

**AR-010.4 - Inline Documentation**: Each module file MUST include:
- Purpose and scope comments at the top
- Option descriptions using NixOS module documentation
- Examples of common configuration patterns

### Key Entities *(include if feature involves data)*

- **NixOS Desktop Module**: Represents the system-wide configuration for the desktop environment.
- **Home-Manager Desktop Module**: Represents the user-specific configuration and packages for the desktop environment.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can enable the new NixOS and home-manager desktop modules, and the system MUST build successfully.
- **SC-002**: On first boot of a configured system, the user is presented with the `greetd` login interface within 30 seconds of the boot process completing.
- **SC-003**: 100% of the specified packages (e.g., `chromium`, `waybar`, `hyprlock`) are present in the resulting system configuration.
- **SC-004**: After being idle for 5 minutes, the user session MUST be in a locked state, requiring a password to resume.
- **SC-005**: A user can successfully launch the `chromium` web browser and the `ghostty` terminal emulator from the Hyprland session.
