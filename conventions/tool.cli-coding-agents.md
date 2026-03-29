# Convention: CLI Coding Agents (tool.cli-coding-agents)

## Overview

Keystone provisions four CLI coding agents via `keystone.terminal.enable`:
**Claude Code**, **Gemini CLI**, **Codex**, and **OpenCode**. Each tool has
its own instruction file format, discovery paths, and MCP configuration.
This convention documents the correct paths, naming, and nuances for each
tool so that keystone modules generate the right files in the right places.

Keystone also maintains a canonical user-level instruction file at
`~/.keystone/AGENTS.md`. Tool-native files are generated from that same content.

## Instruction File Paths

Each tool discovers project and user-level instruction files at specific
paths. Keystone MUST generate instruction files at these paths so each
tool loads conventions natively (without prompt injection).

### Claude Code

- **Docs**: https://code.claude.com/docs/en/memory#claudemd-files
- **File name**: `CLAUDE.md`
- **User-level**: `~/.claude/CLAUDE.md` — personal preferences for all projects
- **Project-level**: `./CLAUDE.md` or `./.claude/CLAUDE.md` — team-shared, checked into source control
- **Managed policy** (org-wide): `/etc/claude-code/CLAUDE.md` (Linux)
- **Path-scoped rules**: `.claude/rules/*.md` — loaded when Claude reads matching files (supports `paths:` frontmatter glob patterns)
- **Imports**: `@path/to/file.md` syntax, relative to the file containing the import, max 5 hops
- **Size guidance**: Target under 200 lines per file; longer files reduce adherence
- **MCP config**: `~/.claude.json` (global MCP servers)
- **Auto memory**: `~/.claude/projects/<project>/memory/MEMORY.md` — Claude writes this itself; first 200 lines loaded per session

**Keystone generates**:

- `~/.keystone/AGENTS.md` — canonical Keystone instruction file for the user profile
- `~/.claude/CLAUDE.md` — system-wide conventions from `keystone-conventions` derivation
- `~/.claude.json` — MCP server configs (deepwork, chrome-devtools, grafana)
- `.claude/rules/` — not generated (project-specific, not keystone's concern)

### Gemini CLI

- **Docs**: https://geminicli.com/docs/cli/gemini-md/
- **File name**: `GEMINI.md` (default; configurable via `settings.json`)
- **User-level**: `~/.gemini/GEMINI.md` — global instructions for all projects
- **Project-level**: `GEMINI.md` in workspace directories and parent directories
- **JIT context**: `GEMINI.md` files auto-scanned in accessed directories up to trusted root
- **Imports**: `@file.md` syntax for both relative and absolute paths
- **Memory commands**: `/memory show`, `/memory reload`, `/memory add <text>`
- **MCP config**: `~/.gemini/settings.json`
- **Configurable filenames**: `settings.json` → `context.fileName` array can include `["AGENTS.md", "CONTEXT.md", "GEMINI.md"]`

**Keystone generates**:

- `~/.keystone/AGENTS.md` — canonical Keystone instruction file for the user profile
- `~/.gemini/GEMINI.md` — system-wide conventions from `keystone-conventions` derivation
- `~/.gemini/settings.json` — MCP server configs + context settings

### Codex (OpenAI)

- **Docs**: https://developers.openai.com/codex/guides/agents-md
- **File name**: `AGENTS.md` (primary); `AGENTS.override.md` takes precedence
- **User-level**: `~/.codex/AGENTS.md` (or `$CODEX_HOME/AGENTS.md`)
- **Project-level**: `AGENTS.md` in each directory from git root to CWD; at most one file per directory
- **Override**: `AGENTS.override.md` checked before `AGENTS.md` in every location
- **Fallback filenames**: Configurable in `~/.codex/config.toml` via `project_doc_fallback_filenames`
- **Size limit**: Combined instructions cap at 32 KiB by default (`project_doc_max_bytes`)
- **Merge order**: Files concatenate root → CWD; closer directories override earlier guidance
- **Profile switching**: `CODEX_HOME=$(pwd)/.codex codex exec "command"`

**Keystone generates**:

- `~/.keystone/AGENTS.md` — canonical Keystone instruction file for the user profile
- `~/.codex/AGENTS.md` — system-wide conventions (note: Codex calls this `instructions.md` in some versions; use `AGENTS.md` for compatibility)
- `~/.codex/config.toml` — managed MCP server configs, merged with the user's existing Codex settings
- `~/.codex/skills/` — Codex-native skills generated for the curated Keystone surface (`$ks`, `$ks-dev`, `$deepwork`)

**Important nuance**: Codex 0.114.0 does not reliably discover skills when
`SKILL.md` and `agents/openai.yaml` are symlinks. Keystone MUST materialize its
managed skill payload files under `~/.codex/skills/` as regular files during
activation, including in development mode. As a result, Codex skill changes
require a profile activation step (`ks switch` or `ks update --dev`) rather than
appearing instantly through out-of-store symlinks.

### OpenCode

- **Docs**: https://opencode.ai/docs/rules/
- **File name**: `AGENTS.md` (primary)
- **User-level**: `~/.config/opencode/AGENTS.md` — global instructions
- **Project-level**: `AGENTS.md` in project root (traverses upward)
- **Legacy compatibility**: Also reads `CLAUDE.md` (project) and `~/.claude/CLAUDE.md` (global) as fallbacks
- **Disable legacy**: `OPENCODE_DISABLE_CLAUDE_CODE=1` env var disables Claude Code file discovery
- **Additional instructions**: `opencode.json` → `instructions` field supports file paths, globs, and remote URLs
- **MCP config**: `~/.config/opencode/opencode.json`

**Keystone generates**:

- `~/.keystone/AGENTS.md` — canonical Keystone instruction file for the user profile
- `~/.config/opencode/AGENTS.md` — system-wide conventions
- `~/.config/opencode/opencode.json` — MCP server configs

**Note**: OpenCode's Claude Code compatibility means it reads `~/.claude/CLAUDE.md` by default.
Keystone SHOULD NOT configure OpenCode separately for now — it picks up Claude Code's
CLAUDE.md automatically. Disable compatibility later with `OPENCODE_DISABLE_CLAUDE_CODE=1`
when OpenCode-specific configuration is needed.

### GitHub Copilot CLI

- **Docs**: https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli-agents/overview
- **Instruction files**:
  - Repository-wide: `.github/copilot-instructions.md`
  - Path-specific: `.github/instructions/**/*.instructions.md`
  - Agent files: `AGENTS.md` in project root
- **User-level agents**: `~/.copilot/agents/` — custom agent profile `.md` files
- **Project-level agents**: `.github/agents/` — repo-specific agent profiles
- **Org-level agents**: `/agents` in `.github-private` repo
- **MCP config**: `~/.copilot/mcp-config.json` (managed via `/mcp add`)
- **Built-in agents**: Explore, Task, General-purpose, Code-review
- **Invocation**: `/agent`, inline prompt, or `copilot --agent=<name> --prompt ...`
- **Priority**: System > Repository > Organization agents

**Keystone generates**:

- Not currently provisioned by keystone (Copilot is a GitHub-hosted service, not a local CLI tool packaged by keystone)
- Project-level `AGENTS.md` at repo root is read by Copilot automatically

## Summary Table

| Tool        | User Instruction File          | Project Instruction File                        | MCP Config                         |
| ----------- | ------------------------------ | ----------------------------------------------- | ---------------------------------- |
| Claude Code | `~/.claude/CLAUDE.md`          | `./CLAUDE.md` or `./.claude/CLAUDE.md`          | `~/.claude.json`                   |
| Gemini CLI  | `~/.gemini/GEMINI.md`          | `./GEMINI.md`                                   | `~/.gemini/settings.json`          |
| Codex       | `~/.codex/AGENTS.md`           | `./AGENTS.md`                                   | `~/.codex/config.toml`             |
| OpenCode    | `~/.config/opencode/AGENTS.md` | `./AGENTS.md`                                   | `~/.config/opencode/opencode.json` |
| Copilot CLI | `~/.copilot/agents/*.md`       | `.github/copilot-instructions.md` + `AGENTS.md` | `~/.copilot/mcp-config.json`       |

## Keystone Module Responsibilities

### `modules/terminal/conventions.nix`

1. MUST generate the system-wide conventions content from `keystone-conventions` derivation
2. MUST write the canonical user-level instruction file to `~/.keystone/AGENTS.md`
3. MUST derive the tool-native user-level files from the same generated content
4. MUST symlink `~/.config/keystone/conventions/` to the conventions store path for on-demand reading

### `modules/terminal/ai-extensions.nix`

1. MUST generate only the curated Keystone command surface by default: `/ks`, optional `/ks.dev`, and `/deepwork`
2. MUST gate `/ks.dev` on `keystone.development = true`
3. MUST derive tool-facing descriptions and labels from the generated command definitions
4. MUST preserve YAML frontmatter for tools that natively consume Markdown metadata, including Claude Code commands and Codex skills
5. MUST render Gemini commands as native TOML rather than Markdown-based skill files
6. MUST keep command filenames and Codex skill ids stable unless a breaking rename is explicitly intended

### `modules/terminal/cli-coding-agent-configs.nix`

1. MUST generate MCP server configs at each tool's expected path
2. MUST NOT embed secrets (API keys, tokens) — these are world-readable in the Nix store
3. Currently generates: `~/.claude.json`, `~/.gemini/settings.json`, `~/.codex/config.toml`, `~/.config/opencode/opencode.json`
4. Codex config management MUST preserve unrelated user settings and replace only the managed `mcp_servers` subtree

### `modules/os/agents/scripts/agentctl.sh`

1. MUST assemble the 4-layer system prompt (system conventions → notes identity → project AGENTS.md → roles)
2. MUST pass assembled prompt via each tool's native injection mechanism:
   - Claude: `--append-system-prompt`
   - Gemini: `--prompt-interactive`
   - Codex: `--instructions`
   - OpenCode: reads `AGENTS.md` natively from working directory
3. For sandboxed (Podman) agents, SHOULD generate overlay instruction files at the tool-native paths inside the container

### `packages/podman-agent/podman-agent.sh`

1. MUST mount host tool config directories into the container (`~/.claude`, `~/.gemini`, `~/.codex`, `~/.opencode`)
2. MUST mount `~/.config/keystone/` for conventions access
3. SHOULD accept overlay instruction files that combine all context layers

## Sandbox Nuances

When an agent runs inside a Podman container via `podman-agent`:

- The host's `~/.claude.json`, `~/.gemini/settings.json`, `~/.codex/config.toml`, etc. are mounted read-only
- MCP server commands in configs reference absolute Nix store paths — these resolve correctly only if the store closure is available in the container's persistent Nix volume
- Tool-native instruction files (`~/.claude/CLAUDE.md`, etc.) ARE mounted since the host tool dirs are already mounted
- The `SP_FLAGS` prompt injection from agentctl works regardless of sandbox — it passes additional context as CLI args

### Convention Directory Access

`agentctl` / `podman-agent` MUST mount only `~/.config/keystone/conventions/` (read-only) into the container — NOT the full nixos-config repo or keystone submodule. This prevents agents from needlessly exploring infrastructure code that is outside their task scope. When a user needs to work with nixos-config or keystone modules directly, they MUST use `ks agent` or `ks doctor` instead, which have full repo context.

## Rules for Adding New Tools

1. Add the tool's package to `modules/terminal/ai.nix`
2. Add MCP config generation to `modules/terminal/cli-coding-agent-configs.nix`
3. Add instruction file generation to `modules/terminal/conventions.nix` at the tool's expected user-level path
4. Add slash-command or skill generation to `modules/terminal/ai-extensions.nix`, depending on the tool's native workflow surface
5. Add the tool's config directory mount to `packages/podman-agent/podman-agent.sh`
6. Add the tool's prompt injection mechanism to `modules/os/agents/scripts/agentctl.sh`
7. Add a pre-resolved store path env var to `modules/terminal/sandbox.nix`
8. Update this convention document
