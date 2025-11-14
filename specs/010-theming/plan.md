# Implementation Plan: Dynamic Theming System

**Branch**: `010-theming` | **Date**: 2025-11-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/010-theming/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Implement a unified theming system for Keystone that applies consistent visual styling across all terminal applications (Helix, Ghostty, Lazygit) and provides architectural foundation for future desktop (Hyprland) integration. The system follows the Omarchy standard, installing theme management binaries and default themes via home-manager, with symlink-based theme switching that persists across system rebuilds.

## Technical Context

**Language/Version**: Nix expression language (via NixOS 25.05 / home-manager)
**Primary Dependencies**:
- Omarchy theme repository (flake input)
- home-manager (activation scripts, file management)
- terminal-dev-environment module (application integration)

**Storage**: Filesystem-based (XDG-compliant directories)
- `~/.config/omarchy/themes/` - Theme registry
- `~/.config/omarchy/current/` - Active theme symlink
- `~/.local/share/omarchy/bin/` - Management binaries

**Testing**:
- NixOS VM builds with `bin/virtual-machine`
- home-manager activation testing with `bin/test-home-manager`
- Manual verification of theme application across all supported applications

**Target Platform**: NixOS Linux (x86_64, aarch64)

**Project Type**: NixOS home-manager module with activation scripts

**Performance Goals**:
- Theme installation: <2 seconds for default theme during activation
- Theme switching: <1 second for symlink updates
- System rebuild: No measurable impact on build time

**Constraints**:
- Must preserve user theme choices across rebuilds (semi-declarative)
- Cannot use purely declarative approach due to user customization requirements
- Theme binaries must remain unmodified from upstream Omarchy source
- Must not break existing terminal-dev-environment functionality

**Scale/Scope**:
- 3 terminal applications (Helix, Ghostty, Lazygit)
- 1 desktop module stub (Hyprland - future work)
- 12+ community themes available via omarchy-theme-install
- Support for unlimited user-installed custom themes

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ I. Declarative Infrastructure

**Status**: PASS (with justified hybrid approach)

**Evaluation**: The theming module follows NixOS declarative patterns for theme source installation but intentionally uses symlinks for user preference state. This hybrid approach is justified because:
- Theme files themselves are declaratively managed via Nix
- User's active theme choice is mutable state (similar to user data)
- Symlinks are checked into version control-able configuration but not overwritten on rebuild

**Compliance**: Module defined as code, version controlled, reproducible (theme sources), auditable

### ✅ II. Security by Default

**Status**: PASS

**Evaluation**: No security implications for visual theming. Theme files are read-only configuration data with no executable code execution or privileged operations. Omarchy binaries are bash scripts that manipulate symlinks only - no system modification capabilities.

**Compliance**: Feature does not compromise existing security posture (encryption, TPM, secure boot remain unchanged)

### ✅ III. Modular Composability

**Status**: PASS

**Evaluation**: Implementation follows module best practices:
- Self-contained module with clear boundaries (home-manager/modules/omarchy-theming/)
- Independent enable/disable via `programs.omarchy-theming.enable`
- Explicit dependencies declared (terminal-dev-environment optional integration)
- Can be used independently or composed with desktop modules

**Compliance**: Module structure follows Keystone patterns, composable with other features

### ✅ IV. Hardware Agnostic

**Status**: PASS

**Evaluation**: Theming is pure software configuration with no hardware dependencies. Works identically across:
- Different CPU architectures (x86_64, aarch64)
- Bare-metal and virtualized environments
- Various terminal emulators and display servers

**Compliance**: No hardware-specific constraints

### ✅ V. Cryptographic Sovereignty

**Status**: N/A

**Evaluation**: Feature does not involve cryptographic operations, key management, or authentication. Purely cosmetic configuration.

**Compliance**: No impact on user sovereignty

### NixOS Module Standards

**Status**: PASS (to be validated during implementation)

**Requirements**:
- ✅ Use `types.bool` for enable option
- ✅ Use `types.enum` for theme selection (if declarative option provided)
- ✅ Use `types.package` for omarchy source input
- ✅ Include assertions for configuration validation (e.g., check terminal-dev-environment enabled)
- ✅ Document all options with descriptions and examples

### Testing Requirements

**Status**: TO BE VALIDATED

**Plan**:
- Build-time validation: `nix build .#homeConfigurations.test-user.activationPackage`
- Activation testing: `bin/test-home-manager` with theming enabled
- Integration testing: Manual verification of theme application in VM
- Regression testing: Verify terminal-dev-environment still works when theming disabled

### Documentation Standards

**Status**: TO BE COMPLETED

**Deliverables**:
- Module option documentation (auto-generated from NixOS module options)
- Usage example in `examples/theming/` directory
- Migration guide (N/A - new feature)
- Architectural rationale documented in this plan and inline comments

## Project Structure

### Documentation (this feature)

```text
specs/010-theming/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output: Omarchy integration patterns
├── data-model.md        # Phase 1 output: Theme entity structure
├── quickstart.md        # Phase 1 output: User guide for enabling theming
├── contracts/           # Phase 1 output: Module options interface
│   └── module-options.nix
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
home-manager/modules/
├── omarchy-theming/
│   ├── default.nix          # Main module with enable option and orchestration
│   ├── activation.nix       # Home-manager activation scripts for symlink setup
│   ├── binaries.nix         # Omarchy binary installation logic
│   ├── terminal.nix         # Terminal application configuration (Helix, Ghostty, Lazygit)
│   └── desktop.nix          # Desktop module stub (Hyprland - future)
│
└── terminal-dev-environment/
    ├── default.nix          # Imports omarchy-theming as optional sub-module
    ├── helix.nix            # Extended with theme configuration support
    ├── ghostty.nix          # Extended with theme configuration support
    └── git.nix              # Extended with lazygit theme configuration

flake.nix                    # Add omarchy source as input

examples/
└── theming/
    ├── basic.nix            # Minimal theming enablement
    ├── custom-theme.nix     # Installing and using custom themes
    └── terminal-only.nix    # Theming without desktop integration

docs/modules/
└── omarchy-theming.md       # User-facing documentation
```

**Structure Decision**: Single project structure following Keystone's existing pattern. The theming module lives in `home-manager/modules/omarchy-theming/` as a peer to `terminal-dev-environment/`, allowing it to be enabled independently or composed with the terminal environment. Sub-modules within omarchy-theming/ separate concerns (binaries, activation, application config).

## Complexity Tracking

> **No violations to justify** - all constitution gates passed

## Phase 0: Research & Technical Discovery

See [research.md](./research.md) for complete findings. Key decisions:

### Theme File Format Discovery

**Decision**: Use Omarchy's multi-application theme directory standard
**Rationale**: Omarchy provides a proven format with 12+ community themes available. Each theme directory contains application-specific config files (helix.toml, ghostty.conf, lazygit.yml, etc.)
**Alternatives considered**:
- Creating a custom theme format: Rejected due to lack of ecosystem and maintenance burden
- Using base16 standard: Rejected because Omarchy is more comprehensive and includes non-color configuration

### Application Configuration Integration Points

**Decision**: Extend existing terminal-dev-environment application modules with theme file inclusion
**Rationale**: Helix, Ghostty, and Lazygit all support loading configuration from included/imported files. This allows theming to layer on top of base configuration without conflicts.
**Alternatives considered**:
- Direct configuration replacement: Rejected due to loss of user customizations
- Conditional configuration merge: Rejected as overly complex for NixOS module system

### Symlink vs Declarative Theme Selection

**Decision**: Use symlinks for active theme state, declarative for theme sources
**Rationale**: Symlinks allow user choice to persist across rebuilds without tracking state in Nix configuration. Theme sources remain fully declarative.
**Alternatives considered**:
- Fully declarative theme selection: Rejected because it forces users to edit Nix config for theme changes
- Imperative-only management: Rejected because theme files wouldn't be managed by Nix

### Home Manager Activation Pattern

**Decision**: Use `home.activation` with `entryAfter ["writeBoundary"]` for symlink creation
**Rationale**: This is the standard home-manager pattern for post-installation filesystem operations that should run after all files are written but before final setup.
**Alternatives considered**:
- SystemD user services: Rejected as overkill for one-time activation
- Manual user scripts: Rejected because it violates declarative infrastructure principle

## Phase 1: Design Artifacts

### Data Model

See [data-model.md](./data-model.md) for complete entity definitions. Key entities:

- **Theme**: Directory containing application config files
- **Theme Registry**: Collection of installed themes in `~/.config/omarchy/themes/`
- **Active Theme**: Symlink at `~/.config/omarchy/current/` pointing to selected theme
- **Theme Binary**: Bash script for theme management operations
- **Application Theme Config**: Per-application files read from active theme symlink

### Module Options Contract

See [contracts/module-options.nix](./contracts/module-options.nix) for complete interface. Primary options:

```nix
programs.omarchy-theming = {
  enable = true;  # Master enable switch

  package = pkgs.omarchy;  # Override omarchy source if needed

  terminal = {
    enable = true;  # Enable terminal application theming
    applications = {
      helix = true;
      ghostty = true;
      lazygit = true;
    };
  };

  desktop = {
    enable = false;  # Future: Hyprland integration
  };
};
```

### User Quick Start

See [quickstart.md](./quickstart.md) for complete guide. Essential steps:

1. Add omarchy input to flake
2. Enable `programs.omarchy-theming.enable = true`
3. Rebuild system
4. Use `omarchy-theme-next` to cycle themes or `omarchy-theme-install` for custom themes

## Phase 2: Implementation Tasks

**NOTE**: Task breakdown generated by `/speckit.tasks` command (not part of this plan output)

See [tasks.md](./tasks.md) once generated for dependency-ordered implementation steps.

## Post-Design Constitution Re-Check

*All gates remain PASS - no design decisions violated constitution principles*

### Re-validation Summary

- **Declarative Infrastructure**: ✅ Theme sources managed declaratively, user state handled appropriately
- **Security by Default**: ✅ No security implications introduced
- **Modular Composability**: ✅ Clean module boundaries with optional composition
- **Hardware Agnostic**: ✅ Pure software configuration
- **Cryptographic Sovereignty**: ✅ N/A

### NixOS Standards Compliance

- Module structure follows Keystone patterns
- Options use appropriate types with validation
- Documentation plan meets requirements
- Testing strategy defined

## Next Steps

Run `/speckit.tasks` to generate implementation tasks from this plan.
