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

### 2026-03-21: Press releases must create an issue and output the full URL

- **Source**: User feedback after running `project/press_release` workflow for Keystone perception layer
- **Issue**: The workflow produced only a local `.mdx` file but did not create an issue or provide a URL. Downstream workflows (e.g., `milestone/setup`) need a stable, linkable reference to the press release for traceability.
- **Resolution**: Three changes applied:
  1. Added step 10 to `steps/write_press_release.md` — create an issue on the project repo with the press release content and record the full URL
  2. Added `press_release_issue_url.md` as a required output in `job.yml` with its own quality review
  3. Updated `common_job_info` to mandate issue creation and URL output
- **Reference**: `steps/write_press_release.md` step 10, `job.yml` write_press_release outputs and reviews

### 2026-03-25: Stage press release workflow artifacts under `.deepwork/tmp/`

- **Source**: User feedback after running `project/press_release` for `keystone.development`
- **Issue**: The workflow instructions were clear about the published issue, but ambiguous about the local output path. That allowed the run to use ad hoc `/tmp/...` files even though this repo's DeepWork convention is to keep transient workflow artifacts under `.deepwork/tmp/`.
- **Resolution**: Updated `steps/write_press_release.md` and `job.yml` so the workflow now stages `press_release.mdx` and `press_release_issue_url.md` under `.deepwork/tmp/`. The instructions now distinguish transient local artifacts from canonical publication: the GitHub/Forgejo issue is always published, and `posts/press_releases/` is only used when the project explicitly stores press releases in-repo.
- **Reference**: `steps/write_press_release.md` output format and publication steps, `job.yml` common_job_info

## Editing Guidelines

1. **Use workflows** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks
