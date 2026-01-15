# Keystone Desktop Specification

This specification defines the functional requirements for the core Keystone Desktop environment components, including the menu system, keybindings help, status bar, screen locking, night light, monitor management, and theming infrastructure.

## Functional Requirements

### Menu System (dt-menu-001)
The system MUST provide a unified, hierarchical menu accessible via a global keyboard shortcut (`Mod + Escape`) and the power button.
- **dt-menu-001.1**: The menu MUST allow navigation to sub-menus: Apps, Learn, Capture, Toggle, Style, Setup, Install, Remove, Update, System.
- **dt-menu-001.2**: The "System" sub-menu MUST provide options for: Lock, Suspend, Restart, and Shutdown.
- **dt-menu-001.3**: The "Style" sub-menu MUST allow switching themes.
- **dt-menu-001.4**: The "Toggle" sub-menu MUST allow toggling system features like Nightlight, Idle Inhibition, and configuring Nightlight schedule and intensity.
- **dt-menu-001.5**: The "Capture" sub-menu MUST provide options for starting/stopping screen recordings and taking various types of screenshots.
- **dt-menu-001.6**: The "Learn" sub-menu MUST provide access to keybindings help and documentation.
- **dt-menu-001.7**: The menu MUST support direct navigation to specific sub-menus via command-line arguments.
- **dt-menu-001.8**: The "Setup" sub-menu MUST provide a "Monitors" section for dynamic display configuration (see dt-monitor-001).

### Monitor Management (dt-monitor-001)
The system MUST provide an interactive menu for configuring displays at runtime, optimized for presentation scenarios.
- **dt-monitor-001.1**: The monitor menu MUST list all currently connected displays.
- **dt-monitor-001.2**: The menu MUST provide a global "Mirror All" toggle to clone the primary display to all others.
- **dt-monitor-001.3**: The menu MUST allow selecting specific external monitors to mirror the primary display individually.
- **dt-monitor-001.4**: The menu MUST provide resolution presets (e.g., 1080p) for compatibility with projectors.
- **dt-monitor-001.5**: The system MUST support an `autoMirror` configuration option that, when enabled, automatically mirrors the primary display to any newly connected external display.

### Keybindings Help (dt-help-001)
The system MUST provide a searchable display of current keyboard shortcuts, accessible via `Mod + K`.
- **dt-help-001.1**: The display MUST dynamically fetch active keybindings from the window manager.
- **dt-help-001.2**: The display MUST map keycodes to human-readable symbols (e.g., converting keycode 272 to "Left Mouse Button").
- **dt-help-001.3**: The display MUST allow filtering/searching of keybindings by description or key combination.
- **dt-help-001.4**: The entries MUST be prioritized/sorted by category (e.g., Window Management, Launchers).

### Status Bar (dt-bar-001)
The system MUST provide a status bar (Waybar) at the top of the screen.
- **dt-bar-001.1**: The bar MUST display: Keystone launcher icon, Workspaces, Clock, Screen recording status, Tray (expandable), Bluetooth, Network, Audio, CPU usage, and Battery.
- **dt-bar-001.2**: The workspace indicator MUST show active workspaces and allow navigation by clicking.
- **dt-bar-001.3**: The screen recording indicator MUST appear only when recording is active and allow stopping the recording.
- **dt-bar-001.4**: The tray MUST be collapsible/expandable to save space.
- **dt-bar-001.5**: The battery module MUST change icons based on charge level and charging status.

### Screen Locking (dt-lock-001)
The system MUST provide a secure screen locking mechanism (Hyprlock).
- **dt-lock-001.1**: The lock screen MUST support fingerprint authentication.
- **dt-lock-001.2**: The lock screen MUST display the current time and a customized background.
- **dt-lock-001.3**: The lock screen MUST provide visual feedback for authentication failures.
- **dt-lock-001.4**: The look and feel MUST align with the active system theme.

### Lock Inhibition (dt-inhibit-001)
The system MUST provide a mechanism to prevent automatic screen locking/suspension for specific applications or activities.
- **dt-inhibit-001.1**: The system MUST allow for temporary manual inhibition of screen locking/suspension.
- **dt-inhibit-001.2**: The system MUST ignore D-Bus inhibition requests (e.g., from web browsers playing media) by default to ensure the screen locks when the user is idle, even if audio/video is playing.

### Night Light (dt-night-001)
The system MUST provide a blue light filter (Hyprsunset) to reduce eye strain.
- **dt-night-001.1**: The filter MUST be toggleable via the Menu System or a keyboard shortcut.
- **dt-night-001.2**: The filter MUST support user-configurable schedule (start/end times) and intensity (color temperature).
- **dt-night-001.3**: The schedule and intensity settings MUST be configurable via the Menu System.

### Theming System (dt-theme-001)
The system MUST provide a centralized theming infrastructure to switch the visual appearance of all desktop components consistently.
- **dt-theme-001.1**: The system MUST support switching between multiple themes (e.g., Tokyo Night, Catppuccin, Nord).
- **dt-theme-001.2**: Switching a theme MUST update:
    - Window manager configuration (colors, borders)
    - Status bar (colors, styles)
    - Terminal emulator (colors)
    - Text editor (colors)
    - Application launcher (colors)
    - Notification daemon (colors)
    - System background/wallpaper
    - GTK/GNOME interface settings (light/dark mode, icon theme)
- **dt-theme-001.3**: The system MUST persist the selected theme across reboots.
- **dt-theme-001.4**: The system MUST allow for custom themes defined locally, in addition to upstream themes.

### Screen Recording (dt-record-001)
The system MUST allow starting and stopping screen recordings, capturing a selected region or the entire screen, with optional audio capture and configurable output management.
- **dt-record-001.1**: The screen recording MUST be toggleable via the "Capture" menu or a dedicated shortcut.
- **dt-record-001.2**: An indicator in the Waybar MUST show when recording is active.
- **dt-record-001.3**: Clicking the Waybar indicator MUST stop the active screen recording.
- **dt-record-001.4**: The system MUST support optional audio capture from desktop audio (`--with-desktop-audio`) and microphone input (`--with-microphone-audio`), which can be combined.
- **dt-record-001.5**: Screen recordings MUST be saved to `$KEYSTONE_SCREENRECORD_DIR` (if set), otherwise `$XDG_VIDEOS_DIR`, with fallback to `~/Videos`, using filename format `screenrecording-YYYY-MM-DD_HH-MM-SS.mp4`.
- **dt-record-001.6**: The recording MUST use GPU-accelerated encoding at 60 FPS with H.264 video codec and AAC audio codec.
- **dt-record-001.7**: Recording MUST provide visual notifications for start, stop, and error conditions with file path confirmation on completion.

#### User Stories (dt-record-001-stories)

**Story 1: Quick Screen Recording**
As a developer, I want to quickly record my screen for documentation and bug reports, so that I can share visual information with teammates without external tools.

Acceptance Scenarios:
- Given a user at any screen with Hyprland desktop, When they access the Capture menu and select "Screenrecord", Then recording starts immediately with a notification
- Given recording is active, When the user clicks the Waybar indicator, Then recording stops and a completion notification shows the file path
- Given a recording completes, When the user checks their Videos directory, Then a properly formatted video file exists with timestamp in filename

**Story 2: Recording with Audio**
As a content creator, I want to capture system audio and microphone input alongside screen video, so that I can create complete tutorials and presentations.

Acceptance Scenarios:
- Given a user starts recording with `--with-desktop-audio`, When audio plays from applications, Then the recording captures system audio in the output file
- Given a user starts recording with `--with-microphone-audio`, When they speak into the microphone, Then voice audio is captured in the output file
- Given a user specifies both audio options, When recording completes, Then the output file contains synchronized desktop and microphone audio

**Story 3: Flexible Output Management**
As a developer, I want to control where recordings are saved, so that I can organize videos by project.

Acceptance Scenarios:
- Given `KEYSTONE_SCREENRECORD_DIR` is set to a custom path, When recording completes, Then the file is saved to that directory
- Given no custom directory is configured, When recording completes, Then the file defaults to ~/Videos with format `screenrecording-YYYY-MM-DD_HH-MM-SS.mp4`
- Given the configured output directory doesn't exist, When recording attempts to start, Then a notification warns the user and recording is prevented

### Screenshots (dt-shot-001)
The system MUST allow capturing screenshots of a selected region, window, or entire screen.
- **dt-shot-001.1**: Taking a screenshot MUST open it in an editor for review and annotation.
- **dt-shot-001.2**: Within the editor, a specific command (e.g., `Mod+C`) MUST save the screenshot to the Pictures directory and close the editor.

---

## Keybinding Functional Requirements

### Philosophy (dt-bind-001)
The keybinding system MUST enable a mouse-free development workflow with consistent patterns across all tools.
- **dt-bind-001.1**: Every operation MUST be accessible via keyboard.
- **dt-bind-001.2**: Keybindings MUST be optimized for speed, ergonomics, and muscle memory.
- **dt-bind-001.3**: The system MUST support hardware-specific strategies while maintaining portable software configuration.

### Modifier Key Strategy (dt-bind-002)
The system MUST use a consistent modifier key strategy across all tools.
- **dt-bind-002.1**: `Super` MUST be the Hyprland window manager modifier.
- **dt-bind-002.2**: Physical Alt key MUST be swapped to Super via `altwin:swap_alt_win` for ergonomic access.
- **dt-bind-002.3**: `Ctrl` MUST be used for application-level operations.
- **dt-bind-002.4**: `Shift` MUST modify base keybindings (e.g., reverse direction, new window vs current).
- **dt-bind-002.5**: Caps Lock MUST be remapped to Ctrl at OS level.

### Spatial Navigation Pattern (dt-bind-003)
The system MUST use J/K/I/L for directional navigation (home row optimized).
- **dt-bind-003.1**: `j` MUST represent left, `k` down, `i` up, `l` right.
- **dt-bind-003.2**: This pattern MUST be consistent across Hyprland window focus and Zellij pane navigation.
- **dt-bind-003.3**: Navigation keys MUST stay on the home row for maximum ergonomics.

### Tab Navigation Pattern (dt-bind-004)
The system MUST use W/E/R/C for tab operations across all tabbed interfaces.
- **dt-bind-004.1**: `w` MUST navigate to previous tab.
- **dt-bind-004.2**: `e` MUST create a new tab.
- **dt-bind-004.3**: `r` MUST navigate to next tab.
- **dt-bind-004.4**: `c` MUST close the current tab.
- **dt-bind-004.5**: This pattern MUST work consistently in browser, terminal multiplexer, and other tabbed interfaces.

### Hyprland Window Navigation (dt-bind-010)
The window manager MUST provide keyboard-driven window focus navigation.
- **dt-bind-010.1**: `Super+J` MUST focus the window to the left.
- **dt-bind-010.2**: `Super+K` MUST focus the window below.
- **dt-bind-010.3**: `Super+I` MUST focus the window above.
- **dt-bind-010.4**: `Super+L` MUST focus the window to the right.

### Hyprland Window Management (dt-bind-011)
The window manager MUST provide keyboard-driven window management.
- **dt-bind-011.1**: `Super+Q` MUST close the active window.
- **dt-bind-011.2**: `Super+Return` MUST open a new terminal.
- **dt-bind-011.3**: `Super+F` MUST toggle fullscreen.
- **dt-bind-011.4**: `Super+V` MUST toggle floating mode.

### Hyprland Workspace Navigation (dt-bind-012)
The window manager MUST provide workspace navigation.
- **dt-bind-012.1**: `Super+1` through `Super+0` MUST switch to workspaces 1-10.
- **dt-bind-012.2**: `Super+Shift+1` through `Super+Shift+0` MUST move the active window to workspaces 1-10.

### Zellij Tab Navigation (dt-bind-020)
The terminal multiplexer MUST support tab navigation matching the W/E/R/C pattern.
- **dt-bind-020.1**: `Ctrl+PageUp` and `Ctrl+Shift+Tab` MUST navigate to previous tab.
- **dt-bind-020.2**: `Ctrl+PageDown` and `Ctrl+Tab` MUST navigate to next tab.
- **dt-bind-020.3**: `Ctrl+T` MUST create a new tab.
- **dt-bind-020.4**: `Ctrl+W` MUST close the current tab.
- **dt-bind-020.5**: Future: `Alt+W/E/R/C` SHOULD provide direct tab navigation.

### Zellij Pane Navigation (dt-bind-021)
The terminal multiplexer MUST support pane navigation using shared keybindings.
- **dt-bind-021.1**: `Alt+h` or `Alt+Left` MUST focus the pane to the left.
- **dt-bind-021.2**: `Alt+j` or `Alt+Down` MUST focus the pane below.
- **dt-bind-021.3**: `Alt+k` or `Alt+Up` MUST focus the pane above.
- **dt-bind-021.4**: `Alt+l` or `Alt+Right` MUST focus the pane to the right.
- **dt-bind-021.5**: Pane navigation MUST work in normal mode without mode switching.

### Zellij Mode Switching (dt-bind-022)
The terminal multiplexer MUST avoid conflicts with common application shortcuts.
- **dt-bind-022.1**: Lock mode MUST be accessible via `Ctrl+Shift+G` (not `Ctrl+G`).
- **dt-bind-022.2**: Session mode MUST be accessible via `Ctrl+Shift+O` (not `Ctrl+O`).
- **dt-bind-022.3**: Default `Ctrl+G` and `Ctrl+O` bindings MUST be disabled.

### Ghostty Integration (dt-bind-030)
The terminal emulator MUST delegate multiplexing to Zellij.
- **dt-bind-030.1**: Ghostty MUST NOT handle tab management (delegated to Zellij).
- **dt-bind-030.2**: Ghostty MUST NOT handle pane/split management (delegated to Zellij).
- **dt-bind-030.3**: Tab navigation shortcuts (`Ctrl+PageUp/Down`, `Ctrl+Tab`) MUST be unbound in Ghostty.
- **dt-bind-030.4**: Split shortcuts (`Ctrl+Shift+O`) MUST be unbound in Ghostty.

### Helix Editor (dt-bind-040)
The text editor MUST provide efficient navigation and editing keybindings.
- **dt-bind-040.1**: `Return` in normal mode MUST save the current file (`:write`).
- **dt-bind-040.2**: Word navigation MUST use `w/b/e` for word boundaries.
- **dt-bind-040.3**: Line navigation SHOULD use `Ctrl+A` for line start and `Ctrl+E` for line end.

### Cross-Tool Consistency (dt-bind-050)
Keybindings MUST be consistent across all tools where applicable.
- **dt-bind-050.1**: Window-level navigation (Hyprland) MUST use `Super+J/K/I/L`.
- **dt-bind-050.2**: Pane-level navigation (Zellij) MUST use `Alt+h/j/k/l`.
- **dt-bind-050.3**: Tab navigation MUST use the W/E/R/C pattern with appropriate modifiers.
- **dt-bind-050.4**: Different modifiers MUST prevent conflicts: Super for windows, Alt for panes.

### Hardware Portability (dt-bind-060)
The keybinding system MUST work consistently across different keyboard hardware.
- **dt-bind-060.1**: OS-level configuration (`altwin:swap_alt_win`) MUST enable any programmable keyboard to work identically.
- **dt-bind-060.2**: UHK Fn2 layer MUST send Alt codes for window management.
- **dt-bind-060.3**: Framework laptop MUST use direct Alt key for window management.
- **dt-bind-060.4**: Portable QMK/ZMK keyboards MUST be configurable to match UHK behavior.
- **dt-bind-060.5**: Adding a new keyboard MUST require zero Nix/Hyprland configuration changes.

## Tasks

### Implementation
- [x] **dt-task-menu-001**: Implement `keystone-menu` script using Walker.
- [x] **dt-task-help-001**: Implement `keystone-menu-keybindings` script to parse Hyprland bindings.
- [x] **dt-task-bar-001**: Configure Waybar with custom modules and expandable tray.
- [x] **dt-task-lock-001**: Configure Hyprlock with fingerprint support and theming.
- [x] **dt-task-inhibit-001**: Implement lock inhibition mechanism.
- [x] **dt-task-night-001**: Configure Hyprsunset and toggle script.
- [x] **dt-task-night-002**: Implement Nightlight schedule and intensity configuration via the Menu System.
- [x] **dt-task-theme-001**: Create `keystone-theme-switch` script and Home Manager module for deploying theme files.
- [x] **dt-task-bind-001**: Configure Hyprland keybindings to launch menus and toggles (`Mod+Escape`, `Mod+K`, `Mod+Ctrl+N`).
- [x] **dt-task-record-001**: Implement screen recording functionality (start/stop) with region/screen selection.
- [x] **dt-task-shot-001**: Implement screenshot functionality with integrated editing and save-to-pictures-and-close workflow.
- [x] **dt-task-bar-002**: Integrate screen recording indicator with Waybar, enabling stop-on-click functionality.
- [x] **dt-task-monitor-001**: Implement `keystone-desktop-monitors` option with `autoMirror` support.
- [ ] **dt-task-monitor-002**: Implement `keystone-monitors` script for interactive monitor configuration.