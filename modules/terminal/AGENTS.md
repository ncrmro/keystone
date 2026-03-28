# Terminal Module — Editing Guide (`modules/terminal/`)

This guide covers conventions for editing the terminal module. For the full user-facing
reference, see `docs/terminal.md`.

**Key constraint**: Terminal and desktop modules are **home-manager based**, not NixOS
system modules. Changes only require `ks build` (fast, no sudo) unless they touch
NixOS-level options.

## Shell (`shell.nix`)

Zsh + oh-my-zsh (robbyrussell), starship, zoxide, direnv+nix-direnv, zellij.

Shell aliases and zellij keybinds are defined here. When adding keybinds, check for
conflicts with Claude Code (`Ctrl+G`) and lazygit (`Ctrl+O`) — those are unbound
intentionally.

## Editor (`editor.nix`)

Helix with custom keybindings and 25+ language servers. Key bindings:

- `Return` → `:write`, `F6` → markdown preview, `F7` → toggle soft wrap

When adding a new LSP, add both the package and the language config. `harper-ls`
applies to 20+ languages for grammar/prose checking — do not add it again per-language.

## Git (`git.nix` via `terminal/default.nix`)

SSH signing is on by default (`gpg.format = "ssh"`, signing key `~/.ssh/id_ed25519`).
`push.autoSetupRemote = true` and `submodule.recurse = true` are always set.

Required options: `keystone.terminal.git.userName` and `keystone.terminal.git.userEmail`.

## AI Tools (`ai.nix`)

Four tools: Claude Code (NPM), Gemini CLI, Codex, OpenCode (last three from llm-agents flake).
All available when `keystone.terminal.enable = true` — agents get the identical environment.

`modules/terminal/ai-commands/*.md` are shared metadata-aware templates for AI
tool command and skill generation. Each file MUST use YAML frontmatter with at
least a `description` field.

Keystone maps those templates into each tool's native format:

- Claude Code commands keep YAML frontmatter in `~/.claude/commands/*.md`
- Gemini commands are rendered as `~/.gemini/commands/*.toml`
- Codex skills are rendered as `~/.codex/skills/*/SKILL.md` with YAML frontmatter
- OpenCode commands receive the Markdown body only

Generators consume parsed metadata and body separately, so do not rely on the
first line of the body as implicit metadata.

## Mail (`mail.nix`)

**CRITICAL**: The `login` field is the Stalwart **account name** (e.g., `"ncrmro"`),
NOT the email address. Using the email as login causes auth failures.

**Folder mappings** (Stalwart defaults):

| Himalaya | Stalwart      |
| -------- | ------------- |
| Sent     | Sent Items    |
| Drafts   | Drafts        |
| Trash    | Deleted Items |

See `conventions/tool.himalaya.md` for full himalaya CLI reference.

## Age-YubiKey / hwrekey (`age-yubikey.nix`)

The `hwrekey` workflow: detect YubiKey → match serial → `agenix --rekey` →
commit+push secrets submodule → update parent flake input.

Retries up to 3x with 3s backoff for pcscd contention. Requires `secretsFlakeInput`
and `configRepoPath` options to be set.

## SSH Auto-Load (`ssh-auto-load.nix`)

Systemd user service that loads SSH keys at login. **Security**: SSH private keys are
host-bound and never stored in agenix — only passphrases are managed as secrets
(`{hostname}-ssh-passphrase`). Service polls for `SSH_AUTH_SOCK` with 5s timeout.

## Sandbox (`sandbox.nix`)

Podman-based AI agent sandboxing. Sets `PODMAN_AGENT_*` env vars consumed by
`podman-agent` package. Maintains a persistent `nix-agent-store` volume so the Nix
store doesn't need to be rebuilt on each invocation.

## Conventions (`conventions.nix`)

Generates `~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, `~/.codex/AGENTS.md` from
`conventions/archetypes.yaml`. The archetype is set per-agent via
`keystone.os.agents.<name>.archetype`.

**Budget warning**: emits a Nix warning if the generated file exceeds `maxGlobalBytes`
(default 16KB). If triggered, move conventions from `inlined_conventions` to
`referenced_conventions` in `archetypes.yaml`.

## Development Mode vs Locked Mode (`development` + `repos` in `terminal/default.nix`)

**Development mode** (`development = true` with repos registered): Generated files
(`~/.claude/commands/`, `~/.claude/CLAUDE.md`, etc.) are out-of-store symlinks, and
repo-backed shell entrypoints in the user path are linked from the checkout →
edits take effect immediately without rebuild after activation.

**Codex exception**: Codex 0.114.0 does not reliably discover skills when
`SKILL.md` and `agents/openai.yaml` are symlinks. Keystone therefore materializes
managed files under `~/.codex/skills/` as regular files during activation, even in
development mode. Codex skill template changes still require `ks switch` or
`ks update --dev` to refresh the copied files.

**Locked mode** (default): Files are immutable Nix store copies. Rebuild required.

```nix
# In nixos-config, enable development mode:
keystone.development = true;
# repos are auto-populated from flake inputs via keystone.repos
```

The `development` boolean and `repos` attrset are bridged from NixOS-level
`keystone.development` and `keystone.repos` by `users.nix`. Terminal modules
look up local checkout paths via `repos` entries by `flakeInput` name.

New file-generating modules MUST use `config.lib.file.mkOutOfStoreSymlink` when
development mode is active, falling back to Nix store `source` otherwise. New
user-facing repo `.sh` commands SHOULD use the same development-mode path
switching instead of always packaging an immutable store copy.

## Tasks / Calendar / Contacts / Timer

These modules (`tasks.nix`, `calendar.nix`, `contacts.nix`, `timer.nix`) all follow the
same credential inheritance pattern — they read from `keystone.terminal.mail` options
rather than requiring separate config. `cfait` (tasks) uses a wrapper script to resolve
the password command at launch since it only supports plaintext passwords in config.
