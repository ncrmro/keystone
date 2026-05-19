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
- **MCP config**: `~/.claude.json` — MCP server configs (deepwork, chrome-devtools, grafana, process-compose)
- **Auto memory**: `~/.claude/projects/<project>/memory/MEMORY.md` — Claude writes this itself; first 200 lines loaded per session

**Keystone generates**:

- `~/.keystone/AGENTS.md` — canonical Keystone instruction file for the user profile
- `~/.claude/CLAUDE.md` — system-wide conventions from `keystone-conventions` derivation
- `~/.claude.json` — MCP server configs (deepwork, chrome-devtools, grafana, process-compose)
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

**Important nuance**: Codex 0.114.0 does not reliably discover skills when the
individual `SKILL.md` or `agents/openai.yaml` *files* are symlinks. The
consumer-flake symlink model (see "Consumer Flake Agent Assets" below)
sidesteps this: `~/.codex/skills` itself is a directory symlink, but each
`SKILL.md` and `agents/openai.yaml` at the resolved path is a regular file in
the user's git checkout. Codex reads them as ordinary files. The refresh path
is `ks sync-agent-assets` (manual), which writes regenerated skill content
into the consumer flake — never directly into `~/.codex/skills/`.

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

## Consumer Flake Agent Assets

Keystone-generated CLI coding agent assets (per-tool skills and subagents) are
materialized into the consumer flake at `<consumer-flake>/agents/<tool>/`, and
each tool's home-dir subdirectory is a home-manager-managed symlink pointing
there. This makes every change to a keystone-shipped skill visible as a git
diff in the consumer flake, so users can review skill upgrades commit-by-commit
and roll back via standard git workflow.

### Source layout

The canonical source-of-truth in the consumer flake:

```
<consumer-flake>/agents/
  _shared/                            committed; canonical source-of-truth
    AGENTS.md                         host-rendered instruction file (regular file)
    skills.yaml                       optional user-authored skill overrides
    skills/<key>/SKILL.md             canonical skill body (dotted key)
    skills/<key>/<convention>.md      colocated conventions/roles for the skill
  claude/                             gitignored (rendered output)
    CLAUDE.md                         symlink → ../_shared/AGENTS.md
    skills/<key>/SKILL.md             rendered copy of _shared/skills/<key>/
    agents/<name>.md                  → ~/.claude/agents/<name>.md
  gemini/                             gitignored (rendered output)
    GEMINI.md                         symlink → ../_shared/AGENTS.md
    skills/<key>/SKILL.md             rendered copy of _shared/skills/<key>/
    agents/                           reserved; Gemini lacks subagents today
  codex/                              gitignored (rendered output)
    AGENTS.md                         symlink → ../_shared/AGENTS.md
    skills/<hyphen-key>/SKILL.md      hyphenated-name body with codex footer
    skills/<hyphen-key>/agents/openai.yaml
    skills/<hyphen-key>/<convention>.md
    agents/                           reserved; Codex lacks subagents today
```

Each `<tool>/<subdir>` (e.g. `claude/skills`, `claude/agents`, `gemini/skills`,
`codex/skills`) is a directory symlink from the home dir. Per-tool instruction
files (CLAUDE.md, GEMINI.md, codex AGENTS.md) are **two-hop symlinks**: the
home-dir file points at the consumer-flake per-tool file, which itself is a
symlink to `_shared/AGENTS.md`. SKILL.md, subagent files, and the canonical
files under `_shared/` are regular files — each tool reads them normally.

The committed surface in a consumer flake is `_shared/`:
- `_shared/AGENTS.md` — one host-rendered instruction file.
- `_shared/skills/<key>/` — one canonical skill body (and colocated
  conventions/roles) per skill. Claude and Gemini receive the identical
  content as gitignored rendered copies under their per-tool dirs.
- Optionally `_shared/skills.yaml` for user-authored skill overrides.

Codex's per-tool dir contains genuinely different content (hyphenated skill
names, the codex skill-invocation footer, and `agents/openai.yaml`), so it
does not share the canonical `_shared/skills/` tree — its rendering stays
under `agents/codex/` as gitignored output. Everything under `claude/`,
`gemini/`, and `codex/` is regenerated by `ks sync-agent-assets` and
gitignored — see the recommended `.gitignore` entries below.

Keystone-canonical files that are not tool-native (`~/.keystone/AGENTS.md`,
`~/.keystone/repos/AGENTS.md`) remain immutable Nix-store-backed writes via
`home.file.text` in `modules/terminal/conventions.nix`. They are not under
the consumer-flake pattern because no tool reads them at those paths;
they are reference material for keystone itself.

OpenCode's instruction file (`~/.config/opencode/AGENTS.md`) also stays on
the immutable write path for this iteration — opencode is not yet wired
into the symlink activation (future scope).

### Skill schema

`<consumer-flake>/agents/_shared/skills.yaml` is an **optional** user-authored
file with the same flat-map schema as `conventions/archetypes.yaml.skills` in
the keystone repo. When present, `ks sync-agent-assets` merges it on top of
the keystone defaults: user keys win wholesale (no field-level merge). Keys
only in the user file are emitted as new skills.

```yaml
skills:
  ks.engineer:                       # override an existing keystone key
    description: "Custom phrasing"
    colocated_conventions: []
  my.custom-skill:                   # add a new key
    description: "User-only skill"
    template: my-custom-skill-skill.template.md
```

The yaml key is the canonical slash-command name. Keys starting with `ks.`
are gated by the manifest's `publishedCommands` — they only emit if the
host has the matching command enabled. Other keys (e.g. `deepwork`,
`my.custom-skill`) are always emitted. For each key:

- Claude/Gemini/OpenCode use the dotted key as the on-disk skill directory.
- Codex uses the same key with `.` → `-` (so `ks.engineer` becomes
  `ks-engineer` under `codex/skills/`), because Codex does not accept dots
  in skill names.
- The body template resolves first to the `template:` field in yaml, and
  falls back to `<key with . → -><suffix>` (`<key>-skill.template.md`).
- Codex display names resolve first to the keystone command_display_name
  table, then fall back to title-casing the key on `.`/`_`/`-` boundaries
  (so `deepwork` renders as "Deepwork").

If `_shared/skills.yaml` is absent, the renderer uses keystone defaults
verbatim.

### Recommended consumer-flake `.gitignore`

Consumer flakes SHOULD commit `_shared/` and gitignore the rendered per-tool
dirs:

```
/agents/claude/
/agents/gemini/
/agents/codex/
```

The keystone template at `templates/default/` ships these entries by default;
existing consumer flakes upgrading to this layout SHOULD add them in the
same commit that introduces `_shared/AGENTS.md`.

### Rules

11. The consumer flake at `<consumer-flake>/agents/<tool>/<subdir>/` MUST be
    the sole source-of-truth for keystone-generated and user-authored agent
    assets for the symlinked tools (Claude, Gemini, Codex). There is no
    parallel source in `$HOME` for those tools. **OpenCode is exempt** for
    now — its skills and instruction file still write to `$HOME` directly
    while it is being prepared to join the symlink set in a future change.
12. Home-manager activation MUST create each `~/.<tool>/<subdir>` as a
    directory symlink pointing into `<consumer-flake>/agents/<tool>/<subdir>/`.
    For the admin user, activation MUST `mkdir -p` the consumer-flake target
    before linking so the symlink is never dangling on first run. For OS
    agent users, the activation MUST NOT `mkdir -p` the target — see rule 18.
13. The consumer-flake path MUST be resolved at runtime from
    `/run/current-system/keystone-system-flake`. This is a **regular file**
    written by `modules/shared/system-flake.nix` containing the consumer
    flake path as text (single line plus trailing newline), not a symlink —
    implementations MUST read it with `read`/`cat` and strip the trailing
    newline, matching the Rust precedent in
    `packages/ks/src/repo.rs:read_system_flake_pointer_from`. Implementations
    MUST NOT use `[ -L ... ]`/`readlink` against this path (always false /
    always returns the wrong value). A `KEYSTONE_CONSUMER_FLAKE` env var
    MUST be honoured as an override for testing and ad-hoc invocations.
14. The `ks sync-agent-assets` command MUST be the only writer to the
    consumer-flake `agents/` directory. It MUST be run manually — home-manager
    activation MUST NOT auto-trigger it. This guarantees the user's git tree
    is never silently rewritten during `ks switch` / `ks update --dev`.
15. `ks sync-agent-assets` MUST unconditionally overwrite keystone-generated
    files. The user's override mechanism is git: review the diff, `git checkout`
    to restore a previous version, then commit. No in-file markers, no skip-if-exists.
16. User-authored skills and keystone-generated skills MUST share a single
    namespace per tool. Keystone-curated skills use the `ks*` name prefix
    (e.g. `ks.notes`, `ks.dev`); user-authored skills SHOULD avoid that
    prefix to reduce collision risk on regen.
