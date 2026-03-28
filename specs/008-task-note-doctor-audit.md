# Spec: Task Note Doctor Audit

## Stories Covered
- US-006: Add doctor audit for missing task note tags

## Affected Modules
- `.deepwork/jobs/notes/steps/verify_doctor.md` — extend with task note audit
- `.deepwork/jobs/notes/job.yml` — add quality criteria for task note tag coverage in doctor workflow

## Behavioral Requirements

### Audit Scope

1. The doctor workflow MUST identify notes with `status/*` tags as task notes.
2. For each task note, the audit MUST check whether expected artifact tags are present based on available VCS data.
3. The audit MUST NOT modify any notes — it produces a report only.

### Cross-Reference Logic

4. The audit SHOULD use `gh` or `fj` CLI to query recent issues and PRs in repositories referenced by `repo:` tags.
5. If a task note references a `repo:` tag but lacks `issue:` or `pull_request:` tags, and the VCS platform shows related issues/PRs (matching the note title or project tag), the audit MUST flag this as a potential missing tag.
6. If a task note has `status/completed` but no `pull_request:` tag, the audit SHOULD flag this as a potential omission.
7. The audit MUST NOT require network access if the `--offline` flag is provided — in offline mode, it SHOULD only check tag format validity and status consistency.

### Report Format

8. The audit output MUST include a section titled `## Task Note Tag Audit` in the doctor report.
9. Each flagged note MUST include: note path, current tags, missing tag recommendations with specific values.
10. The audit MUST report a summary count: total task notes, fully tagged, partially tagged, flagged.

### Backward Compatibility

11. All existing doctor workflow quality criteria MUST continue to pass after this extension.
12. The task note audit MUST be additive — it adds a new section to the doctor report without modifying existing sections.
13. If no task notes exist in the notebook, the audit section MUST report "No task notes found" and pass without error.

## Edge Cases

- If `gh` or `fj` CLI is unavailable, the audit MUST fall back to offline mode and log a warning.
- If a task note references a repository that no longer exists or is inaccessible, the audit MUST skip that note with a warning rather than failing.
- If a task note has malformed tags (wrong format per spec 006), the audit MUST flag the format error separately from missing tags.
- If multiple task notes reference the same issue/PR, the audit MUST NOT flag this as an error — shared artifacts across tasks are valid.
