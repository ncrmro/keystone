# Parse Sources

## Objective

Parse pre-fetched source data and create or update tasks in TASKS.yaml. This step bridges external sources (email, GitHub) with the internal task tracking system.

## Task

The task loop orchestrator has already run declarative shell commands to fetch source data and written the output to `.deepwork/sources.json`. Your FIRST action MUST be to read that file. Then parse the JSON, compare it against the current TASKS.yaml, and add any new tasks while avoiding duplicates.

### Process

1. **Read the current state**
   - Read TASKS.yaml from the working directory
   - Read PROJECTS.yaml from the working directory to understand project associations
   - If TASKS.yaml does not exist, create it with `tasks: []`

2. **Parse the source JSON**
   - Read the source JSON from `.deepwork/sources.json` in the working directory (written by the task loop orchestrator before invoking this workflow)
   - If the file is missing or empty, report zero items ingested and finish
   - Each source section is labeled with its source name (e.g., "email", "github-issues")
   - Email source JSON includes envelope metadata AND a `body` field with full message text
   - Use BOTH the subject and body fields when determining if an email is actionable (subjects may be empty)
   - Parse each source's JSON output

3. **Identify new tasks from sources**
   - For each source item (email, issue, PR), determine if it represents actionable work
   - Skip items that are purely informational (newsletters, automated notifications, CI status emails)
   - Skip items that already have a corresponding task in TASKS.yaml (match by `source_ref`)
   - For GitHub issues/PRs: use the issue/PR URL as `source_ref`
   - For email: use the format `email-{id}-{sender_address}` as `source_ref` (e.g., `email-10-nicholas.romero@ncrmro.com`)

4. **Create task entries for new items**
   - Set `status: pending`
   - Set `source` to the source type (email, github-issue, github-pr)
   - Set `source_ref` to the unique identifier from the source
   - Set `project` if the source item clearly maps to a project in PROJECTS.yaml (e.g., a GitHub issue from a repo listed under a project)
   - Write a clear, actionable `description` derived from the source content
   - Choose a descriptive kebab-case `name`

5. **Write updated TASKS.yaml**
   - Follow the schema in `steps/shared/tasks_schema.md` exactly. The only top-level key is `tasks`. Do NOT add `summary:`, `metadata:`, or any other top-level keys.
   - Append new tasks to the existing list
   - Do NOT modify existing tasks in any way — preserve their exact status, description, and all fields verbatim
   - Do NOT change the status of any existing task (e.g., do not change `pending` to `completed` or vice versa)
   - Do NOT rename fields (e.g., do not change `name` to `id`, `description` to `title`, etc.)
   - Do not reorder existing tasks
   - When writing the file, copy existing task entries character-for-character and only append new entries at the end
   - After writing, validate with `yq e '.' TASKS.yaml` to confirm the file is valid YAML

6. **Write the ingest report**

### Core rules

- **Ping/Pong**: Any message containing "ping" (from any source) MUST always create a task to reply with "pong". This is a standing requirement that applies regardless of sender or context.

### Scheduled tasks

Scheduled tasks (with `source: "schedule"`) are created by the `agent-scheduler` timer (see process.agent-cronjobs.md), not by ingest. Ingest MUST preserve these tasks and MUST NOT treat them as duplicates of source items.

### Guidelines for task creation

- **Email**: Not every email is a task. Look for requests, action items, questions that need answers, or assignments. Ignore automated notifications, marketing, and FYI-only messages.
- **Reply emails**: Replies to agent-sent emails (e.g., replies to the daily status digest, replies to task confirmations) frequently contain NEW task requests from the human. When an email is a reply (`Re: ...`), focus on the new content above the quoted text — that is likely a new instruction, not a repeat of the original. Never dismiss a reply as "not actionable" just because it is part of an existing thread.
- **GitHub Issues**: Open issues assigned to the agent or unassigned in watched repos are potential tasks. Closed issues are not.
- **GitHub PRs**: PRs requesting review are tasks. PRs the agent authored that need updates are tasks. Merged/closed PRs are not.
- **GitHub/Forgejo PR Reviews** (`github-pr-reviews`, `forgejo-pr-reviews`): Reviews on agent-authored PRs. These are high-priority — the agent's PR is blocked until feedback is addressed.
  - Reviews with state `CHANGES_REQUESTED` (GitHub) or `REQUEST_CHANGES` (Forgejo) MUST always create a task.
  - Reviews with state `COMMENTED` SHOULD create a task only if comments contain actionable feedback (not purely informational or approving).
  - Use `source: "github-pr-review"` or `source: "forgejo-pr-review"`.
  - Use `source_ref: "{pr_url}#reviews"` (keyed by PR URL to consolidate multiple reviews on the same PR into one task).
  - The task `description` MUST include: repo name, PR number, branch name (`pr_branch`), reviewer name, review state, and a summary of each comment (file path + comment body). Preserve enough context for the executing agent to act without re-fetching.
  - Example task name: `address-review-fix-login-bug-42`
- **Deduplication**: Always check `source_ref` against existing tasks. If a task already exists for a source item, skip it even if the source data has changed.

## Output Format

### TASKS.yaml

Updated task file with any new tasks appended.

**Structure**:

```yaml
tasks:
  - name: "existing-task"
    description: "An existing task"
    status: completed
  - name: "reply-to-nicholas-email"
    description: "Reply to Nicholas's email about deployment timeline"
    status: pending
    project: "agent-space"
    source: "email"
    source_ref: "email-42-nicholas.romero@ncrmro.com"
  - name: "fix-login-bug"
    description: "Fix the login redirect bug reported in issue #42"
    status: pending
    project: "notes"
    source: "github-issue"
    source_ref: "https://github.com/ncrmro/notes/issues/42"
```

### ingest_report.md

Summary of what was ingested.

**Structure**:

```markdown
# Ingest Report

**Date**: [current date]

## Sources Processed

| Source        | Items Found | New Tasks | Skipped (duplicate) | Skipped (not actionable) |
| ------------- | ----------- | --------- | ------------------- | ------------------------ |
| email         | [n]         | [n]       | [n]                 | [n]                      |
| github-issues | [n]         | [n]       | [n]                 | [n]                      |

## New Tasks Created

- **[task-name]**: [description] (from [source])

## Skipped Items

- [item description]: [reason skipped]

## Summary

[1-2 sentences: X new tasks created from Y source items. Z items skipped.]
```

**Concrete example**:

```markdown
# Ingest Report

**Date**: 2026-02-19

## Sources Processed

| Source        | Items Found | New Tasks | Skipped (duplicate) | Skipped (not actionable) |
| ------------- | ----------- | --------- | ------------------- | ------------------------ |
| email         | 8           | 1         | 0                   | 7                        |
| github-issues | 3           | 2         | 1                   | 0                        |

## New Tasks Created

- **reply-to-nicholas-timeline**: Reply to Nicholas about deployment timeline (from email)
- **fix-login-redirect**: Fix login redirect bug from issue #42 (from github-issues)
- **review-api-docs-pr**: Review PR #15 updating API documentation (from github-issues)

## Skipped Items

- Email from "GitHub Notifications": automated notification, not actionable
- Email from "Newsletter": marketing content, not actionable
- Issue #38 (ncrmro/notes): already tracked as task "update-search-index"

## Summary

3 new tasks created from 11 source items. 8 items skipped (7 not actionable, 1 duplicate).
```

## Quality Criteria

- No duplicate tasks created for source items already tracked in TASKS.yaml
- Every new task has required fields: name, description, status (pending), source, source_ref
- Tasks are associated with projects from PROJECTS.yaml when the relationship is clear
- Existing tasks are preserved and not modified
- The ingest report accurately reflects what was processed

## Context

This is the first step in the task loop pipeline. The task loop orchestrator runs declarative shell commands to fetch source data before invoking this workflow, writing the JSON to `.deepwork/sources.json`. Read that file to get the pre-fetched data. The output feeds into the prioritize workflow, which orders tasks by project priority.
