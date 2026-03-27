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

<!-- TODO: Add terminal screenshots for `pz list`, `pz keystone`, and a repo worktree session once repo/worktree launch support lands. -->
<!-- TODO: Add one screenshot per stable Zellij layout after the layout set and visual structure stop changing. -->

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
- [`process.git-worktrees`](../../conventions/process.git-worktrees.md)
