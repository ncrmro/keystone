# REQ-012: Project Agent Launcher (`pclaude` CLI)

CLI tool for launching Claude Code sessions scoped to a project, with
worktree isolation and project-specific configuration. Implements
REQ-010.13–010.16.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Stories Covered
- US-004: Launch sub-agent sessions in worktrees

## Affected Modules
- `packages/pclaude/pclaude.sh` — new CLI script
- `packages/pclaude/default.nix` — Nix package definition
- `modules/terminal/projects.nix` — `pclaude` configuration and Claude config directory setup
- `modules/terminal/ai.nix` — existing Claude Code configuration (read-only dependency)
- `bin/worktree` — worktree management (invoked by `pclaude`)
- `packages/podman-agent/podman-agent.sh` — optional sandbox backend
- `flake.nix` — add `pclaude` to overlay

## Data Models

### Claude Project Configuration
Created per-project by the home-manager module (REQ-010.10).

| Item | Path | Notes |
|------|------|-------|
| Config directory | `{notes_path}/.claude-projects/{slug}/` | Created by module |
| Shared credentials | Symlinked from `~/.claude/` | API keys, auth tokens |
| System prompt | `{config_dir}/system-prompt.md` | Rendered via `envsubst` |
| AGENTS.md | `{config_dir}/AGENTS.md` | Aggregated from declared repos |

### Agent Environment Variables
Exported into the Claude Code process (REQ-010.9).

| Variable | Value | Notes |
|----------|-------|-------|
| `PROJECT_NAME` | `{slug}` | Project identifier |
| `PROJECT_PATH` | `{notes_path}/projects/{slug}` | Absolute project directory |
| `PROJECT_README` | `{PROJECT_PATH}/README.md` | Project README path |
| `VAULT_ROOT` | `{notes_path}` | Notes repo root |
| `CLAUDE_CONFIG_DIR` | `{notes_path}/.claude-projects/{slug}` | Project-scoped Claude config |
| `AGENTS_MD` | `{CLAUDE_CONFIG_DIR}/AGENTS.md` | Aggregated context file |

## CLI Contract

### `pclaude [options] [slug]`

Launch Claude Code with project context.

**Arguments**:
- `slug` — project slug (optional; defaults to current project if inside a `pz` session via `$PROJECT_NAME`)

**Options**:
- `--resume <session-id>` — resume an existing Claude Code session (REQ-010.14)
- `--worktree <branch>` — launch in a specific worktree (creates if needed)
- `--sandbox` — run Claude Code via `podman-agent` for isolation
- `--prompt <text>` — append text to the system prompt

**Behavior**:
1. The command MUST resolve the project slug from the argument or `$PROJECT_NAME`
2. The command MUST validate that the project exists at `{notes_path}/projects/{slug}/`
3. The command MUST set environment variables per REQ-010.9
4. The command MUST set `CLAUDE_CONFIG_DIR` to `{notes_path}/.claude-projects/{slug}/`
5. If `--worktree <branch>` is specified:
   a. The command MUST check declared repos in the project's README.md frontmatter
   b. For each repo, the command MUST create a worktree at `{repo}/.worktrees/{branch}/` if it doesn't exist
   c. The command MUST set the working directory to the first repo's worktree
6. The command MUST render the system prompt template via `envsubst` (REQ-010.15)
7. The command MUST launch `claude` with `--config-dir $CLAUDE_CONFIG_DIR`
8. If `--resume` is provided, the command MUST pass `--resume <session-id>` to Claude Code

**Exit codes**:
- `0` — Claude Code exited normally
- `1` — project not found or configuration error
- Passthrough — Claude Code's exit code

### `pclaude list`

List active Claude Code sessions for the current project.

**Behavior**:
1. SHOULD list Claude Code sessions associated with the current `$CLAUDE_CONFIG_DIR`
2. Output MUST include session ID and start time

## Behavioral Requirements

### Configuration Directory

1. The home-manager module MUST create `{notes_path}/.claude-projects/{slug}/` for each discovered project.
2. The module MUST symlink shared credentials from `~/.claude/` into the project config directory.
3. Credential files that MUST be symlinked: `credentials.json`, `auth.json`, or equivalent Claude Code auth files.
4. The config directory MUST be writable by the user (not read-only symlinks for all content).

### System Prompt

5. A system prompt template MUST exist at `{notes_path}/.claude-projects/{slug}/system-prompt.md`.
6. The template MUST be rendered via `envsubst` using the environment variables from REQ-010.9.
7. If the project declares `repos:` in its README.md frontmatter, the system prompt SHOULD include the aggregated `AGENTS.md` content.
8. The rendered system prompt MUST be passed to Claude Code via `--system-prompt` or equivalent mechanism.

### AGENTS.md Aggregation

9. When a project declares `repos:` in README.md YAML frontmatter (REQ-010.11), the module MUST aggregate `AGENTS.md` (or `CLAUDE.md`) files from each declared repo into a single file at `{CLAUDE_CONFIG_DIR}/AGENTS.md` (REQ-010.12).
10. Aggregation MUST concatenate files with `---` separators and repo path headers.
11. If a declared repo is not cloned locally, the aggregation MUST skip it with a warning comment in the output.

### Worktree Integration

12. When `--worktree` is specified, `pclaude` MUST use the `bin/worktree` script (or equivalent logic) to create worktrees.
13. Worktrees MUST be created at `{repo}/.worktrees/{branch}/` following existing conventions.
14. `pclaude` MUST run `direnv allow` in the worktree after creation.
15. The worktree branch name SHOULD default to a pattern like `agent/{slug}/{timestamp}` when not specified.

### OS Agent Compatibility

16. OS agents (per SPEC-007) MUST be able to use `pclaude` in headless mode without desktop integration (REQ-010.16).
17. When run by an OS agent, `pclaude` MUST use the agent's own credentials and SSH keys, not the human user's.

## Edge Cases

- **No repos declared**: If the project's README.md has no `repos:` frontmatter, `pclaude` MUST still work — it launches Claude Code in the project directory with project environment variables but no worktree or repo aggregation.
- **Missing repo clone**: If a declared repo is not cloned at the expected path (`.repos/{owner}/{repo}`), `pclaude` MUST warn but continue with available repos.
- **Concurrent sessions**: Multiple `pclaude` sessions for the same project MUST be supported. Each session uses the same `CLAUDE_CONFIG_DIR` but operates independently.
- **Resume with wrong project**: If `--resume <id>` is used with a different project slug than the original session, behavior is undefined (Claude Code handles session state). The command SHOULD warn if the session ID doesn't match the project context.
- **Sandbox mode**: When `--sandbox` is specified, `pclaude` MUST delegate to `podman-agent claude` with appropriate volume mounts for the project config directory and worktree.
