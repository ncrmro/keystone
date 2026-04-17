# Spec: Notes Task Workflow

## Stories Covered
- US-001: Create `notes.task` DeepWork job definition
- US-002: Implement task note creation step
- US-003: Implement progressive tag enrichment step
- US-004: Implement shared surface commenting step
- US-005: Support task note querying by project, milestone, agent, or status
- US-006: Add doctor audit for missing task note tags
- US-007: Define task note tag schema and nomenclature
- US-008: Document the `notes.task` workflow for agents and operators

## Affected Modules
- `.deepwork/jobs/notes/job.yml` — new `task` workflow, step definitions, common_job_info
- `.deepwork/jobs/notes/steps/create_task_note.md` — new step file
- `.deepwork/jobs/notes/steps/enrich_tags.md` — new step file
- `.deepwork/jobs/notes/steps/comment_shared_surface.md` — new step file
- `.deepwork/jobs/notes/steps/verify_doctor.md` — extend with task note audit
- `conventions/process.knowledge-management.md` — extend frontmatter schema
- `docs/` — glossary entry for "shared surface"

## Tag Schema

### Task Note Frontmatter Tags

Tags in the `tags:` list follow these namespaced formats:

| Tag Pattern | Example | Description |
|-------------|---------|-------------|
| `project/<slug>` | `project/keystone` | Project the task belongs to |
| `milestone:<platform>:<owner>/<repo>#<number>` | `milestone:gh:ncrmro/keystone#8` | Linked milestone |
| `issue:<platform>:<owner>/<repo>#<number>` | `issue:gh:ncrmro/keystone#242` | Linked issue |
| `pull_request:<platform>:<owner>/<repo>#<number>` | `pull_request:gh:ncrmro/keystone#243` | Linked PR |
| `repo:<platform>:<owner>/<repo>` | `repo:gh:ncrmro/keystone` | Repository reference |
| `status/<state>` | `status/in-progress` | Current task status |

### Platform Prefixes

| Prefix | Platform |
|--------|----------|
| `gh` | GitHub |
| `fj` | Forgejo |

### Valid Status States

| State | Meaning |
|-------|---------|
| `in-progress` | Agent is actively working on the task |
| `blocked` | Task cannot proceed — reason documented in note body |
| `needs-review` | Work is done, awaiting review |
| `completed` | Task finished and verified |

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
- **Reviews**: tags follow schema, status tag is singular

#### `comment_shared_surface`
- **Inputs**: `task_note_path.md`, artifact references
- **Outputs**: `comment_log.md` — list of comments posted
- **Reviews**: comments contain actionable context

## Behavioral Requirements

### Tag Schema

1. Every task note MUST include at least one `project/<slug>` tag at creation time.
2. Every task note MUST include exactly one `status/<state>` tag at all times.
3. The initial status tag MUST be `status/in-progress` when the note is created.
4. Platform prefixes MUST use `gh` for GitHub and `fj` for Forgejo.
5. Artifact tags (milestone, issue, pull_request) SHOULD be added as soon as the artifact exists.
6. The `repo:` tag SHOULD be added when the task involves a specific repository.
7. Tags MUST be lowercase and hyphenated, consistent with `process.knowledge-management` convention.
8. When a task transitions status, the old status tag MUST be replaced (not appended) — only one `status/*` tag at a time.
9. The tag schema MUST be documented in the notes job's `common_job_info` section.
10. A "shared surface" glossary entry SHOULD be added to keystone documentation defining the term as "a VCS artifact (issue, PR, milestone) visible to all collaborators on a platform."

### Workflow Registration

11. The `task` workflow MUST be added to the existing `notes` job in `.deepwork/jobs/notes/job.yml`.
12. The workflow MUST appear alongside existing workflows (setup, init, doctor, process_inbox) without modifying them.
13. The workflow MUST be discoverable via `get_workflows` MCP tool.

### Task Note Creation (`create_task_note`)

14. The step MUST create a note in the `notes/` group using `zk new notes/ --title "<title>" --no-input --print-path`.
15. The note frontmatter MUST include all required fields per `process.knowledge-management`: id, title, type (permanent), created, author, tags.
16. The initial tags MUST include `project/<slug>` and `status/in-progress`.
17. The note body MUST include an `## Objective` section summarizing the task goal.
18. The note body SHOULD include a `## Progress` section as an empty list for future updates.
19. The step MUST commit the new note to the notes repo.
20. The step MUST output the note file path for use by subsequent steps.

### Progressive Tag Enrichment (`enrich_tags`)

21. The step MUST accept one or more artifact references to add as tags.
22. The step MUST modify the note's frontmatter YAML to add new tags without disturbing existing tags.
23. The step MUST validate tag format against the tag schema before writing.
24. The step MUST replace the existing `status/*` tag when a status transition is requested.
25. The step MUST commit tag changes to the notes repo after each enrichment.
26. The step SHOULD be idempotent — adding a tag that already exists MUST NOT create duplicates.

### Shared Surface Commenting (`comment_shared_surface`)

27. The step MUST guide the agent to post a progress comment on relevant shared surface artifacts (issues, PRs, milestone issues).
28. Comments MUST include actionable context: what was done, how to verify, or what comes next.
29. Comments SHOULD reference related artifacts by number (e.g., `#242`) to trigger VCS platform auto-linking.
30. The step MUST use `gh issue comment` for GitHub and `fj issue comment` for Forgejo.
31. The step MAY be skipped if no shared surface artifacts exist yet for the task.

### Doctor Audit

32. The doctor workflow MUST identify notes with `status/*` tags as task notes.
33. For each task note, the audit MUST check whether expected artifact tags are present based on available VCS data.
34. The audit MUST NOT modify any notes — it produces a report only.
35. The audit SHOULD use `gh` or `fj` CLI to query recent issues and PRs in repositories referenced by `repo:` tags.
36. If a task note references a `repo:` tag but lacks `issue:` or `pull_request:` tags, and the VCS platform shows related artifacts, the audit MUST flag this as a potential missing tag.
37. If a task note has `status/completed` but no `pull_request:` tag, the audit SHOULD flag this as a potential omission.
38. The audit MUST NOT require network access if the `--offline` flag is provided — in offline mode, it SHOULD only check tag format validity and status consistency.
39. The audit output MUST include a section titled `## Task Note Tag Audit` in the doctor report.
40. Each flagged note MUST include: note path, current tags, missing tag recommendations with specific values.
41. The audit MUST report a summary count: total task notes, fully tagged, partially tagged, flagged.
42. All existing doctor workflow quality criteria MUST continue to pass after this extension.
43. If no task notes exist in the notebook, the audit section MUST report "No task notes found" and pass without error.

### Documentation

44. The `common_job_info` section of the notes job MUST include a summary of the `task` workflow and its intended use.
45. Step instructions MUST include example `zk list` queries for discovering task notes.
46. The workflow documentation MUST explain the progressive enrichment model.

## Query Patterns

```bash
# All tasks for a project
zk list notes/ --tag "project/keystone" --format json

# Tasks for a specific milestone
zk list notes/ --tag "milestone:gh:ncrmro/keystone#8" --format json

# Completed tasks
zk list notes/ --tag "status/completed" --format json

# Tasks by a specific agent
zk list notes/ --match "author: agent-drago" --format json

# Blocked tasks across all projects
zk list notes/ --tag "status/blocked" --format json
```

## Edge Cases

- If a task spans multiple repositories, multiple `repo:` tags MAY be present.
- If a task has no associated milestone, the `milestone:` tag MUST be omitted (not set to 0 or null).
- If a platform prefix is unknown, the agent MUST ask the operator rather than guessing.
- Tag enrichment on a note that has been archived SHOULD be avoided — archive notes are frozen state.
- If the notes repo is not initialized (no `.zk/` directory), the step MUST fail with a clear error directing the agent to run `notes/init` first.
- If `zk new` fails (e.g., directory permissions), the step MUST report the error and not proceed to enrichment.
- If a shared surface artifact does not exist (e.g., issue was deleted), the commenting step MUST skip that artifact and log a warning.
- If the agent invokes `enrich_tags` without a prior `create_task_note`, the step MUST accept a manually provided note path.
- If `gh` or `fj` CLI is unavailable, the doctor audit MUST fall back to offline mode and log a warning.
- If a task note references a repository that no longer exists, the audit MUST skip that note with a warning rather than failing.
- If a task note has malformed tags, the audit MUST flag the format error separately from missing tags.
- If multiple task notes reference the same issue/PR, the audit MUST NOT flag this as an error — shared artifacts across tasks are valid.
