---
layout: default
title: Terminal Module
---

# Terminal Module

The Keystone Terminal module (`keystone.terminal`) provides a comprehensive, opinionated command-line development environment. It is designed to work consistently across NixOS, macOS, and other Linux distributions via Home Manager.

## Enable the Module

To enable the terminal environment in your Home Manager configuration:

```nix
keystone.terminal.enable = true;
```

This installs and configures:
- **Helix**: Modal text editor (default)
- **Zsh**: Interactive shell with Starship prompt
- **Zellij**: Terminal multiplexer
- **Lazygit**: Git TUI
- **Git**: Configured with LFS and sensible defaults
- **Utilities**: `eza`, `ripgrep`, `htop`, `zoxide`, `direnv`, `yazi`

## Helix Editor

Keystone configures [Helix](https://helix-editor.com/) as the default editor (`EDITOR` and `VISUAL` environment variables are set to `hx`).

### Key Features
- **Language Support**: Pre-configured LSPs for Bash, Markdown, Nix, TypeScript, Docker, YAML, JSON, and more.
- **Theme**: Uses `kinda_nvim` theme by default.
- **Soft Wrap**: Enabled by default with a text width of 120 columns.

### Keybindings (Normal Mode)

| Key | Action | Description |
| :--- | :--- | :--- |
| `Ret` (Enter) | `:write` | Save the current buffer. |
| `F6` | Markdown Preview | Selects all text, renders Markdown to HTML using Pandoc, opens it in the default browser, and copies the preview URL to the clipboard. |
| `F7` | Toggle Soft Wrap | Toggles soft wrapping of text. |

### Markdown Preview
The Markdown preview feature (`F6`) uses a robust helper script (`helix-preview-markdown`) that:
1. Pipes the full content of the current file (even if unsaved) to Pandoc.
2. Renders it to `/tmp/helix-preview.html`.
3. Opens the HTML file in your system's default browser (via `xdg-open`).
4. Copies the URL (`file:///tmp/helix-preview.html`) to your clipboard (using `wl-copy` on Linux or `pbcopy` on macOS) so you can paste it into a different browser if preferred.

### Language Servers
The module installs and configures the following language servers automatically:
- **Markdown**: `marksman`, `harper-ls` (grammar checking)
- **Nix**: `nixfmt`
- **Bash**: `bash-language-server`
- **TypeScript**: `typescript-language-server`, `prettier`
- **Docker**: `docker-langserver`, `docker-compose-langserver`
- **YAML**: `yaml-language-server`
- **Ruby**: `ruby-lsp`, `solargraph`

## Shell Environment

### Zsh
- **Prompt**: [Starship](https://starship.rs/) prompt is configured for a minimal, informative interface.
- **Navigation**: [Zoxide](https://github.com/ajeetdsouza/zoxide) is enabled for fast directory jumping (`z <dir>`).
- **Aliases**:
  - `ls`, `l` -> `eza -1l` (modern ls replacement)
  - `grep` -> `rg` (ripgrep)
  - `g` -> `git`
  - `lg` -> `lazygit`
  - `zs` -> `zesh connect` (session manager)

### Zellij
[Zellij](https://zellij.dev/) is configured with sensible keybindings and acts as the default terminal multiplexer.
