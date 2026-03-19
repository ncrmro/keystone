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
| name | string | Zellij session name | Format: `{prefix}-{slug}` |
| slug | string | Extracted from session name | Everything after `{prefix}-` |
| status | enum | Zellij | `attached` or `detached` |
| created | timestamp | Zellij session metadata | ISO 8601 |

## CLI Contract

### `pz <slug>`

Create or attach to a project Zellij session.

**Behavior**:
1. The command MUST validate that `{notes_path}/projects/{slug}/README.md` exists
2. If a Zellij session named `{prefix}-{slug}` exists, the command MUST attach to it
3. If no session exists, the command MUST create a new Zellij session named `{prefix}-{slug}`
4. The session MUST start with the working directory set to `{notes_path}/projects/{slug}`
5. The command MUST export environment variables per REQ-010.9 before attaching

**Exit codes**:
- `0` — session attached or created successfully
- `1` — project slug not found (no matching directory)
- `2` — Zellij not available or session creation failed

**Error output**:
- Missing project: `error: project '{slug}' not found at {notes_path}/projects/{slug}`
- Missing README: `error: project '{slug}' has no README.md`

### `pz list [--project <slug>]`

List sessions filtered by project.

**Behavior**:
1. The command MUST list all Zellij sessions whose names start with `{prefix}-`
2. When `--project <slug>` is provided, the command MUST show only sessions matching `{prefix}-{slug}`
3. Output MUST include: session slug, status (attached/detached), and creation time
4. Sessions from other prefixes (e.g., manual Zellij sessions) MUST be excluded
5. The command MUST exit with code `0` even when no sessions are found (empty list)

**Output format** (stdout, tab-separated):
```
SLUG        STATUS      CREATED
backend     attached    2026-03-18T10:30:00
frontend    detached    2026-03-17T14:22:00
```

### `pz kill <slug>`

Destroy a project session.

**Behavior**:
1. The command MUST kill the Zellij session named `{prefix}-{slug}`
2. If the session does not exist, the command MUST print a warning and exit `0`
3. The command MUST NOT kill sessions that don't match the `{prefix}-` pattern

## Behavioral Requirements

### Session Lifecycle

1. Sessions MUST persist across terminal disconnections (Zellij default behavior).
2. Re-running `pz {slug}` on an existing session MUST attach, not create a duplicate.
3. The session prefix MUST be configurable via `keystone.projects.sessionPrefix` (default: `obs`, per REQ-010.7).
4. Session names MUST use the format `{prefix}-{slug}` with no additional separators.

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
10. Environment variables MUST be available to all processes spawned within the session.

### Shell Completion

11. The `pz` command MUST provide tab completion for project slugs in Zsh (REQ-010.17).
12. The `pz` command SHOULD provide tab completion for project slugs in Bash (REQ-010.17).
13. Completions MUST be generated dynamically by scanning the projects directory at runtime.

## Edge Cases

- **Stale sessions**: If a Zellij session exists but the project directory has been deleted, `pz list` MUST still show the session (it's a valid Zellij session). `pz <slug>` for a deleted project MUST fail with exit code `1`.
- **Concurrent attach**: If a session is already attached in another terminal, `pz {slug}` MUST attach to the same session (Zellij supports multiple clients per session).
- **Empty projects directory**: If no projects exist, `pz list` MUST output an empty table with headers only. `pz <slug>` MUST fail with exit code `1`.
- **Invalid slug characters**: `pz` MUST reject slugs containing characters other than lowercase alphanumeric and hyphens.
- **Zellij not running**: If Zellij server is not running, `pz` MUST start a new server automatically (Zellij default behavior).

## Home Manager Module Options

The `keystone.projects` module provides configuration consumed by `pz`:

```nix
keystone.projects = {
  enable = mkEnableOption "Project session management";
  sessionPrefix = mkOption {
    type = types.str;
    default = "obs";
    description = "Prefix for Zellij session names";
  };
};
```

When `keystone.projects.enable` is true, `keystone.notes.enable` MUST also be true (REQ-010.5).
