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
