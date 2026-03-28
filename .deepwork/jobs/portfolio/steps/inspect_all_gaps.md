# Inspect All Gap Projects

## Objective

Launch the `inspect_one_gap` sub-workflow for each gap project in parallel via sub-agents,
then collect all proposals into a single combined output file.

## Task

1. **Parse the gap project list**

   Read `gap_projects.md` and extract the list of gap projects. For each project, note:
   - `project_slug` — the project identifier
   - `project_repos` — comma-separated `owner/repo:platform` strings
   - `notes_path` — the notes repo path (same as this step's runtime context)

2. **Launch parallel sub-agents**

   For each gap project, launch an independent sub-agent using the Task tool to run
   the `inspect_one_gap` sub-workflow. Since each project is independent, launch
   all sub-agents concurrently.

   Each sub-agent should:
   - Start the `portfolio/inspect_one_gap` workflow
   - Pass `project_slug`, `project_repos`, and `notes_path` as inputs to the
     `inspect_repo` step
   - Run through both steps (`inspect_repo` → `write_proposal`)
   - Return the path to the completed `milestone_proposal.md`

3. **Wait for all sub-agents to complete**

   Monitor all launched sub-agents. Wait for every one to finish before proceeding.
   If any sub-agent fails, note the failure and continue — don't block on a single
   project's failure.

4. **Collect and combine proposals**

   Read each `milestone_proposal.md` output from the sub-agent runs and combine them
   into a single `gap_proposals.md` file. Use the project slug as a section header.

   Preserve the full proposal content from each sub-agent — do not summarize or
   truncate. The `apply_milestones` step needs the full detail to create milestones.

## Output Format

### gap_proposals.md

```markdown
# Gap Project Milestone Proposals — [Date]

[N] projects reviewed. [N] proposals generated.

---

## [Project Slug]

[Full content of milestone_proposal.md from this project's sub-agent run]

---

## [Project Slug]

[Full content of milestone_proposal.md from this project's sub-agent run]
```

## Notes

- If the gap project list is empty (no projects with zero milestones), write a brief
  `gap_proposals.md` noting that no gap projects were found. This is a success state.
- If a sub-agent run fails for a project, include a section for that project with a
  failure note and the error message so the `apply_milestones` step can skip it.
