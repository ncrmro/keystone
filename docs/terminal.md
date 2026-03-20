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

## hwrekey — Secrets Rekeying

The `hwrekey` command automates re-encrypting agenix secrets with your YubiKey and (optionally) handling the full submodule commit/push/flake-update workflow.

### Enable

`hwrekey` is available when `keystone.terminal.ageYubikey.enable = true`.

```nix
keystone.terminal.ageYubikey = {
  enable = true;
  identities = [ "AGE-PLUGIN-YUBIKEY-..." ];
  # Optional: enable submodule workflow
  secretsFlakeInput = "agenix-secrets";
};
```

### Usage

```bash
cd agenix-secrets
hwrekey
```

### What It Does

1. Runs `agenix --rekey` using the YubiKey identity file (touch prompt per secret, no SSH password)
2. If `secretsFlakeInput` is set:
   - Commits and pushes the rekeyed secrets in the current (submodule) repo
   - Runs `nix flake update <secretsFlakeInput>` in the parent repo
   - Commits the submodule pointer + `flake.lock` together in the parent repo
3. If `secretsFlakeInput` is null, only runs the rekey — you commit manually

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable age-plugin-yubikey identity management |
| `identities` | list of str | `[]` | YubiKey identity strings (`AGE-PLUGIN-YUBIKEY-...`) |
| `identityPath` | str | `~/.age/yubikey-identity.txt` | Path to the combined identity file |
| `secretsFlakeInput` | null or str | `null` | Flake input name for the secrets submodule |

### When to Use

Run `hwrekey` after any change to `secrets.nix` that adds or removes key recipients (e.g., enrolling a new YubiKey, adding a new host key, removing a decommissioned machine). See [Hardware Keys](hardware-keys.md) for the full YubiKey enrollment workflow.

## Conventions

The conventions module generates `~/.config/keystone/AGENTS.md` at build time from keystone conventions, providing consistent project guidance for AI coding agents and developers.

```nix
keystone.terminal.conventions = {
  enable = true;            # Default: true
  archetype = "engineer";   # Default: "engineer"
};
```

The `archetype` option controls which convention set is applied. The generated file is available to all tools that read `AGENTS.md` or `CLAUDE.md`.

## DeepWork

The DeepWork module integrates workflow-driven development with quality gates into the terminal environment.

```nix
keystone.terminal.deepwork = {
  enable = true;            # Default: true
};
```

When enabled, the `DEEPWORK_ADDITIONAL_JOBS_FOLDERS` environment variable is set, allowing the DeepWork MCP server to discover project-specific job definitions alongside the built-in ones.

## Personal Information Management

Keystone integrates the [Pimalaya](https://pimalaya.org/) CLI suite for email, calendars, contacts, and timers:

| Tool | Enable | Purpose |
|------|--------|---------|
| himalaya | `keystone.terminal.mail.enable = true` | Email (IMAP/SMTP) |
| calendula | `keystone.terminal.calendar.enable = true` | Calendars (CalDAV) |
| cardamum | `keystone.terminal.contacts.enable = true` | Contacts (CardDAV) |
| comodoro | `keystone.terminal.timer.enable = true` | Pomodoro timers |

Calendar and contacts auto-default credentials from the mail config. See [Personal Information Management](personal-info-management.md) for full usage documentation and [Agents](agents.md) for `agent-mail` usage (structured email templates for OS agents).
