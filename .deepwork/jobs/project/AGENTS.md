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

### 2026-03-30: Press releases must be stored in ~/notes before creating the issue

- **Source**: User instruction — all project press releases must first be stored in `~/notes` following the zk tagging standard
- **Issue**: The workflow created an issue and a local `.deepwork/tmp/` artifact but did not create a durable zk note in the user's notes notebook. Press releases are meaningful project records that should be discoverable alongside other project notes.
- **Resolution**: Added step 11 to `steps/write_press_release.md` — create a permanent note in `~/notes/notes/` before creating the issue. The note must include `project/<slug>`, `source/agent`, `source/deepwork` tags, and `repo_ref` frontmatter. After issue creation, the note must be updated with `issue_ref`. If a project hub exists in `~/notes/index/`, the note must be linked from it. Updated `job.yml` common_job_info to mandate the zk note step.
- **Reference**: `steps/write_press_release.md` steps 11–12 and Output Format, `job.yml` common_job_info press release conventions, `process.notes`, `tool.zk-notes`

### 2026-03-30: Press release tmp artifacts must use unique filenames

- **Source**: User feedback after running `project/press_release` for Keystone Project Agent
- **Issue**: The workflow correctly staged local artifacts under `.deepwork/tmp/`, but it still used generic basenames like `press_release.mdx` and `press_release_issue_url.md`. Re-running the workflow for another project or another press release can overwrite earlier artifacts and confuse traceability.
- **Resolution**: Updated `steps/write_press_release.md` and `job.yml` to require unique `.deepwork/tmp/` filenames derived from the project slug or headline slug, such as `<slug>-press-release.mdx` and `<slug>-press-release-issue-url.md`. Added a review criterion to reject shared generic basenames.
- **Reference**: `steps/write_press_release.md` final check, staging instructions, output format, and `job.yml` press_release review criteria

### 2026-03-30: Press release issues should quote the release text

- **Source**: User feedback after reviewing the published press release issue
- **Issue**: The workflow created the issue with the press release as plain body text. The user wants the actual user-facing press release to appear as quoted published copy, so readers can clearly distinguish the release from any issue wrapper text.
- **Resolution**: Updated `steps/write_press_release.md` and `job.yml` so the issue body must render the press release inside a Markdown blockquote (`>` on each release line). Added review criteria to reject plain pasted issue bodies.
- **Reference**: `steps/write_press_release.md` publish step and quality criteria, `job.yml` press_release issue review

### 2026-03-30: The `>` blockquote in a press release issue must be audience-facing narrative — no internal labels

- **Source**: User feedback after reviewing the published press release for Keystone Project Agent (#260)
- **Issue**: The press release body used `**Current state**` / `**Why this**` / `**How**` / `**What**` as visible labels inside the `>` blockquote. These are internal draft scaffolding for the agent's organizing process — they are not meant to appear in the published, audience-facing copy. The `>` blockquote is what readers and stakeholders see; it must be clean narrative prose.
- **Resolution**: Updated `steps/write_press_release.md` to clarify:
  1. The `current state → why → how → what` structure is an internal draft device only — labels must NOT appear in the published press release
  2. The `>` blockquote is a single, self-contained section of the issue body — it contains only audience-facing prose (headline, narrative paragraphs, ASCII mockup if applicable, CTA)
  3. Other issue content (FAQ, technical notes) goes outside the `>` blockquote, after the `---` separator
  4. Updated the Output Format template to show narrative paragraphs instead of labeled sections inside the blockquote
  5. Updated the Quality Criteria to require the blockquote be free of internal labels
- **Reference**: `steps/write_press_release.md` step 5, step 12, Output Format, and Quality Criteria

## Editing Guidelines

1. **Use workflows** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks
