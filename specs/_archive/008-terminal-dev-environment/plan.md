# Implementation Plan: Terminal Development Environment

**Branch**: `008-terminal-dev-environment` | **Date**: 2025-11-05 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/008-terminal-dev-environment/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Create a composable home-manager module `terminal-dev-environment` that provides an opinionated, cohesive terminal development stack for Keystone users. The module will install and configure: helix (text editor with LSP support), git (with LFS and SSH signing), zsh (with oh-my-zsh, starship, zoxide), zellij (terminal multiplexer), lazygit (git TUI), and ghostty (terminal emulator). All tools will have sensible defaults inspired by the existing ncrmro/nixos-config structure but adapted for Keystone's module system with an enable option and overrideable configurations.

## Technical Context

**Language/Version**: Nix 2.24+ (NixOS 25.05)
**Primary Dependencies**: home-manager (composable user environment manager), nixpkgs packages (helix, git, zsh, zellij, lazygit, ghostty)
**Storage**: N/A (declarative configuration only)
**Testing**: NixOS module system assertions, manual integration testing via `nix build` and VM testing
**Target Platform**: Linux (NixOS 25.05) with home-manager - x86_64 and aarch64 architectures
**Project Type**: NixOS home-manager module (single module with sub-configurations per tool)
**Performance Goals**: Module evaluation time < 5 seconds, first shell startup < 2 seconds with all integrations loaded
**Constraints**: Must use only packages available in nixpkgs 25.05 stable, must not conflict with existing Keystone client/server modules, configurations must be pure (no imperative setup steps)
**Scale/Scope**: Single home-manager module with 7 tool configurations, ~200-300 lines of Nix code, supports both standalone and integrated usage with Keystone client module

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Compliance

#### I. Declarative Infrastructure
**Status**: ✅ PASS
- All tool configurations defined as Nix code in home-manager module
- Version controlled and reproducible across different machines
- Pure declarative configuration with no imperative setup steps

#### II. Security by Default
**Status**: ✅ PASS (N/A for this feature)
- This module does not handle encryption, TPM, or boot security
- Configures git SSH signing support (optional security enhancement)
- No security violations or degradation of existing security posture

#### III. Modular Composability
**Status**: ✅ PASS
- Implemented as self-contained home-manager module with clear `enable` option
- Composable with existing Keystone client/server modules
- Each tool configuration can be overridden independently
- No hard dependencies on other Keystone modules (optional integration with client desktop)

#### IV. Hardware Agnostic
**Status**: ✅ PASS
- Pure software configuration, no hardware-specific dependencies
- Compatible with x86_64 and aarch64 architectures
- Works on both bare-metal and virtualized environments
- Terminal tools are platform-agnostic within Linux

#### V. Cryptographic Sovereignty
**Status**: ✅ PASS (N/A for this feature)
- Module does not manage encryption keys or authentication
- Git SSH signing configured to use user's own SSH keys (~/.ssh/id_ed25519)
- No vendor dependencies or external key management

### NixOS-Specific Constraints

#### Module Development Standards
**Status**: ✅ PASS
- Will use `lib.mkEnableOption` for enable option
- Will use `lib.mkOption` with proper types for configuration options
- Will include assertions for configuration validation
- Will provide comprehensive documentation with examples

#### Development Tooling
**Status**: ✅ PASS
- Can be tested with existing `bin/virtual-machine` infrastructure
- Compatible with ISO building and nixos-anywhere deployment
- No new development tooling requirements

#### Testing Requirements
**Status**: ✅ PASS
- Build-time validation with `nix build .#nixosConfigurations.test-config`
- Self-contained bin/test-home-manager script for automated testing as non-root testuser
- Script called from bin/test-deployment, returns exit code 0/1 to pass/fail outer test
- Comprehensive verification checks: tools installed, zsh default, LSPs functional, aliases work
- Manual testing via standalone `./bin/test-home-manager` execution

#### Documentation Standards
**Status**: ✅ PASS
- Will provide NixOS option documentation for all configurable settings
- Will include usage example in module documentation
- Will document integration patterns with existing Keystone modules

### Gate Result: ✅ APPROVED

All core principles and NixOS constraints satisfied. No violations or exceptions required. This feature aligns with Keystone's modular, declarative, and composable architecture.

---

### Post-Design Re-evaluation (Phase 1 Complete)

**Date**: 2025-11-05
**Status**: ✅ APPROVED - All principles still satisfied

After completing research and design (research.md, data-model.md, quickstart.md):

#### Design Confirms Compliance

1. **Declarative Infrastructure** - ✅ Unchanged
   - Module options fully defined in data-model.md
   - All configuration declarative via home-manager

2. **Security by Default** - ✅ Unchanged
   - No security implications introduced
   - Git SSH signing remains optional and user-controlled

3. **Modular Composability** - ✅ Unchanged
   - Module structure confirmed in research.md
   - Individual tool toggles preserve composability
   - Escape hatches (extraPackages) maintain flexibility

4. **Hardware Agnostic** - ✅ Unchanged
   - All tools are pure software, platform-independent
   - Confirmed compatibility with x86_64 and aarch64

5. **Cryptographic Sovereignty** - ✅ Unchanged
   - No key management introduced
   - User maintains control of SSH keys for git signing

#### No New Risks Identified

- Home-manager module patterns follow official best practices (from research)
- Ghostty confirmed available in nixpkgs 25.05 (no unstable dependencies)
- All design decisions align with existing Keystone architecture
- Testing strategy uses existing infrastructure (bin/virtual-machine)

**Final Gate Status**: ✅ APPROVED FOR IMPLEMENTATION

## Project Structure

### Documentation (this feature)

```
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
home-manager/
└── modules/
    └── terminal-dev-environment/
        ├── default.nix           # Main module orchestration with enable option
        ├── helix.nix            # Helix editor configuration with LSP
        ├── git.nix              # Git configuration with aliases and signing
        ├── zsh.nix              # Zsh shell with oh-my-zsh, aliases, integrations
        ├── zellij.nix           # Zellij multiplexer configuration
        ├── lazygit.nix          # Lazygit TUI configuration
        └── ghostty.nix          # Ghostty terminal emulator configuration

examples/
└── terminal-dev-environment-example.nix  # Usage example configuration

docs/
└── modules/
    └── terminal-dev-environment.md       # Module documentation
```

**Structure Decision**: Following Keystone's existing module pattern with a dedicated `home-manager/modules/` directory. The module is structured similarly to the existing `modules/client/` approach, with a main orchestrator (`default.nix`) that imports tool-specific sub-modules. Each tool gets its own file for maintainability and clarity. Examples and documentation follow Keystone's established conventions.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

N/A - No constitution violations. All gates passed.

