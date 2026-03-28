# Portfolio Job

## Standard Workflow: Monthly Portfolio Review

The canonical way to run a portfolio review is `portfolio/review`. It:

1. **Discovers** all active projects from the notes repo (`PROJECTS.yaml` or `projects/README.md`)
2. **Reviews** each project in parallel (milestones, activity, blockers) via `review_one` sub-workflows
3. **Synthesizes** a portfolio health report with Eisenhower matrix and recommendations
4. **Opens a PR** in the notes repo at `projects/portfolio/reviews/YYYY-MM.md`

The human reviews the PR, comments, and merges it in. The report is permanent record in the notes repo.

### Running it

```bash
# In Claude Code:
/deepwork portfolio/review
# notes_path input: ~/notes
```

### PR convention

- Branch: `portfolio-review/YYYY-MM`
- Target: `main` in the notes repo
- Platform: notes repo is on **Forgejo** (`git.ncrmro.com/luce/notes`) — use `fj pr create`
- The human reviews and merges manually — no auto-merge on this repo

### Frequency

Run monthly or when a major project status change warrants a fresh snapshot.

---

## setup_gaps Workflow

Run `portfolio/setup_gaps` when the review identifies projects with no active milestones (⚪ Deferred).
It inspects each gap project's repo state and interactively proposes retroactive milestone creation.

---

## Job Management

This folder and its subfolders are managed using `deepwork_jobs` workflows.

## Recommended Workflows

- `deepwork_jobs/new_job` - Full lifecycle: define → implement → test → iterate
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
