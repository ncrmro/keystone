---
layout: default
title: Terminal Module
---

# Terminal Module

The `keystone.terminal` module provides a complete terminal development environment with modern tools and sensible defaults.

## Overview

The terminal module includes:
- **Helix** - Modal text editor with language server support
- **Zsh** - Interactive shell with starship prompt
- **Zellij** - Terminal multiplexer
- **Git** - Version control with helpful aliases
- **Lazygit** - Terminal UI for Git operations

## Configuration

Enable the terminal module in your home-manager configuration:

```nix
keystone.terminal = {
  enable = true;
  git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";
  };
};
```

## Helix Editor

### Soft Wrap

The Helix editor is configured with **soft-wrap enabled by default** for better readability of long lines. This visual wrapping does not insert hard line breaks in your files.

**Toggle soft-wrap in editor:**
```
:toggle soft-wrap.enable
```

**Configuration options** (in `modules/terminal/editor.nix`):
- `enable` - Enable/disable soft wrap (default: `true`)
- `max-wrap` - Maximum characters before forced wrap (default: `25`)
- `max-indent-retain` - Indentation retained on wrapped lines (default: `0`)
- `wrap-indicator` - Visual indicator for wrapped lines (default: `""` - hidden)

For more details, see the [Helix soft-wrap documentation](https://docs.helix-editor.com/editor.html#editorsoft-wrap-section).

### Language Server Support

Helix includes language servers for:
- Nix (nixfmt)
- Bash
- TypeScript/JavaScript
- YAML
- JSON
- HTML/CSS
- Docker
- Markdown (Harper grammar/spell checker)
- And many more...

## Git Configuration

The module provides convenient Git aliases:
- `g s` - Switch branches
- `g f` - Fetch
- `g p` - Pull
- `g b` - List branches
- `g st` - Concise status
- `g co` - Checkout
- `g c` - Commit

## Shell (Zsh)

Includes modern shell enhancements:
- **Starship** prompt with Git integration
- **Zoxide** for smart directory navigation (`z <directory>`)
- **direnv** for automatic environment loading
- **Eza** for better file listings

## Module Reference

- **Source**: `modules/terminal/`
- **Type**: Home-manager module
- **Option namespace**: `keystone.terminal`

See [CLAUDE.md](../CLAUDE.md) for detailed module structure and options.
