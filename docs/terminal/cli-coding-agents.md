---
title: CLI coding agents
description: How Keystone configures AI coding CLIs with unified MCP, commands, and skills
---

# CLI coding agents

Keystone manages four AI coding CLIs — Claude Code, Gemini CLI, Codex, and
OpenCode — through a shared Nix module stack. Each CLI receives identical
DeepWork integration, MCP server definitions, and Keystone workflow commands,
adapted to the tool's native configuration format.

## Architecture

Three terminal modules collaborate:

| Module | Responsibility |
|--------|---------------|
| `ai.nix` | Installs CLI packages and the DeepWork binary |
| `cli-coding-agent-configs.nix` | Generates MCP server configs at each tool's expected path |
| `ai-extensions.nix` | Generates Keystone commands and skills for each tool |

`deepwork.nix` sets `DEEPWORK_ADDITIONAL_JOBS_FOLDERS` to point at the curated
job libraries (shared library jobs and keystone-native jobs).

## MCP server configuration

All CLIs share a single `keystone.terminal.cliCodingAgents.mcpServers` option.
The DeepWork MCP server is appended automatically when
`keystone.terminal.deepwork.enable = true`.

| CLI | Config path | Platform flag | Merge strategy |
|-----|------------|---------------|----------------|
| Claude Code | `~/.claude.json` | `claude` | jq — merges `mcpServers` key, preserves runtime state |
| Gemini CLI | `~/.gemini/settings.json` | `gemini` | jq — merges `mcpServers` + `context`, preserves runtime state |
| Codex | `~/.codex/config.toml` | `codex` | Python TOML rewriter — replaces `[mcp_servers]` section |
| OpenCode | `~/.config/opencode/opencode.json` | `opencode` | jq — merges `.mcp` key, preserves runtime state |

Each activation script follows the same safety pattern:

1. Remove stale Nix store symlink if present.
2. Merge managed keys into existing file (preserving runtime state).
3. Create from scratch on first run.

### Adding an MCP server

```nix
keystone.terminal.cliCodingAgents.mcpServers.my-server = {
  command = "${pkgs.my-mcp-server}/bin/my-server";
  args = [ "--flag" "value" ];
  env = { MY_VAR = "value"; };  # WARNING: stored in Nix store, world-readable
};
```

This definition propagates to all four CLIs automatically.

## Commands and skills

`ai-extensions.nix` generates the same Keystone workflow commands (`/ks`,
`/ks.dev`, `/ks.notes`, `/ks.projects`) and skills (`deepwork`, `wrap-up`)
for each CLI, adapted to the tool's native format.

### Format mapping

| CLI | Commands | Skills |
|-----|----------|--------|
| Claude Code | `.claude/commands/{id}.md` with YAML frontmatter | `.claude/skills/{name}/SKILL.md` |
| Gemini CLI | `.gemini/commands/{path}.toml` | `.gemini/commands/{name}.toml` (flattened) |
| Codex | N/A — uses `$skill-name` tokens | `.codex/skills/{name}/SKILL.md` + `agents/openai.yaml` |
| OpenCode | `.config/opencode/commands/{id}.md` | `.config/opencode/skills/{name}/SKILL.md` |

### Tool-specific notes

- **Gemini** flattens skills into its `commands/` directory as TOML files.
  There is no separate `skills/` directory.
- **Codex** does not receive command files. Users invoke workflows via
  `$ks`, `$ks-dev`, etc. Codex skills include an `agents/openai.yaml`
  metadata file alongside each `SKILL.md`. Because this two-file layout
  cannot use `home.file`, Codex skills are written by an activation script
  with stale-skill cleanup.
- **Claude Code** and **OpenCode** share the same directory structure
  (commands + skills with `SKILL.md`).

## Capability-driven generation

The set of published commands depends on resolved capabilities:

| Capability | Commands enabled |
|-----------|-----------------|
| `ks` (always) | `/ks` |
| `notes` (default) | `/ks.notes` |
| `project` (default) | `/ks.projects` |
| `ks-dev` (dev mode only) | `/ks.dev` |

Capabilities merge from base defaults, archetype defaults (e.g., `engineer`),
explicit `aiExtensions.capabilities`, and dev-mode gating.

## Development mode

When `keystone.development = true`:

- `DEEPWORK_ADDITIONAL_JOBS_FOLDERS` points at local repo checkouts instead of
  Nix store derivations, so job edits take effect immediately.
- Commands and skills are written to the live repo checkout (appearing as git
  diffs) rather than via `home.file` symlinks.
- `ks-dev` capability is automatically enabled.

## DeepWork integration

The DeepWork MCP server binary (`pkgs.keystone.deepwork`) is installed by
`ai.nix`. The server discovers jobs from two roots via
`DEEPWORK_ADDITIONAL_JOBS_FOLDERS`:

1. **Shared library jobs** — from the `Unsupervisedcom/deepwork` repo's
   `library/jobs/` directory.
2. **Keystone-native jobs** — from `ncrmro/keystone/.deepwork/jobs/`.

In locked mode both resolve to Nix store copies (`pkgs.keystone.deepwork-library-jobs`
and `pkgs.keystone.keystone-deepwork-jobs`). In dev mode both resolve to local
checkouts.
