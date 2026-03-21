# Job Management

This folder and its subfolders are managed using `deepwork_jobs` workflows.

## Recommended Workflows

- `deepwork_jobs/new_job` - Full lifecycle: define -> implement -> test -> iterate
- `deepwork_jobs/learn` - Improve instructions based on execution learnings
- `deepwork_jobs/repair` - Clean up and migrate from prior DeepWork versions

## Directory Structure

```
.
├── AGENTS.md          # This file - project context and guidance
├── job.yml            # Job specification
└── steps/             # Step instruction files
    ├── scaffold.md
    ├── seed.md
    ├── verify_init.md
    ├── audit.md
    ├── plan_migration.md
    ├── migrate.md
    ├── verify_doctor.md
    ├── review_inbox.md
    ├── promote.md
    ├── link_notes.md
    └── sync.md
```

## Editing Guidelines

1. **Use workflows** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks

## Learnings

(None yet — this is a new job.)
