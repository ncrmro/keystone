# Feature Specification: Dynamic Theming System

**Feature Branch**: `010-theming`
**Created**: 2025-11-07
**Status**: Draft
**Input**: User description: "dynamic theming module. This should configure all the terminal programs lazygit/helix/ghostty @home-manager/modules/terminal-dev-environment/ and have desktop module (stup for now but this will config hyprland seperatly). It should follow omarchy theming standard. That is the omarchy bin should be copied from the flake input and installed in the users .local/share/omarchy/bin, we install the default omarchy theme etc in a idempotent script. System links are used to switch all the terminal themes. https://github.com/ncrmro/omarchy-nix/blob/feat/submodule-omarchy-arch/modules/home-manager/omarchy-defaults.nix#L64 This allows users to install themes via https://github.com/basecamp/omarchy/blob/master/bin/omarchy-theme-install or change themes via https://github.com/basecamp/omarchy/blob/master/bin/omarchy-theme-next"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Default Theme Installation and Activation (Priority: P1)

A Keystone user wants all their terminal applications (Helix editor, Ghostty terminal, Lazygit) to use consistent visual styling without manually configuring each tool individually. Upon enabling the theming module, the system automatically installs the default Omarchy theme and applies it across all supported applications.

**Why this priority**: This is the foundational capability - without basic theme installation and application, no other theming features are possible. This delivers immediate value by providing a cohesive visual experience out-of-the-box.

**Independent Test**: Enable the theming module in configuration, rebuild the system, and verify all terminal applications display the default Omarchy theme. Value delivered: unified visual interface across all tools.

**Acceptance Scenarios**:

1. **Given** a Keystone system with terminal-dev-environment enabled, **When** the user enables the omarchy-theming module and rebuilds, **Then** the default Omarchy theme files are installed to `~/.config/omarchy/themes/default/` and symlinked to `~/.config/omarchy/current/`
2. **Given** the theming module is active, **When** the user opens Helix editor, **Then** the editor displays colors and styling from the active Omarchy theme
3. **Given** the theming module is active, **When** the user opens Ghostty terminal, **Then** the terminal displays colors and styling from the active Omarchy theme
4. **Given** the theming module is active, **When** the user opens Lazygit, **Then** the git interface displays colors and styling from the active Omarchy theme
5. **Given** the system is rebuilt with theming enabled, **When** the user checks `~/.local/share/omarchy/bin/`, **Then** all Omarchy management binaries are present and executable

---

### User Story 2 - Theme Cycling and Switching (Priority: P2)

A user wants to quickly experiment with different visual themes to find one that matches their preferences or lighting conditions. They can cycle through installed themes using a simple command without manually editing configuration files.

**Why this priority**: This builds on the foundation by adding user choice and flexibility. Once the basic system works, users need an easy way to change themes to truly customize their environment.

**Independent Test**: With multiple themes installed, run the theme-next command and verify all applications switch to the new theme. Value delivered: user can personalize their environment.

**Acceptance Scenarios**:

1. **Given** multiple themes are installed in `~/.config/omarchy/themes/`, **When** the user runs `omarchy-theme-next`, **Then** the system updates the `current` symlink to point to the next theme in alphabetical order
2. **Given** the current theme is the last one alphabetically, **When** the user runs `omarchy-theme-next`, **Then** the system wraps around to the first theme
3. **Given** the theme has been switched, **When** the user opens any supported application (Helix, Ghostty, Lazygit), **Then** the application reflects the newly selected theme
4. **Given** a theme switch has occurred, **When** the user checks system notifications, **Then** they see a confirmation message indicating which theme is now active

---

### User Story 3 - Installing Custom Themes (Priority: P3)

A user discovers a community-created Omarchy theme they like and wants to install it from a Git repository. They can install the theme using a simple command and immediately start using it.

**Why this priority**: This enables community ecosystem and personalization beyond defaults. It's lower priority because users can get value from built-in themes first.

**Independent Test**: Provide a theme repository URL, run the install command, and verify the new theme appears in the available themes list and can be activated. Value delivered: access to unlimited community themes.

**Acceptance Scenarios**:

1. **Given** a valid Git repository containing an Omarchy theme, **When** the user runs `omarchy-theme-install <repo-url>`, **Then** the theme is cloned to `~/.config/omarchy/themes/<theme-name>/`
2. **Given** a theme with the same name already exists, **When** the user installs a new theme with that name, **Then** the existing theme is replaced after confirmation
3. **Given** a custom theme has been installed, **When** the user runs `omarchy-theme-next` or sets the theme explicitly, **Then** the custom theme can be selected and applied like any built-in theme
4. **Given** the installation process encounters an error (network failure, invalid repository), **When** the error occurs, **Then** the user receives a clear error message and the system remains in a stable state

---

### User Story 4 - Persistent Theme Configuration Across System Rebuilds (Priority: P2)

A user selects a non-default theme that they prefer. When they rebuild their Keystone system (updating packages, changing configuration, etc.), their theme choice persists without requiring manual reconfiguration.

**Why this priority**: This is critical for practical daily use - users shouldn't lose their preferences on system updates. Tied with P2 because persistence enables the value of theme switching.

**Independent Test**: Select a non-default theme, rebuild the system, and verify the selected theme remains active. Value delivered: stable, predictable environment.

**Acceptance Scenarios**:

1. **Given** a user has selected a non-default theme, **When** the system is rebuilt (nixos-rebuild or home-manager switch), **Then** the theme selection persists via the `current` symlink
2. **Given** the theme files are managed by Nix, **When** the user manually switches themes via symlink, **Then** subsequent rebuilds do not overwrite the user's manual theme choice
3. **Given** the default theme is updated in the flake input, **When** the user rebuilds, **Then** the updated theme files are installed but the user's current theme selection is not changed

---

### User Story 5 - Desktop Environment Theme Integration (Priority: P3)

A user running the Keystone client desktop (Hyprland) wants their window manager, status bar, and other desktop components to match their terminal theme. The system provides a foundation for extending Omarchy theming to desktop components.

**Why this priority**: This is future-focused - the spec mentions desktop integration is a "stub for now". It's included to establish the architecture but isn't immediately implemented.

**Independent Test**: Enable desktop theming module, verify it loads without errors, and confirm it has access to the active Omarchy theme. Value delivered: architectural foundation for future desktop theming.

**Acceptance Scenarios**:

1. **Given** the desktop theming module is enabled, **When** the system is built, **Then** the module initializes successfully without breaking existing desktop functionality
2. **Given** an Omarchy theme is active, **When** desktop components query the theme system, **Then** they can read the current theme configuration and colors
3. **Given** a theme switch occurs, **When** desktop-aware components check for updates, **Then** they can detect the theme change and respond accordingly (future: automatically reload)

---

### Edge Cases

- **What happens when** the user manually deletes the `current` symlink or it becomes broken?
  - System should detect the missing/broken symlink and automatically recreate it pointing to the default theme

- **What happens when** the user has custom theme modifications and rebuilds the system?
  - User modifications in `~/.config/omarchy/current/` persist because Nix only manages the theme sources in `themes/`, not the `current` symlink target

- **What happens when** a theme is missing required configuration files for one application (e.g., no helix.toml)?
  - That specific application falls back to its default styling while other applications still use the theme

- **What happens when** the omarchy flake input is updated with breaking changes to the bin scripts?
  - The module should continue using the existing script interface, or version-lock the omarchy input to ensure stability

- **What happens when** the user runs theme commands before home-manager activation completes?
  - The activation script runs idempotently, so missing directories are created on first activation and commands work thereafter

- **What happens when** multiple users on the same system have different theme preferences?
  - Each user has their own `~/.config/omarchy/` directory with independent theme configuration and symlinks

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST install Omarchy management binaries from the flake input to `~/.local/share/omarchy/bin/` with executable permissions
- **FR-002**: System MUST add `~/.local/share/omarchy/bin/` to the user's PATH via session environment configuration
- **FR-003**: System MUST install the default Omarchy theme to `~/.config/omarchy/themes/default/` during initial activation
- **FR-004**: System MUST create a symlink at `~/.config/omarchy/current/` pointing to the active theme directory
- **FR-005**: System MUST NOT overwrite the `current` symlink if it already exists (preserve user theme choices across rebuilds)
- **FR-006**: System MUST configure Helix editor to read theme configuration from `~/.config/omarchy/current/helix.toml` (or equivalent theme file)
- **FR-007**: System MUST configure Ghostty terminal to read theme configuration from `~/.config/omarchy/current/ghostty` (or equivalent theme file)
- **FR-008**: System MUST configure Lazygit to read theme configuration from `~/.config/omarchy/current/lazygit.yml` (or equivalent theme file)
- **FR-009**: The `omarchy-theme-next` binary MUST cycle through themes in alphabetical order, wrapping to the first theme after the last
- **FR-010**: The `omarchy-theme-next` binary MUST update the `current` symlink to point to the new theme directory
- **FR-011**: The `omarchy-theme-next` binary MUST display a system notification confirming the theme change
- **FR-012**: The `omarchy-theme-install` binary MUST accept a Git repository URL and clone it to `~/.config/omarchy/themes/<theme-name>/`
- **FR-013**: The `omarchy-theme-install` binary MUST extract theme name from repository URL (removing "omarchy-" prefix and "-theme" suffix if present)
- **FR-014**: The `omarchy-theme-install` binary MUST automatically activate the newly installed theme
- **FR-015**: System MUST create required directories (`~/.config/omarchy/`, `~/.local/share/omarchy/`) during activation if they don't exist
- **FR-016**: Theme installation and switching operations MUST be idempotent (safe to run multiple times)
- **FR-017**: System MUST provide a separate desktop theming module that can be enabled independently of terminal theming
- **FR-018**: Desktop theming module MUST be able to query the current active Omarchy theme for future integration with Hyprland
- **FR-019**: System MUST include the Omarchy logo file at `~/.local/share/omarchy/logo.txt`
- **FR-020**: All theme-related paths MUST use relative symlinks where possible to allow themes to reference files within their own directory

### Key Entities

- **Omarchy Theme**: A directory containing configuration files for multiple applications (helix.toml, ghostty, lazygit.yml, etc.) that define consistent colors, fonts, and styling across tools
- **Theme Registry**: The `~/.config/omarchy/themes/` directory containing all installed themes as subdirectories
- **Active Theme**: The theme currently in use, indicated by the `~/.config/omarchy/current/` symlink
- **Omarchy Binaries**: Management scripts (omarchy-theme-next, omarchy-theme-install, omarchy-theme-set) that manipulate theme state
- **Application Theme Configuration**: Application-specific config files or settings that reference the active Omarchy theme

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: User can enable theming and have all terminal applications (Helix, Ghostty, Lazygit) display the default theme within 10 seconds of system rebuild completion
- **SC-002**: User can switch between themes using a single command and see the change reflected in all applications within 5 seconds
- **SC-003**: Theme preferences persist across system rebuilds without user intervention (100% persistence rate)
- **SC-004**: User can install a custom theme from a Git repository in under 30 seconds (excluding network download time)
- **SC-005**: Theme switching operations complete successfully 100% of the time without leaving the system in an inconsistent state
- **SC-006**: System rebuilds with theming enabled complete without errors or warnings related to theme configuration
- **SC-007**: Users report consistent visual experience across all terminal applications when using the same theme (measured by absence of color/style mismatches)
- **SC-008**: Desktop theming module can be enabled without breaking existing Hyprland functionality (0 regression bugs)

## Assumptions

- **A-001**: The Omarchy upstream project maintains a stable interface for theme directory structure and binary script behavior
- **A-002**: Users have network access to clone Git repositories when installing custom themes
- **A-003**: All supported applications (Helix, Ghostty, Lazygit) support loading configuration from files that can be symlinked
- **A-004**: The default Omarchy theme includes configuration files for all supported applications
- **A-005**: Users are comfortable using command-line tools to switch themes and install new ones
- **A-006**: Theme configuration does not need to be applied in real-time to already-running applications (users can restart applications to see theme changes)
- **A-007**: Desktop environment theming (Hyprland) will be implemented in a future iteration and only requires architectural foundation now

## Constraints

- **C-001**: Must integrate with existing `terminal-dev-environment` module structure without breaking existing functionality
- **C-002**: Must follow NixOS home-manager patterns for declarative configuration and activation scripts
- **C-003**: Must preserve user theme choices across system rebuilds (cannot be purely declarative)
- **C-004**: Theme binaries must be sourced from the Omarchy flake input, not built/modified locally
- **C-005**: Must work with the existing Keystone flake structure and not require additional flake inputs beyond the Omarchy source
- **C-006**: Desktop module must be implemented as a stub that doesn't break when enabled, even though full Hyprland integration is future work

## Dependencies

- **D-001**: Requires the Omarchy source repository to be available as a flake input
- **D-002**: Depends on `terminal-dev-environment` module being enabled for terminal application integration
- **D-003**: Depends on Helix, Ghostty, and Lazygit being installed via the terminal-dev-environment module
- **D-004**: Requires home-manager for activation script and file management capabilities
- **D-005**: Desktop module depends on Hyprland being installed via the client module (future integration)

## Out of Scope

- **OS-001**: Real-time theme switching without application restart (applications must be restarted to see theme changes)
- **OS-002**: Full Hyprland desktop theming implementation (only architectural stub is in scope)
- **OS-003**: Theme preview or gallery interface (users must install and activate themes to see them)
- **OS-004**: Theme editing or customization tools (users must manually edit theme files or fork repositories)
- **OS-005**: Integration with applications outside the terminal-dev-environment module (e.g., browser themes, IDE themes)
- **OS-006**: Theme validation or compatibility checking (assumes themes are correctly formatted)
- **OS-007**: Automatic theme updates when upstream repositories change (users must manually reinstall to update)
