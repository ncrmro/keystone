# Terminal Development Environment Specification

## Overview

- **Goal**: Provide a cohesive terminal-based development environment with modern tools, configured through a single Home Manager flake output.
- **Scope**: Shell, editor, multiplexer, git integration, and AI-assisted development tools for terminal-centric workflows.
- **Automation**: All features must be testable via `nix flake check` with VM-based validation.

## Functional Requirements

### FR-001 Shell Environment

The terminal environment MUST provide a modern, productive shell experience.

- Zsh with completion and history management
- Directory navigation with fuzzy matching and frecency tracking
- Automatic environment loading for project-specific configurations
- Unified prompt showing git status, execution time, and context
- Sensible aliases for common operations
- Fast plugin loading without startup lag

### FR-002 Text Editor

The terminal environment MUST include a modal text editor with language server support.

- Helix editor as the default editor
- Language server protocol integration for common languages
- Syntax highlighting and formatting
- Modal editing with intuitive keybindings
- Editor set as EDITOR and VISUAL environment variables
- Theme support with sensible defaults

### FR-003 Terminal Multiplexer

The terminal environment MUST support session management and window splitting.

- Zellij as the terminal multiplexer
- Tab and pane management without conflicting keybindings
- Session persistence across disconnections
- Integration with shell environment
- Minimal UI overhead for focus on content
- Keybindings that don't conflict with Claude Code or other tools

### FR-004 Git Integration

The terminal environment MUST provide efficient git workflows.

- Git CLI with sensible defaults and aliases
- Git LFS support enabled by default
- Terminal UI for git operations (lazygit)
- Automatic push remote setup
- Configurable user identity (name, email)
- Default branch set to "main"

### FR-005 File Navigation

The terminal environment MUST support efficient file browsing and searching.

- Modern ls replacement with colors and git integration
- Fast recursive grep with regex support
- Terminal file manager for visual navigation
- CSV viewing for data inspection

### FR-006 AI Development Tools

The terminal environment MUST include AI-assisted development capabilities.

- Claude Code CLI for AI-powered development
- Integration with shell environment
- Automatic installation and updates
- Keybinding compatibility with multiplexer

### FR-007 Language Server Support

The editor MUST support language servers for common development languages.

- Bash, Docker, YAML, JSON, HTML, CSS language servers
- TypeScript/JavaScript with prettier formatting
- Ruby with multiple LSP backends
- Helm chart support for Kubernetes
- Markdown and prose linting with harper
- Automatic formatting on save for supported languages

### FR-008 Configuration Interface

The module MUST expose a clear, documented configuration interface.

- Single `keystone.terminal.enable` option to activate all features
- Required git user configuration (name, email)
- Configurable default editor
- Optional git integration toggle
- Minimal required configuration for quick setup

## Flake Output Interface

### Home Manager Module

**Output**: `homeModules.terminal`

```nix
{
  inputs = {
    keystone.url = "github:ncrmro/keystone";
  };

  outputs = { home-manager, keystone, ... }: {
    homeConfigurations.user = home-manager.lib.homeManagerConfiguration {
      modules = [
        keystone.homeModules.terminal
        {
          keystone.terminal = {
            enable = true;
            git = {
              userName = "Full Name";
              userEmail = "email@example.com";
            };
          };
        }
      ];
    };
  };
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `keystone.terminal.enable` | bool | - | Enable terminal development environment |
| `keystone.terminal.editor` | string | `"hx"` | Default editor command |
| `keystone.terminal.git.enable` | bool | `true` | Enable git configuration |
| `keystone.terminal.git.userName` | string | `null` | Git commit author name (required) |
| `keystone.terminal.git.userEmail` | string | `null` | Git commit email (required) |

### Module Structure

```
modules/keystone/terminal/
├── default.nix      # Main module with options interface
├── shell.nix        # Zsh, starship, zoxide, direnv, zellij
├── editor.nix       # Helix with LSP configuration
└── ai.nix           # Claude Code and AI tools
```

## Non-Functional Requirements

### NFR-001 Performance

- Shell startup time under 500ms
- Editor launches in under 1 second
- Tab completion responds in under 100ms
- No blocking operations during normal usage

### NFR-002 Consistency

- Keybindings follow common conventions
- Colors and themes consistent across tools
- Configuration merged without conflicts
- Updates don't break existing workflows

### NFR-003 Documentation

- All options documented with examples
- Configuration validated with assertions
- Error messages provide remediation guidance
- Common use cases documented in CLAUDE.md

## Testing Requirements

### TR-001 VM Testing

**Flake check output**: `checks.x86_64-linux.vm-terminal`

- Test user with terminal environment enabled
- SSH access for interactive validation
- All tools accessible in PATH
- Git configuration applied correctly
- Editor and LSPs functional

### TR-002 Integration Testing

- Home-manager activation succeeds
- No conflicting package installations
- Service dependencies resolved correctly
- XDG configuration files created properly

## Success Criteria

### SC-001 Activation Success

- Fresh activation completes without errors
- All programs available in PATH after login
- Shell starts with configured plugins loaded
- Editor launches with LSPs running

### SC-002 Configuration Validation

- Missing required options produce clear error messages
- Invalid git email detected during build
- Conflicting keybindings documented and resolved
- Option changes apply without breaking existing sessions

### SC-003 User Experience

- New users can configure in under 5 minutes
- Common development tasks supported out of box
- Keybindings discoverable and documented
- Tools work together without manual integration

## Out of Scope

The following features are explicitly out of scope for this specification:

- **GUI terminal emulator configuration**: Ghostty and other graphical terminals (separate module)
- **Desktop integration**: Desktop-specific keybindings, notifications
- **Language-specific development environments**: Node.js, Python, Rust toolchains (use direnv)
- **Container tools**: Docker, podman, kubectl (NixOS-level configuration)
- **Database clients**: psql, mysql, redis-cli (project-specific)
- **Cloud provider CLIs**: AWS, GCP, Azure (project-specific)
- **Custom shell scripts**: User-specific automation (home-manager configuration)
- **SSH configuration**: Host definitions, keys (home-manager SSH module)

## Migration Notes

### From terminal-dev-environment Module

The new `keystone.terminal` module consolidates functionality previously in `programs.terminal-dev-environment`:

**Old configuration**:
```nix
{
  imports = [ inputs.keystone.homeModules.terminalDevEnvironment ];
  programs.terminal-dev-environment = {
    enable = true;
    tools = {
      git = true;
      editor = true;
      shell = true;
      multiplexer = true;
      terminal = false;  # GUI terminal
    };
  };
}
```

**New configuration**:
```nix
{
  imports = [ inputs.keystone.homeModules.terminal ];
  keystone.terminal = {
    enable = true;
    git = {
      userName = "Your Name";
      userEmail = "you@example.com";
    };
  };
}
```

### Breaking Changes

- Git user name and email are now required when `git.enable = true`
- Editor defaults to `hx` (explicit, not inferred)
- Zellij keybindings updated to avoid conflicts with Claude Code
- Ghostty configuration moved to separate desktop module
