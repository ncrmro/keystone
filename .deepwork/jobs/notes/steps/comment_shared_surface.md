# Comment on Shared Surface

## Objective

Post a structured progress comment on the VCS artifacts referenced by the task note. Keeps
collaborators informed and ensures any agent can resume context from the shared surface alone.

## Task

1. **Identify artifacts**: Read the task note frontmatter and collect all artifact tags:
   - `issue:gh:<owner>/<repo>#<number>` → `gh issue comment <owner>/<repo> <number>`
   - `pull_request:gh:<owner>/<repo>#<number>` → `gh pr comment <owner>/<repo> <number>`
   - `milestone:gh:<owner>/<repo>#<number>` → comment on the milestone issue
   - `issue:fj:<owner>/<repo>#<number>` → `fj issue comment <owner>/<repo> <number>`
   - `pull_request:fj:<owner>/<repo>#<number>` → `fj issue comment <owner>/<repo> <number>`

2. **Skip if no artifacts**: If no `issue:`, `pull_request:`, or `milestone:` tags exist yet,
   log "No shared surface artifacts — skipping" and output an empty comment log. Do NOT fail.

3. **Draft comment body**: Write a concise progress update. Include:
   - What was done (1–3 bullet points)
   - How to verify (command to run, URL to check, or screenshot description)
   - What comes next (if known)
   - Reference related artifacts by number (e.g., `#242`) for platform auto-linking.

   Example:

   ```
   ## Work Update

   - Implemented `create_task_note` and `enrich_tags` steps in `.deepwork/jobs/notes/`
   - Added task note tag schema to `conventions/process.knowledge-management.md`

   To verify: `zk list notes/ --tag "project/keystone" --format json`

   Next: open PR for Phase 2 (relates to #243).
   ```

4. **Post the comment** on each artifact:

   ```bash
   # GitHub issue
   gh issue comment <number> --repo <owner>/<repo> --body "<comment>"

   # GitHub PR
   gh pr comment <number> --repo <owner>/<repo> --body "<comment>"

   # Forgejo issue
   fj issue comment <owner>/<repo> <number> --body "<comment>"
   ```

5. **Log each post**: Record the artifact URL returned by the CLI.

## Output Format

Write `.deepwork/tmp/comment_log.md`:

```markdown
# Shared Surface Comment Log

## Comments posted

| Artifact | URL |
|----------|-----|
| issue:gh:ncrmro/keystone#242 | https://github.com/ncrmro/keystone/issues/242#issuecomment-... |
| milestone:gh:ncrmro/keystone#8 | https://github.com/ncrmro/keystone/issues/8#issuecomment-... |

## Comment body

<the comment text that was posted>
```

## Important Notes

- If an artifact does not exist (e.g., deleted issue), skip it and log a warning — do NOT fail.
- If `gh` or `fj` CLI is unavailable, log the error and ask the operator to post manually.
- Comments MUST include actionable context — do not post empty or boilerplate-only comments.
- If the same comment would be a duplicate of the previous one, skip and note "no new progress
  to report."
- The milestone issue receives the same comment as a regular issue — there is no special
  milestone comment command.
