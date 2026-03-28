# Spec: Task Note Tag Schema

## Stories Covered
- US-007: Define task note tag schema and nomenclature
- US-003: Implement progressive tag enrichment step
- US-005: Support task note querying by project, milestone, agent, or status

## Affected Modules
- `conventions/process.knowledge-management.md` — extend frontmatter schema
- `.deepwork/jobs/notes/job.yml` — common_job_info tag reference
- `docs/` — glossary entry for "shared surface"

## Data Models

### Task Note Frontmatter Tags

Tags in the `tags:` list follow these namespaced formats:

| Tag Pattern | Example | Description |
|-------------|---------|-------------|
| `project/<slug>` | `project/keystone` | Project the task belongs to |
| `milestone:<number>` | `milestone:8` | GitHub/Forgejo milestone number |
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

## Behavioral Requirements

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

## Edge Cases

- If a task spans multiple repositories, multiple `repo:` tags MAY be present.
- If a task has no associated milestone, the `milestone:` tag MUST be omitted (not set to 0 or null).
- If a platform prefix is unknown, the agent MUST ask the operator rather than guessing.
- Tag enrichment on a note that has been archived SHOULD be avoided — archive notes are frozen state.

## Query Patterns

Standard `zk list` queries for task notes:

```bash
# All tasks for a project
zk list notes/ --tag "project/keystone" --format json

# Tasks for a specific milestone
zk list notes/ --tag "milestone:8" --format json

# Completed tasks
zk list notes/ --tag "status/completed" --format json

# Tasks by a specific agent
zk list notes/ --match "author: agent-drago" --format json

# Blocked tasks across all projects
zk list notes/ --tag "status/blocked" --format json
```
