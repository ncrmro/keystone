# Job Management

This folder and its subfolders are managed using `deepwork_jobs` workflows.

## Recommended Workflows

- `deepwork_jobs/new_job` - Full lifecycle: define -> implement -> test -> iterate
- `deepwork_jobs/learn` - Improve instructions based on execution learnings
- `deepwork_jobs/repair` - Clean up and migrate from prior DeepWork versions

## Directory Structure

```
.
├── .deepreview        # Review rules for the job itself using Deepwork Reviews
├── AGENTS.md          # This file - project context and guidance
├── job.yml            # Job specification (created by define step)
├── steps/             # Step instruction files (created by implement step)
│   └── *.md           # One file per step
├── hooks/             # Custom validation scripts and prompts
│   └── *.md|*.sh      # Hook files referenced in job.yml
├── scripts/           # Reusable scripts and utilities created during job execution
│   └── *.sh|*.py      # Helper scripts referenced in step instructions
└── templates/         # Example file formats and templates
    └── *.md|*.yml     # Templates referenced in step instructions
```

## Editing Guidelines

1. **Use workflows** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks

## Job-Specific Context

### sweng

#### Convention Dependencies

This job integrates several keystone conventions. Steps reference them by name:
- `process.feature-delivery` — Branch naming, worktree paths, draft PR, squash merge
- `process.version-control` — Conventional commits, SSH cloning, `.repos/` layout
- `process.continuous-integration` — CI gating, log download, error search
- `process.pull-request` — PR body format (Goal, Changes, Demo, Tasks)
- `process.task-tracking` — TASKS.yaml schema and lifecycle
- `process.copilot-agent` — Copilot review on GitHub PRs
- `process.project-board` — Issue board transitions (In Progress, In Review, Done)
- `code.delivery` — End-to-end delivery lifecycle with board integration

See `.agents/conventions/` for full convention docs.

#### Project Board Integration

Every step that changes issue state MUST also update the project board column:
- **plan**: Issue comment + move to "In Progress" when branch created
- **review**: Move to "In Review" when PR marked ready for review
- **review (failure)**: Move back to "Backlog" when max fix attempts exceeded
- **postflight**: Move to "Done" on Forgejo (GitHub auto-handles via built-in workflows)

GitHub project boards require looking up field/option IDs via `gh project field-list`
before setting statuses — these IDs are project-specific and MUST NOT be hardcoded.

Forgejo has no project board API — use `forgejo-project` CLI for all board operations.

#### Platform Detection

Platform is inferred from git remote URL at runtime:
- `*github.com*` -> github -> use `gh` CLI
- `*git.ncrmro.com*` -> forgejo -> use `fj` CLI + `forgejo-project` for boards

## Last Updated

- Date: 2026-03-19
- From conversation about: Adding project board integration (issue comments and board column transitions) to all sweng steps