17. Subagent format support is currently Claude-only (`~/.claude/agents/<name>.md`).
    Gemini and Codex subagent paths are reserved but the sync script writes
    nothing to them. When upstream Gemini/Codex add subagent loaders, the
    convention extends with no compatibility break.
18. The symlink activation MUST run for both the admin user and OS agent users.
    Each agent's `~/.<tool>/<subdir>` MUST symlink to the same consumer-flake
    `agents/<tool>/<subdir>/` path the admin uses. This L1→L2 inheritance
    mechanism lets `keystone.os.agents.<name>` principals run the same
    skills/agents the admin authored, without per-agent duplication, and is
    the foundation for OS-agent auto-loops that don't require DeepWork.
    For OS agent users, the activation MUST NOT attempt to `mkdir -p` the
    consumer-flake target — the admin's prior activation created it, and the
    agent lacks write permission inside the admin's home.
19. Per-tool instruction files MUST resolve through **two hops** of symlinks
    into the canonical `_shared/AGENTS.md`:
    - `~/.claude/CLAUDE.md`   → `<consumer-flake>/agents/claude/CLAUDE.md`
                              → `<consumer-flake>/agents/_shared/AGENTS.md`
    - `~/.gemini/GEMINI.md`   → `<consumer-flake>/agents/gemini/GEMINI.md`
                              → `<consumer-flake>/agents/_shared/AGENTS.md`
    - `~/.codex/AGENTS.md`    → `<consumer-flake>/agents/codex/AGENTS.md`
                              → `<consumer-flake>/agents/_shared/AGENTS.md`
    The home-dir → consumer-flake hop is the home-manager symlink activation;
    the consumer-flake → `_shared/AGENTS.md` hop is rewritten on each run of
    `ks sync-agent-assets`. The canonical `_shared/AGENTS.md` is the only
    regular file in the chain — every tool reads the same bytes.
    `modules/terminal/conventions.nix` MUST NOT write the per-tool
    instruction files via `home.file.<path>.text` — the symlink activation
    owns them. The Keystone-canonical files `~/.keystone/AGENTS.md` and
    `~/.keystone/repos/AGENTS.md`, and the OpenCode instruction file
    `~/.config/opencode/AGENTS.md`, remain managed via `home.file.text`
    (no tool reads them through a path that needs the symlink contract).
20. The symlink activation MUST handle file-level migrations from the prior
    `home.file`-based mechanism. When the previous generation wrote
    `~/.claude/CLAUDE.md` as an immutable Nix-store symlink, home-manager
    removes that symlink during the switch to the new generation; the
    activation then either creates the new file symlink (if the
    consumer-flake target exists) or skips with a warning telling the user
    to run `ks sync-agent-assets`.

### First-time setup and migration

After this convention lands, the consumer flake's `agents/_shared/` directory
is the single committed source of truth for the instruction file, skill
bodies, and colocated conventions. Everything under
`agents/{claude,gemini,codex}/` is rendered output, gitignored. First-time
setup on a fresh host or upgrade from the pre-symlink era:

```
ks sync-agent-assets       # writes _shared/ and renders the per-tool dirs
cd <consumer-flake>
git status                 # _shared/ contents should show as untracked

# Ensure the per-tool dirs are gitignored before staging.
cat >> .gitignore <<'EOF'
/agents/claude/
/agents/gemini/
/agents/codex/
EOF

git add agents/_shared/ .gitignore
git commit -m "feat: add keystone shared agent assets"
ks switch                  # activation creates the home-dir symlinks
```

A pre-existing non-empty real directory at one of the symlink sites
(`~/.claude/skills`, `~/.claude/agents`, `~/.gemini/skills`, `~/.codex/skills`)
will block the activation with a clear error message. Remove or move the
directory aside before re-running activation.

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
7. `ks.notes` SHOULD act as the durable-memory skill for decision capture, report capture, and zk-linked shared-surface refs
8. Keystone workflow skills SHOULD remind agents to use `ks.notes` when work produces durable findings or decisions
9. Skill directory names for Claude Code, Gemini, and OpenCode MUST use the dot-notation command id (e.g., `ks.system`, `ks.dev`). The `codexSkillName` dot-to-dash transform MUST only apply to Codex skills, which do not support dots in skill names.
10. Generated instruction files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) MUST NOT duplicate the list of available skills. CLI coding agents inject the skill catalog into the system prompt automatically; repeating it in instruction files wastes context tokens.

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
