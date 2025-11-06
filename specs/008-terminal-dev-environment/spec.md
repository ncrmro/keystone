# Feature Specification: Terminal Development Environment

**Feature Branch**: `008-terminal-dev-environment`
**Created**: 2025-11-05
**Status**: Draft
**Input**: Using home manager in a home folder we should create a nix module called Terminal Development Environment. It installs lazygit, zellij, ghostty, helix, zsh, git. This should be used for finding existing settings, example can be found here https://github.com/ncrmro/nixos-config/tree/master/home-manager/common

## User Scenarios & Testing

### User Story 1 - Enable Terminal Development Environment (Priority: P1)

A developer wants to enable a curated set of terminal development tools (helix, git, zsh, zellij, lazygit, ghostty) in their Keystone configuration with a single module import, getting sensible defaults that work out of the box.

**Why this priority**: This is the core value proposition - providing an opinionated terminal development stack that can be enabled with minimal configuration. Without this, users have to manually configure each tool individually.

**Independent Test**: Can be tested by enabling the module in a home-manager configuration, rebuilding, and verifying all tools are available and configured in a new shell session.

**Acceptance Scenarios**:

1. **Given** a Keystone system with home-manager configured, **When** a user imports the terminal-dev-environment module and rebuilds, **Then** all tools (helix, git, zsh, zellij, lazygit, ghostty) are installed and available in PATH
2. **Given** the module is enabled, **When** the user opens a new shell, **Then** zsh is the default shell with configured aliases and integrations
3. **Given** the module is enabled, **When** the user runs `hx` or `helix`, **Then** the editor opens with configured language servers and theme
4. **Given** the module is enabled, **When** the user runs `lazygit`, **Then** it opens with the configured UI
5. **Given** the module is enabled, **When** the user runs `zellij`, **Then** it starts with the configured theme and settings

---

### User Story 2 - Customize Configuration (Priority: P2)

A developer wants to override specific tool configurations (e.g., helix theme, zsh aliases, git settings) while keeping the other default configurations from the module.

**Why this priority**: Users need flexibility to adapt the environment to their preferences. This ensures the module is not overly opinionated and allows gradual customization.

**Independent Test**: Can be tested by overriding a single configuration option (e.g., helix theme) and verifying only that setting changes while others remain as defaults.

**Acceptance Scenarios**:

1. **Given** the terminal-dev-environment module is enabled, **When** a user overrides `programs.helix.settings.theme` in their configuration, **Then** the custom theme is used while other helix settings remain as module defaults
2. **Given** the terminal-dev-environment module is enabled, **When** a user adds custom zsh aliases, **Then** both custom and default aliases are available
3. **Given** the terminal-dev-environment module is enabled, **When** a user overrides git user configuration, **Then** the custom git identity is used while other git settings remain as defaults

---

### User Story 3 - Integration with Existing Keystone Modules (Priority: P3)

A developer using Keystone's client module wants the terminal development environment to work seamlessly with the existing Hyprland desktop environment (e.g., ghostty as default terminal for Hyprland).

**Why this priority**: While useful, this integration is not essential for the module to provide value. Users can still use the tools independently of desktop environment integration.

**Independent Test**: Can be tested by enabling both client and terminal-dev-environment modules, opening a terminal shortcut in Hyprland, and verifying ghostty opens with the configured environment.

**Acceptance Scenarios**:

1. **Given** both client and terminal-dev-environment modules are enabled, **When** the user opens a terminal via Hyprland keybinding, **Then** ghostty launches with zsh as the default shell
2. **Given** the terminal-dev-environment module is enabled on a headless server, **When** the user SSH's into the system, **Then** zsh is the default shell with all tools available

---

### Edge Cases

- What happens when a user has existing conflicting home-manager configurations for these tools?
- How does the system handle if a specific tool (e.g., ghostty) is not available in the current nixpkgs version?
- What happens when language servers specified in helix configuration are not available?
- How does git signing work if the user hasn't configured SSH keys?

## Requirements

### Functional Requirements

- **FR-001**: Module MUST provide a single enable option `keystone.terminal-dev-environment.enable` to activate all tools
- **FR-002**: Module MUST install and configure helix text editor with language servers (bash, yaml, dockerfile, json, nix at minimum)
- **FR-003**: Module MUST install and configure git with sensible defaults (LFS support, SSH signing capability)
- **FR-004**: Module MUST install and configure zsh with oh-my-zsh, common aliases, and integrations for zoxide, direnv, starship
- **FR-005**: Module MUST install and configure zellij terminal multiplexer with theme and settings
- **FR-006**: Module MUST install and configure lazygit terminal UI for git operations
- **FR-007**: Module MUST install and configure ghostty terminal emulator
- **FR-008**: Module MUST allow users to override individual tool configurations through home-manager options
- **FR-009**: Module MUST set helix as the default EDITOR and VISUAL environment variable
- **FR-010**: Module MUST integrate with direnv for automatic environment loading
- **FR-011**: Module MUST provide shell aliases for common development tasks (lg for lazygit, hx for helix, etc.)
- **FR-012**: Module MUST configure zoxide for smart directory navigation with zsh integration
- **FR-013**: Module MUST configure starship prompt for enhanced shell experience

### Non-Functional Requirements

- **NFR-001**: Module configuration MUST follow NixOS home-manager module conventions with proper options interface
- **NFR-002**: Module MUST be composable with other Keystone modules (client, server)
- **NFR-003**: All configuration files MUST be declaratively managed through Nix
- **NFR-004**: Module MUST provide documentation with usage examples
- **NFR-005**: Module MUST be testable via self-contained bin/test-home-manager script called from bin/test-deployment
- **NFR-006**: Test script MUST perform installation and verification as non-root testuser, returning exit code 0 on success or 1 on failure

### Key Entities

- **TerminalDevEnvironment**: A cohesive collection of terminal-based development tools configured to work together, including editor (helix), shell (zsh), multiplexer (zellij), git UI (lazygit), terminal emulator (ghostty), and supporting utilities
- **ToolConfiguration**: Individual tool settings that can be overridden by users while maintaining sensible defaults from the module

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can enable the complete terminal development environment with a single module import and rebuild
- **SC-002**: All tools (helix, git, zsh, zellij, lazygit, ghostty) are functional immediately after rebuild without additional manual configuration
- **SC-003**: Users can successfully override at least one configuration option per tool without breaking the module
- **SC-004**: Module documentation includes at least one working example of enabling and customizing the environment
- **SC-005**: Helix editor includes functional language servers for Nix, Bash, YAML, JSON, and Dockerfile
- **SC-006**: Module passes bin/test-home-manager script verification (called from bin/test-deployment)
- **SC-007**: Automated verification confirms all tools functional for testuser: helix with LSPs, git, zsh with aliases, lazygit, zellij with theme, starship prompt, zoxide navigation
