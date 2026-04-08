---
title: Projects and pz
description: Project hubs, repo roots, worktrees, and pz-based terminal sessions
---

# Projects and pz

Keystone treats the project hub note as the source of truth for an active
project. `pz` uses those hub notes to discover projects and launch Zellij
sessions in the right context.

This page covers the current user workflow for project notes, repo roots,
worktrees, and `pz`.


## Source of truth

Each active project should have one hub note under `index/` in the notebook at
`~/notes`.

The hub note should include:

- `project: "<slug>"`
- `repos:` with full remote URLs when the project uses one or more repos
- tags such as `index`, `project/<slug>`, and `status/active`

Example:

```yaml
---
project: "keystone"
repos:
  - "git@github.com:ncrmro/keystone.git"
  - "ssh://forgejo@git.ncrmro.com:2222/drago/notes.git"
tags: [index, project/keystone, status/active]
---
```

`pz` discovers projects from these active hub notes. If a project does not have
an active hub note, `pz` will not treat it as a valid project session target.

## Repo and worktree paths

Keystone uses two checkout roots:

- keystone-managed repos: `~/.keystone/repos/{owner}/{repo}`
- non-keystone project repos: `$HOME/code/{owner}/{repo}`

Implementation work should happen in external worktrees:

- worktrees: `$HOME/.worktrees/{owner}/{repo}/{branch}`

Keystone exports these roots for humans, agents, and non-`ks` tooling:

- `NOTES_DIR`
- `CODE_DIR`
- `WORKTREE_DIR`

Home Manager ensures those directories exist automatically.

## pz basics

`pz` is the project session entry point for Zellij.

Current commands:

```bash
pz
pz list
pz list --project keystone
pz keystone
pz keystone review
pz keystone --layout dev
```

Behavior:

- `pz` with no arguments defaults to `pz list`
- `pz list` shows active Zellij sessions for registered project hubs
- `pz <project>` creates or attaches to the main session for that project
- `pz <project> <session>` creates or attaches to a named sub-session
- `--layout <name>` applies when creating a new session

Current built-in layout names:

- `dev`
- `ops`
- `write`

## Workflow

The normal Keystone project workflow is:

1. Keep the notes repo current so the active hub notes reflect reality.
2. Open the project session with `pz`.
3. Use Zellij to keep the session persistent and organized.
4. Use Helix for editing and Lazygit for git operations inside that session.

Typical flow:

```bash
systemctl --user status keystone-notes-sync
pz keystone
hx .
lazygit
```

### Zellij

`pz` is the preferred entry point because it creates or attaches to the right
Zellij session with project-aware environment variables already set.

Use plain Zellij concepts inside the project session:

- tabs for contexts such as coding, logs, and review,
- panes for side-by-side work,
- detach and reattach instead of rebuilding your workspace.

Examples:

```bash
pz keystone
pz keystone review
zellij list-sessions
```

### Session management

There are three ways to find and switch between Zellij sessions:

| Method | Context | What it shows |
|--------|---------|---------------|
| `pz` / `pz list` | Terminal | Project sessions in a tree view |
| `zs` (`zesh connect`) | Terminal | Interactive fzf picker across all sessions with zoxide ranking |
| `$mod+D` | Desktop | Walker fuzzy-search menu showing all active sessions |

For scripting and tooling, `pz all-sessions-json` outputs every active Zellij
session as JSON, annotated with project metadata where available:

```bash
pz all-sessions-json | jq '.[] | select(.status == "attached")'
```

### Helix

Use Helix as the default editor for code, notes, and docs:

```bash
hx .
hx ~/notes/index
```

Helix works especially well in Keystone because the terminal module already
ships the editor, language tooling, and zk-aware workflow defaults.

### Lazygit

Use Lazygit for fast review and commit workflows without leaving the session:

```bash
lazygit
```

That is the recommended git UI when iterating inside a `pz` session.

## Projects, notes, and review

Projects in Keystone are note-backed, not directory-backed.

The active hub note in `~/notes/index/` is what makes a project discoverable to:

- `pz`,
- project-aware agent workflows, and
- desktop project navigation.

Keep `~/notes` current before assuming the project list is correct. For humans,
that usually means letting `keystone-notes-sync` run or checking it directly:

```bash
systemctl --user status keystone-notes-sync
journalctl --user -u keystone-notes-sync -n 20
```

When you need to review or refresh the hub note itself:

```bash
cd ~/notes
zk edit -i
```

Or refresh the hub through the workflow command:

```text
/notes.project
```

Use [Notes](../notes.md) for the canonical hub-note structure and note flow.

## Desktop session picker with Walker

`$mod+D` opens a Walker menu showing all active Zellij sessions with fuzzy
search. Select a session to attach, or choose "New session" to browse projects
and create one through the project picker.

The sessions menu shows both project-backed sessions (with project metadata)
and ad-hoc sessions (with their raw Zellij session name).

Relevant commands and scripts:

- `keystone-context-switch` opens the Walker session picker
- `keystone-project-menu` delegates session data and launch behavior to `pz`
- `pz` remains the source of truth for sessions and project metadata

The practical effect is:

- `pz all-sessions-json` enumerates every active Zellij session,
- project-backed sessions get project icons and route through the full
  project launch flow (host targeting, layouts),
- ad-hoc sessions attach directly via `zellij attach`,
- Walker provides native fuzzy matching across all entries.

The project picker remains accessible via the "New session" entry and through
the `$mod+Escape` main menu.

## Session naming

Session names are deterministic:

- `pz keystone` uses session `keystone`
- `pz keystone review` uses session `keystone-review`

When `pz list` shows sessions, the base project session appears as `main`.

## Session environment

When `pz` creates a new session, it exports:

- `PROJECT_NAME`
- `PROJECT_PATH`
- `PROJECT_README`
- `VAULT_ROOT`

Today, `PROJECT_PATH` and `PROJECT_README` preserve a legacy contract:

- if `~/notes/projects/<slug>/README.md` exists, `pz` uses that legacy path
- otherwise it falls back to the notes notebook root and the project hub note

That fallback is what allows notes-backed projects to work even when there is
no legacy `~/notes/projects/<slug>/` tree.

## Agent handoff from a project session

From inside a `pz` session, you can run `agentctl` in the current project
context:

```bash
pz keystone
pz agent reviewer run
```

`pz agent ...` requires an existing project session because it reads the active
`PROJECT_NAME` from the session environment.

## Worktrees and future repo-scoped sessions

The current `pz` behavior is project-first. It validates project slugs from
active hub notes and opens a session for the project.

The documented direction is broader:

- hub notes remain the source of truth for project-to-repo relationships
- repo roots resolve from the declared remote URLs
- repo-scoped sessions should be able to target external worktrees under
  `$HOME/.worktrees/{owner}/{repo}/{branch}`

That worktree integration is defined by convention, but the repo/worktree
session UX is still evolving. Until that lands, use `pz` for project sessions
and standard `git worktree` commands for branch worktrees.

## Related docs

- [Notes](../notes.md)
- [Terminal module](terminal.md)
- [`process.git-repos`](../../conventions/process.git-repos.md)
