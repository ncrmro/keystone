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

Desktop menu behavior that consumes this session model is specified in
REQ-026.

## Affected Modules

- `packages/pz/pz.sh` — new CLI script
- `packages/pz/default.nix` — Nix package definition
- `modules/terminal/projects.nix` — new home-manager module (shared with REQ-012)
- `modules/terminal/default.nix` — import `projects.nix`
- `modules/terminal/shell.nix` — Zellij configuration (read-only dependency)
- `flake.nix` — add `pz` to overlay

## Data Models

### Project

Discovered from active hub notes via zk per REQ-010.1–010.4.

| Field    | Type         | Source                            | Notes                                                  |
| -------- | ------------ | --------------------------------- | ------------------------------------------------------ |
| slug     | string       | Hub note frontmatter/tag          | Lowercase, hyphen-separated (REQ-010.2)                |
| hub_path | string       | zk note path                      | Active `index/` hub note                               |
| path     | string       | Notes root or legacy project dir  | Session fallback cwd when no repo/worktree is selected |
| readme   | string       | Hub note or legacy project README | Project context file                                   |
| repos    | list[string] | Hub note metadata                 | Full remote URLs from `repos:`                         |

### Session

Derived from Zellij session state.

| Field        | Type   | Source                      | Notes                                                       |
| ------------ | ------ | --------------------------- | ----------------------------------------------------------- |
| name         | string | Zellij session name         | Format: `{project-slug}` or `{project-slug}-{session-slug}` |
| project_slug | string | Extracted from session name | Project identifier                                          |
| session_slug | string | Extracted from session name | Purpose identifier (default: `main`)                        |
| status       | enum   | Zellij                      | `attached`, `detached`, or `exited`                         |

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

1. The command MUST validate that `{project-slug}` is discoverable from an active hub note via `zk --notebook-dir {notes_path} list index/ --tag "status/active" --format json`
2. If a Zellij session named `{project-slug}` exists for the default session or `{project-slug}-{session-slug}` exists for a named session, the command MUST attach to it
3. If no session exists, the command MUST create a new Zellij session using that same naming rule
4. The session MUST start with the working directory set to `{notes_path}/projects/{project-slug}` when that legacy directory exists
5. The command MUST export environment variables per REQ-010.9 before attaching

### `pz <project-slug> [<session-slug>] --repo <owner/repo> [--worktree <branch>]`

Open a project session rooted at a specific repo or repo worktree.

**Arguments**:

- `--repo <owner/repo>` — normalized repo identity derived from the hub note `repos:` URLs
- `--worktree <branch>` — branch/worktree name to open under that repo

**Behavior**:

1. `pz` MUST normalize the hub note `repos:` URLs into canonical `owner/repo` identities and match `--repo` against that set
2. If `--repo` is omitted and the project declares exactly one repo, `pz` SHOULD use that repo automatically
3. If `--repo` is omitted and the project declares more than one repo, `pz` MUST fail with a clear error listing the available repo identities
4. When the selected repo is keystone-managed, `pz` MUST resolve the repo root to `~/.keystone/repos/{owner}/{repo}/`
5. When the selected repo is not keystone-managed, `pz` MUST resolve the repo root to `$HOME/code/{owner}/{repo}/`
6. When `--worktree <branch>` is provided, `pz` MUST resolve the worktree path as `$HOME/.worktrees/{owner}/{repo}/{branch}/`
7. If the requested worktree does not exist, `pz` SHOULD create it according to `process.git-worktrees`
8. If a repo or worktree is selected, the session working directory MUST be the resolved repo root or worktree path rather than the notes root
9. The command MUST export repo and worktree context environment variables for the session

**Exit codes**:

- `0` — session attached or created successfully
- `1` — project slug not found (no matching directory)
- `2` — Zellij not available or session creation failed

**Error output**:

- Missing project: `error: project '{project-slug}' is not an active project hub in {notes_path}`
- Missing README: `error: project '{project-slug}' has no README.md`

### `pz list [--project <project-slug>]`

List sessions filtered by project.

**Behavior**:

1. The command MUST discover valid project slugs from active hub notes via `zk --notebook-dir {notes_path} list index/ --tag "status/active" --format json`
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

### Workflow Parity and Delegation (pz-parity)

1. **pz-parity-001 (Terminal First):** All project management workflows (discovery, session lifecycle, metadata retrieval) MUST be implemented in the `pz` CLI as the primary interface.
2. **pz-parity-002 (Consistency):** The `pz` CLI MUST ensure that the same set of project-aware metadata and session actions are available to both interactive terminal users and programmatic desktop consumers.
3. **pz-parity-003 (Unified State):** There MUST be a single source of truth for project and session state, managed by `pz` and its dependencies (`zk`, `zellij`). Desktop components MUST NOT maintain independent or parallel state for these entities.
4. **pz-parity-004 (Bulk Provisioning):** The `pz` CLI MUST provide high-performance, machine-readable export formats (e.g., `--json` or `--tsv`) to allow desktop consumers to retrieve all necessary menu state in a single call, preventing N+1 performance bottlenecks.

### Session Lifecycle

1. Sessions MUST persist across terminal disconnections (Zellij default behavior).
2. Re-running `pz {project-slug} [session-slug]` on an existing session MUST attach, not create a duplicate.
3. Session names MUST use the format `{project-slug}` for the default session and `{project-slug}-{session-slug}` for named sub-sessions. This naming scheme is shared with `agentctl --project <project> <session-slug>` to ensure consistent session identification across tools.

### Project Discovery

5. Projects MUST be discovered from active hub notes via `zk --notebook-dir {notes_path} list index/ --tag "status/active" --format json` (REQ-010.4).
6. Archived or inactive hub notes MUST be excluded (REQ-010.3).
7. Project slugs MUST be lowercase, hyphen-separated strings (REQ-010.2).
8. The `notes_path` MUST be derived from `keystone.notes.path` (REQ-010.4).
9. Repo-scoped sessions MUST resolve repo roots from hub note `repos:` URLs using REQ-010.12a and REQ-018.19 through REQ-018.19b.
10. Worktree-scoped sessions MUST resolve paths using `$HOME/.worktrees/{owner}/{repo}/{branch}/` per `process.git-worktrees`.

### Environment Variables

11. Inside a `pz` session, the following environment variables MUST be set (REQ-010.9):

- `PROJECT_NAME` — the project slug
- `PROJECT_PATH` — absolute path to the resolved project cwd
- `PROJECT_README` — path to the hub note or legacy `README.md`
- `VAULT_ROOT` — the notes repo root (`keystone.notes.path`)
- `CLAUDE_CONFIG_DIR` — project-scoped Claude configuration directory (`{notes_path}/.claude-projects/{project-slug}/`)
- `AGENTS_MD` — path to the aggregated agents context file for the project (REQ-010.12)
- `PROJECT_REPO` — normalized `owner/repo` for the selected repo, when one is selected
- `PROJECT_REPO_URL` — original remote URL for the selected repo, when one is selected
- `PROJECT_WORKTREE_BRANCH` — worktree branch name, when one is selected
- `PROJECT_WORKTREE_PATH` — resolved worktree path, when one is selected

12. Environment variables MUST be available to all processes spawned within the session.

### Shell Completion

13. The `pz` command MUST provide tab completion for project slugs in Zsh (REQ-010.17).
14. The `pz` command SHOULD provide tab completion for project slugs in Bash (REQ-010.17).
15. Completions MUST be generated dynamically from active project hub notes at runtime.
16. When `--repo` is in scope, completions SHOULD offer normalized repo identities derived from the selected project's declared repo URLs.

## Edge Cases

- **Stale sessions**: If a Zellij session exists but the project slug is no longer registered by an active hub note, `pz list` MUST exclude the session. `pz <project-slug>` for an inactive or missing project hub MUST fail with exit code `1`.
- **Concurrent attach**: If a session is already attached in another terminal, `pz <project-slug> <session-slug>` MUST attach to the same session (Zellij supports multiple clients per session).
- **Multiple repos**: If a project declares multiple repos and `--repo` is omitted, `pz` MUST error instead of guessing.
- **No active project hubs**: If no active hubs exist, `pz list` MUST output an empty table with headers only. `pz <project-slug>` MUST fail with exit code `1`.
- **Invalid slug characters**: `pz` MUST reject slugs containing characters other than lowercase alphanumeric and hyphens.
- **Legacy prefixed sessions**: `obs-*` sessions are outside the contract and MUST be ignored by `pz list` and `pz` attach behavior.
- **Hub metadata drift**: If an active hub note disagrees between `project: <slug>` frontmatter and `project/<slug>` tag, project discovery MUST fail with a clear error instead of guessing.
- **Missing repo checkout**: If the selected repo root does not exist locally, `pz` MUST fail with a clear error showing the expected path.
- **Missing worktree checkout**: If worktree creation fails, `pz` MUST fail with a clear error and MUST NOT silently fall back to the main checkout.
- **Zellij not running**: If Zellij server is not running, `pz` MUST start a new server automatically (Zellij default behavior).

## Home Manager Module Options

The `keystone.projects` module provides configuration consumed by `pz`:

```nix
keystone.projects = {
  enable = mkEnableOption "Project session management";
};
```

When `keystone.projects.enable` is true, `keystone.notes.enable` MUST also be true (REQ-010.5).
