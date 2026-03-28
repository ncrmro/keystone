# Spec: Task Workflow Definition

## Stories Covered
- US-001: Create `notes.task` DeepWork job definition
- US-002: Implement task note creation step
- US-003: Implement progressive tag enrichment step
- US-004: Implement shared surface commenting step
- US-008: Document the `notes.task` workflow for agents and operators

## Affected Modules
- `.deepwork/jobs/notes/job.yml` — new `task` workflow and step definitions
- `.deepwork/jobs/notes/steps/create_task_note.md` — new step file
- `.deepwork/jobs/notes/steps/enrich_tags.md` — new step file
- `.deepwork/jobs/notes/steps/comment_shared_surface.md` — new step file

## Workflow Structure

### `task` Workflow

```yaml
- name: task
  summary: "Create and maintain a structured task note with progressive artifact linking"
  steps:
    - create_task_note
    - enrich_tags
    - comment_shared_surface
```

### Step Definitions

#### `create_task_note`
- **Inputs**: task context (goal, project slug, notes repo path)
- **Outputs**: `task_note_path.md` — path to the created note
- **Reviews**: note has valid frontmatter, project tag present, status/in-progress set

#### `enrich_tags`
- **Inputs**: `task_note_path.md` from previous step, artifact references to add
- **Outputs**: `enrichment_log.md` — list of tags added
- **Reviews**: tags follow schema from spec 006, status tag is singular

#### `comment_shared_surface`
- **Inputs**: `task_note_path.md`, artifact references
- **Outputs**: `comment_log.md` — list of comments posted
- **Reviews**: comments contain actionable context

## Behavioral Requirements

### Workflow Registration

1. The `task` workflow MUST be added to the existing `notes` job in `.deepwork/jobs/notes/job.yml`.
2. The workflow MUST appear alongside existing workflows (setup, init, doctor, process_inbox) without modifying them.
3. The workflow MUST be discoverable via `get_workflows` MCP tool.

### Task Note Creation (`create_task_note`)

4. The step MUST create a note in the `notes/` group using `zk new notes/ --title "<title>" --no-input --print-path`.
5. The note frontmatter MUST include all required fields per `process.knowledge-management`: id, title, type (permanent), created, author, tags.
6. The initial tags MUST include `project/<slug>` and `status/in-progress`.
7. The note body MUST include an `## Objective` section summarizing the task goal.
8. The note body SHOULD include a `## Progress` section as an empty list for future updates.
9. The step MUST commit the new note to the notes repo.
10. The step MUST output the note file path for use by subsequent steps.

### Progressive Tag Enrichment (`enrich_tags`)

11. The step MUST accept one or more artifact references to add as tags.
12. The step MUST modify the note's frontmatter YAML to add new tags without disturbing existing tags.
13. The step MUST validate tag format against the schema in spec 006 before writing.
14. The step MUST replace the existing `status/*` tag when a status transition is requested.
15. The step MUST commit tag changes to the notes repo after each enrichment.
16. The step SHOULD be idempotent — adding a tag that already exists MUST NOT create duplicates.

### Shared Surface Commenting (`comment_shared_surface`)

17. The step MUST guide the agent to post a progress comment on relevant shared surface artifacts (issues, PRs, milestone issues).
18. Comments MUST include actionable context: what was done, how to verify, or what comes next.
19. Comments SHOULD reference related artifacts by number (e.g., `#242`) to trigger VCS platform auto-linking.
20. The step MUST use `gh issue comment` for GitHub and `fj issue comment` for Forgejo.
21. The step MAY be skipped if no shared surface artifacts exist yet for the task.

### Documentation

22. The `common_job_info` section of the notes job MUST include a summary of the `task` workflow and its intended use.
23. Step instructions MUST include example `zk list` queries for discovering task notes.
24. The workflow documentation MUST explain the progressive enrichment model.

## Edge Cases

- If the notes repo is not initialized (no `.zk/` directory), the step MUST fail with a clear error directing the agent to run `notes/init` first.
- If `zk new` fails (e.g., directory permissions), the step MUST report the error and not proceed to enrichment.
- If a shared surface artifact does not exist (e.g., issue was deleted), the commenting step MUST skip that artifact and log a warning.
- If the agent invokes `enrich_tags` without a prior `create_task_note`, the step MUST accept a manually provided note path.
