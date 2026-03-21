# Job Management

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

## Learning History

### 2026-03-20: Press release tone — succinct, no quotes, no city
- **Source**: User feedback after running `project/press_release` workflow
- **Issue**: Press releases were too verbose with marketing-style prose. They included fictional customer quotes (fabricated testimonials) and city datelines that the user didn't want. The tone should be direct and informational.
- **Resolution**: Three changes applied to `steps/write_press_release.md` and `steps/gather_context.md`:
  1. Removed customer quote requirement from both steps and the context brief template
  2. Removed city dateline from the template — only include if user explicitly requests
  3. Restructured body to a succinct flow: current state → why this → how → what. Word count reduced from 400-600 to 300-500.
- **Reference**: `steps/write_press_release.md` (template and quality criteria), `steps/gather_context.md` (removed quote direction), `job.yml` common_job_info and write_press_release reviews

### 2026-03-20: Press releases must include ASCII art mockups
- **Source**: User feedback on Desktop Context System press release (#174) — lacked a visual showing the context switcher UI
- **Issue**: Press releases for products with a UI shipped without showing what the product looks like in use. An ASCII art mockup grounds the reader and makes the promise concrete.
- **Resolution**: Added ASCII art mockup as a required step in `steps/write_press_release.md` (step 6). Added mockup section to the template. Added "ASCII Art Mockup" quality criterion to `job.yml` write_press_release reviews. Products without a UI may omit the mockup.
- **Reference**: `steps/write_press_release.md` step 6 and template, `job.yml` write_press_release reviews

## Editing Guidelines

1. **Use workflows** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks
