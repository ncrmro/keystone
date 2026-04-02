# REQ-026: Project desktop menu

Requirements for the project-aware desktop menu that bridges the terminal-first
`pz` workflow and the Walker desktop launcher. This spec consolidates the
desktop-facing project menu behavior that was previously split across REQ-002,
REQ-010, and REQ-011.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Scope

This spec defines the contract for:

- the root project list exposed in Walker or the Keystone desktop menu,
- the project actions menu opened from a selected project,
- delegation to `pz` for project discovery, session state, metadata, and
  session lifecycle, and
- parity between terminal project workflows and desktop project workflows.

This spec does not redefine the core `pz` session lifecycle contract from
REQ-011, or general desktop menu behavior from REQ-002.

## Stories covered

- US-026-001: Open a project from the desktop into the default `pz` session
- US-026-002: Create a new named project session from the desktop
- US-026-003: Re-open an existing named project session from the desktop
- US-026-004: Inspect project mission, milestone, and session context before
  launching

## Normative dependencies

- REQ-002: Keystone Desktop
- REQ-009: Notes
- REQ-010: Projects
- REQ-011: Project Sessions (`pz` CLI)

## Functional requirements

### Source of truth and delegation (pdm-source-001)

The desktop project menu MUST remain a thin adapter over terminal-first project
tooling.

- **pdm-source-001.1**: The desktop project menu MUST discover projects from
  the same active project hub source used by `pz`.
- **pdm-source-001.2**: The desktop project menu MUST NOT implement an
  independent project registry, session registry, or project metadata store.
- **pdm-source-001.3**: Project discovery, session discovery, project preview
  data, and session launch behavior MUST delegate to `pz` or another
  terminal-first helper that itself delegates to `pz`.
- **pdm-source-001.4**: Desktop behavior for opening, creating, or re-attaching
  project sessions MUST preserve the naming and lifecycle rules defined in
  REQ-011.

### Root project list (pdm-root-001)

The desktop MUST provide a root project list for project-aware launch and
switching.

- **pdm-root-001.1**: The root list MUST show registered active projects from
  the `pz` project registry.
- **pdm-root-001.2**: Each project row MUST identify the project slug.
- **pdm-root-001.3**: Each project row SHOULD show a concise status summary for
  the project, such as whether the default session is running.
- **pdm-root-001.4**: The root list MUST be keyboard accessible.
- **pdm-root-001.5**: In the current Walker `actions_as_menu` design, pressing
  `Enter` on a project row MUST open that project's action menu.
- **pdm-root-001.6**: Selecting a project row MUST NOT immediately switch,
  attach, or launch a terminal before the project action menu is shown.
- **pdm-root-001.7**: The root list SHOULD show project preview information,
  such as mission or milestone context, for the currently selected project when
  the launcher supports previews.

### Project actions menu (pdm-actions-001)

Selecting a project from the root list MUST expose a project-specific action
menu.

- **pdm-actions-001.1**: The project action menu MUST include an explicit
  action to open the default project session.
- **pdm-actions-001.2**: The project action menu MUST include an explicit
  action to create a new named session, even when one or more sessions already
  exist for the project.
- **pdm-actions-001.3**: The project action menu MUST list existing named
  sessions for the selected project when they exist.
- **pdm-actions-001.4**: Existing named sessions in the action menu SHOULD
  display available session status, such as `attached` or `detached`.
- **pdm-actions-001.5**: Existing named sessions in the action menu SHOULD
  display repo or worktree context when that information is available from the
  terminal-side source of truth.
- **pdm-actions-001.6**: If repo or worktree context is not available, the menu
  MUST degrade gracefully and still allow the session to be opened.
- **pdm-actions-001.7**: The action menu MAY include an explicit `Details`
  action for richer project context, but project session actions MUST remain
  accessible even when a separate details view is absent.
- **pdm-actions-001.8**: The project action menu MUST expose the effective target host and allow changing it.
- **pdm-actions-001.9**: The project action menu SHOULD expose interactive provider, model, and fallback model overrides used for project launches.

### Session launch behavior (pdm-open-001)

Desktop session actions MUST preserve terminal-session semantics while
integrating with the active desktop window state.

- **pdm-open-001.1**: Choosing `Open default session` MUST behave as the
  desktop equivalent of `pz <project>`.
- **pdm-open-001.2**: Choosing an existing named session MUST behave as the
  desktop equivalent of `pz <project> <session>`.
- **pdm-open-001.3**: If a matching desktop window already exists for the
  target session, the desktop MUST focus that window instead of launching a new
  terminal.
- **pdm-open-001.4**: If the target session exists without a matching desktop
  window, the desktop MUST open a new terminal attached to that existing
  session.
- **pdm-open-001.5**: If the target session does not yet exist, the desktop
  MUST launch the session through `pz`, preserving `pz` naming and environment
  behavior.
- **pdm-open-001.6**: The desktop MUST support both current `pz` session names
  and legacy `obs-<project>` session names when detecting active sessions for
  focus-or-launch behavior.
- **pdm-open-001.7**: Starting or attaching a project session from the desktop
  menu MUST fully detach the spawned terminal or editor process from the
  Walker or Elephant process tree before the user-facing window starts.
- **pdm-open-001.8**: Restarting `walker.service` or `elephant.service` MUST
  NOT close, interrupt, or invalidate a project window or zellij session that
  was launched from the desktop menu.
- **pdm-open-001.9**: When the effective target host is remote, the desktop MUST launch the project through terminal-first remote transport rather than a desktop-only session registry.

### New named session flow (pdm-new-001)

The desktop MUST support creating named project sessions from the project action
menu.

- **pdm-new-001.1**: Choosing `New named session` MUST open a dedicated input
  flow for the session slug.
- **pdm-new-001.2**: Submitting that flow with a non-empty slug MUST behave as
  the desktop equivalent of `pz <project> <session-slug>`.
- **pdm-new-001.3**: The input flow MAY allow an empty value to target the
  default project session.
- **pdm-new-001.4**: Session slug validation MUST remain aligned with the
  terminal-side `pz` slug rules.

### Information hierarchy and parity (pdm-parity-001)

The desktop menu SHOULD mirror the information hierarchy of the terminal
project workflow.

- **pdm-parity-001.1**: The desktop menu SHOULD surface the same categories of
  project context that `pz` exposes, including mission, milestones, and session
  state.
- **pdm-parity-001.2**: When richer project details are shown, they MUST be
  sourced from the notes project hub or other terminal-side sources already used
  by `pz`.
- **pdm-parity-001.3**: Missing notes metadata, milestone data, repo data, or
  worktree data MUST NOT block the user from opening the default session, a new
  named session, or an existing named session.

### Performance and machine-readable state (pdm-perf-001)

The desktop project menu MUST stay responsive.

- **pdm-perf-001.1**: The desktop project menu MUST prefer bulk machine-readable
  exports from `pz` over per-project shell-outs.
- **pdm-perf-001.2**: The desktop project menu MUST avoid N+1 project metadata
  lookups during root menu population.
- **pdm-perf-001.3**: The desktop project menu MAY use short-lived runtime
  caching for menu payloads, provided the cache remains a derived view of the
  terminal-side source of truth.
- **pdm-perf-001.4**: Cache misses, cache expiry, or cache invalidation MUST
  degrade gracefully without preventing menu use.

## Acceptance criteria

1. Opening the desktop project menu shows active project slugs discovered from
   the same source used by `pz`.
2. Pressing `Enter` on a project row opens a project action menu rather than
   immediately launching a session.
3. The project action menu contains `Open default session` and `New named
   session`.
4. If named sessions already exist for the project, they appear in the same
   action menu.
5. Choosing `Open default session` behaves like `pz <project>`, including
   focus-or-launch behavior for an existing desktop window.
6. Choosing `New named session`, entering a slug, and confirming behaves like
   `pz <project> <session-slug>`.
7. The root menu uses a bulk `pz` export path rather than one per-project
   metadata call.
8. Restarting `walker.service` after opening a project session does not close
   the launched terminal window or its backing zellij session.

## Affected modules

- `packages/pz/pz.sh`
- `modules/desktop/home/scripts/keystone-project-menu.sh`
- `modules/desktop/home/scripts/keystone-context-switch.sh`
- `modules/desktop/home/components/keystone-projects.lua`
- `modules/desktop/home/components/keystone-project-details.lua`
- `modules/desktop/home/components/keystone-project-session.lua`
- `modules/desktop/home/components/launcher.nix`
