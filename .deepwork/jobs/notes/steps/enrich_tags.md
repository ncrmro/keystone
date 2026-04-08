# Enrich Tags

## Objective

Add artifact tags to an existing task note and transition its status tag. Called after new VCS
artifacts (issues, PRs, milestones) are created or when the task status changes.

## Task

1. **Identify the note**: Use the path from `create_task_note` output, or accept a manually
   provided note path if this step is invoked standalone.

2. **Read the current frontmatter**:

   ```bash
   head -30 <note_path>
   ```

3. **Validate new tags**: For each artifact reference to add, verify it follows the schema from
   `process.knowledge-management`:

   | Tag pattern | Example |
   |-------------|---------|
   | `issue:<platform>:<owner>/<repo>#<number>` | `issue:gh:ncrmro/keystone#242` |
   | `pull_request:<platform>:<owner>/<repo>#<number>` | `pull_request:gh:ncrmro/keystone#243` |
   | `milestone:<platform>:<owner>/<repo>#<number>` | `milestone:gh:ncrmro/keystone#8` |
   | `repo:<platform>:<owner>/<repo>` | `repo:gh:ncrmro/keystone` |
   | `status/<state>` | `status/completed` |

   Valid platforms: `gh` (GitHub), `fj` (Forgejo).
   Valid status states: `in-progress`, `blocked`, `needs-review`, `completed`.

4. **Add new artifact tags**: Edit the `tags:` list in the frontmatter YAML to append new tags.
   Do NOT create duplicate entries — check if a tag already exists before adding.

5. **Update status tag** (if status transition requested): Find the existing `status/*` entry and
   replace it with the new status. Only one `status/*` tag must exist at a time.

6. **Commit changes**:

   ```bash
   git add <note_path>
   git commit -m "chore(notes): enrich tags — <note title> [<new tags summary>]"
   ```

7. **Verify**: Read the note frontmatter again and confirm the tags list is correct.

## Output Format

Write `.deepwork/tmp/enrichment_log.md`:

```markdown
# Tag Enrichment Log

- **Note**: notes/<id> <title-slug>.md
- **Tags added**: issue:gh:ncrmro/keystone#242, milestone:gh:ncrmro/keystone#8
- **Status**: in-progress → completed  (or "unchanged")
- **Commit**: <git short hash>

## Resulting frontmatter tags

```yaml
tags:
  - project/keystone
  - repo:gh:ncrmro/keystone
  - milestone:gh:ncrmro/keystone#8
  - issue:gh:ncrmro/keystone#242
  - pull_request:gh:ncrmro/keystone#243
  - status/completed
```
```

## Important Notes

- This step is idempotent — adding a tag that already exists MUST NOT create a duplicate.
- If the note path is not provided and no prior `create_task_note` output exists, ask the
  operator for the note path.
- If a platform prefix is unknown (not `gh` or `fj`), ask the operator rather than guessing.
- Do NOT enrich tags on notes in `archive/` — archived notes are frozen state.
- If status is transitioning to `completed`, verify the task note has at least one
  `pull_request:` or `issue:` tag as evidence of delivery.
