# Write Note

## Objective

Record the completed task as a report note in the configured notes dir (`$NOTES_DIR`,
which resolves to `~/notes` for human users on Keystone systems) so the agent's work
is permanently visible in the knowledge base and synced to the remote notes repo.

## Task

### 1. Check whether a notes repo is available

```bash
NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
if [ -d "$NOTES_DIR/.zk" ]; then
  echo "notes repo found"
else
  echo "no notes repo — skipping"
fi
```

If `$NOTES_DIR/.zk` does not exist, write `note_status.md` with the single line
`Skipped: configured notes dir is not a zk notebook.` and stop — do not treat this as an error.

### 2. Read the task report

Read `task_report.json` from the previous step. Extract:
- `task_name`
- `status` (completed or blocked)
- `message`
- `issues_or_blockers` (array)
- `pull_requests_created` (array)
- `issues_created` (array)

Also read the task's `project` field from TASKS.yaml (match by `task_name`).

### 3. Determine report metadata

- **report_kind**: `task-execution`
- **title**: `Task: <task_name>` (e.g., `Task: reply-to-nicholas-timeline`)
- **tags**: always include `source/agent`, `source/deepwork`, `report/task-execution`.
  If a project slug is known, also add `project/<slug>`.
- **author**: use the current user (`$USER` or the value from SOUL.md if present)

### 4. Search for a prior report of the same task

```bash
NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
zk list --notebook-dir "$NOTES_DIR" docs/reports/ \
  --match "task-execution $task_name" --format json | head -5
```

If a prior note is found, record its `id` as `previous_report`.

### 5. Create the note

```bash
NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
note_path=$(zk new --notebook-dir "$NOTES_DIR" docs/reports/ \
  --title "Task: <task_name>" --no-input --print-path)
```

Write the note body to the path returned:

```markdown
---
id: "<YYYYMMDDHHmm>"
title: "Task: <task_name>"
type: report
created: <ISO-8601 timestamp>
author: <author>
tags: [source/agent, source/deepwork, report/task-execution, project/<slug>]
report_kind: task-execution
source_ref: <task_name>
previous_report: "<prior note ID>"   # omit this line entirely if no prior report
---

## Outcome

**Status**: <completed | blocked>

<message from task_report.json>

## Artifacts

- Pull requests: <list URLs, or "none">
- Issues created: <list URLs, or "none">
- Blockers: <list, or "none">
```

Omit the `previous_report` frontmatter line entirely if no prior report was found.
Omit empty artifact entries (e.g., if `pull_requests_created` is empty, write "none").

### 6. Commit the note

```bash
NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
cd "$NOTES_DIR"
git add docs/reports/
git commit -m "chore(notes): task-execution report for <task_name>"
```

Do not push — the systemd `repo-sync` timer handles that automatically.

### 7. Rebuild the zk index

```bash
NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
zk index --notebook-dir "$NOTES_DIR"
```

## Output Format

Write `note_status.md`:

```markdown
# Note Status

- Path: <notes-dir>/docs/reports/<id> task-<slug>.md
- Note ID: <id>
- Committed: yes
- Skipped: no
```

Or if skipped:

```markdown
# Note Status

- Skipped: configured notes dir is not a zk notebook.
```
