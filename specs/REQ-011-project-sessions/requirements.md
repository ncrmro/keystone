# REQ-011: Project Sessions (`pz` CLI)

Session management CLI for creating, resuming, and listing Zellij terminal
sessions scoped to projects. Implements the session-facing requirements of
REQ-010 (REQ-010.6–010.8, REQ-010.17).

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Stories Covered
- US-001: Create named terminal sessions per project
- US-002: Resume existing terminal sessions
- US-003: List terminal sessions by project

## Affected Modules
- `packages/pz/pz.sh` — new CLI script
- `packages/pz/default.nix` — Nix package definition
- `modules/terminal/projects.nix` — new home-manager module (shared with REQ-012)
- `modules/terminal/default.nix` — import `projects.nix`
- `modules/terminal/shell.nix` — Zellij configuration (read-only dependency)
- `flake.nix` — add `pz` to overlay

## Data Models

### Project
Discovered from the filesystem per REQ-010.1–010.4.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| slug | string | Directory name under `{notes_path}/projects/` | Lowercase, hyphen-separated (REQ-010.2) |
| path | string | Absolute path to project directory | `{notes_path}/projects/{slug}` |
| readme | string | Path to README.md | `{path}/README.md` |
| repos | list[string] | YAML frontmatter `repos:` in README.md | Optional (REQ-010.11) |

### Session
Derived from Zellij session state.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| name | string | Zellij session name | Format: `{project-slug}` or `{project-slug}-{session-slug}` |
| project_slug | string | Extracted from session name | Project identifier |
| session_slug | string | Extracted from session name | Purpose identifier (default: `main`) |
| status | enum | Zellij | `attached`, `detached`, or `exited` |

## CLI Contract

### `pz <project-slug> [<session-slug>]`

Create or attach to a named project Zellij session.

**Arguments**:
- `<project-slug>` — the project to open (required)
- `<session-slug>` — purpose identifier for the session (optional; default: `main`)

Session names use the format `{project-slug}` for the default session and
`{project-slug}-{session-slug}` for named sub-sessions, allowing multiple
named sessions per project. This naming scheme is also adopted by `agentctl` (REQ-012.3)
to ensure consistent session identification across tools.

**Behavior**:
1. The command MUST validate that `{notes_path}/projects/{project-slug}/README.md` exists
2. If a Zellij session named `{project-slug}` exists for the default session or `{project-slug}-{session-slug}` exists for a named session, the command MUST attach to it
3. If no session exists, the command MUST create a new Zellij session using that same naming rule
4. The session MUST start with the working directory set to `{notes_path}/projects/{project-slug}`
5. The command MUST export environment variables per REQ-010.9 before attaching

**Exit codes**:
- `0` — session attached or created successfully
- `1` — project slug not found (no matching directory)
- `2` — Zellij not available or session creation failed

**Error output**:
- Missing project: `error: project '{project-slug}' not found at {notes_path}/projects/{project-slug}`
- Missing README: `error: project '{project-slug}' has no README.md`

### `pz list [--project <project-slug>]`

List sessions filtered by project.

**Behavior**:
1. The command MUST discover valid project slugs from `{notes_path}/projects/*/README.md`
2. The command MUST list only Zellij sessions whose names exactly match a discovered project slug or begin with `{project-slug}-`
3. When `--project <project-slug>` is provided, the command MUST show only sessions whose discovered project slug matches that value
4. Sessions whose names do not include a discovered project slug in that format MUST be excluded
5. Legacy `obs-*` sessions MUST be ignored
6. The command MUST exit with code `0` even when no sessions are found (empty list)

**Output format** (stdout, tab-separated):
```
PROJECT     SESSION     STATUS
backend     main        attached
backend     review      detached
frontend    main        detached
```

### `pz kill <project-slug> [<session-slug>]`

Destroy a project session.

**Behavior**:
1. The command MUST kill the Zellij session named `{project-slug}` for the default session or `{project-slug}-{session-slug}` for a named session
2. When `<session-slug>` is omitted, the command MUST kill the default session and all named sessions matching `{project-slug}-*`
3. If the session does not exist, the command MUST print a warning and exit `0`
4. The command MUST NOT kill sessions that do not match the project session naming rules

## Behavioral Requirements

### Session Lifecycle

1. Sessions MUST persist across terminal disconnections (Zellij default behavior).
2. Re-running `pz {project-slug} [session-slug]` on an existing session MUST attach, not create a duplicate.
3. Session names MUST use the format `{project-slug}` for the default session and `{project-slug}-{session-slug}` for named sub-sessions. This naming scheme is shared with `agentctl --project <project> <session-slug>` to ensure consistent session identification across tools.

### Project Discovery

5. Projects MUST be discovered by scanning `{notes_path}/projects/*/README.md` (REQ-010.4).
6. Directories matching `_archive/` or starting with `_` MUST be excluded (REQ-010.3).
7. Project slugs MUST be lowercase, hyphen-separated strings (REQ-010.2).
8. The `notes_path` MUST be derived from `keystone.notes.path` (REQ-010.4).

### Environment Variables

9. Inside a `pz` session, the following environment variables MUST be set (REQ-010.9):
   - `PROJECT_NAME` — the project slug
   - `PROJECT_PATH` — absolute path to the project directory
   - `PROJECT_README` — path to the project's `README.md`
   - `VAULT_ROOT` — the notes repo root (`keystone.notes.path`)
   - `CLAUDE_CONFIG_DIR` — project-scoped Claude configuration directory (`{notes_path}/.claude-projects/{project-slug}/`)
   - `AGENTS_MD` — path to the aggregated agents context file for the project (REQ-010.12)
10. Environment variables MUST be available to all processes spawned within the session.

### Shell Completion

11. The `pz` command MUST provide tab completion for project slugs in Zsh (REQ-010.17).
12. The `pz` command SHOULD provide tab completion for project slugs in Bash (REQ-010.17).
13. Completions MUST be generated dynamically by scanning the projects directory at runtime.

## Edge Cases

- **Stale sessions**: If a Zellij session exists but the project directory has been deleted or is no longer registered under `{notes_path}/projects/*/README.md`, `pz list` MUST exclude the session. `pz <project-slug>` for a deleted project MUST fail with exit code `1`.
- **Concurrent attach**: If a session is already attached in another terminal, `pz <project-slug> <session-slug>` MUST attach to the same session (Zellij supports multiple clients per session).
- **Empty projects directory**: If no projects exist, `pz list` MUST output an empty table with headers only. `pz <project-slug>` MUST fail with exit code `1`.
- **Invalid slug characters**: `pz` MUST reject slugs containing characters other than lowercase alphanumeric and hyphens.
- **Legacy prefixed sessions**: `obs-*` sessions are outside the contract and MUST be ignored by `pz list` and `pz` attach behavior.
- **Zellij not running**: If Zellij server is not running, `pz` MUST start a new server automatically (Zellij default behavior).

## Home Manager Module Options

The `keystone.projects` module provides configuration consumed by `pz`:

```nix
keystone.projects = {
  enable = mkEnableOption "Project session management";
};
```

When `keystone.projects.enable` is true, `keystone.notes.enable` MUST also be true (REQ-010.5).
