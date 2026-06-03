# Wrap-up

You have too many open threads. This skill helps you wind down engineering work cleanly —
distilling in-flight context into durable artifacts so you can step away and resume later
(or hand off to someone else) without losing anything.

See `process.wrap-up` for the authoritative convention.

## What this skill does

1. Captures context, status, testing, next steps, and deferred items in shared issue/PR comments.
2. Comments on every open issue or PR touched in the session with a structured handoff block.
3. Creates a tracking issue (linked to a milestone) when none exists for in-flight work.

## Steps

### 1. Gather context

Before writing anything, collect:

- Current working directory and any active git repos (branch, uncommitted state, last few commits via `git log --oneline -10`).
- Open issues and PRs in scope (`gh issue list`, `fj issue list`, or explicit URLs from the user).
- Test output, build results, or error messages from this session.
- Any `$ARGUMENTS` passed by the user — treat them as the primary focus.

### 2. Draft the handoff

Draft the handoff body with these sections:

#### Context

What was being worked on, why, and what decisions were made. Include relevant commit SHAs, branch names, and file paths.

#### Status

Current state: what is complete, what is in progress, and what is blocked.

#### Testing

Evidence: commands run, output snippets, pass/fail status. If no tests were run, state that explicitly.

#### Next steps

Ordered list of concrete actions for the next agent or human. Name files, commands, and issue numbers.

#### Deferred

Items explicitly punted with the reason and a suggested trigger for revisiting. "Nothing deferred" if none.

### 3. Update or create tracking issues

For each relevant repo:

**Open issue or PR already exists** — post a handoff comment (see step 4).

**No tracking issue exists** — create one first:

1. Find or confirm a milestone:
   - GitHub: `gh api repos/{owner}/{repo}/milestones`
   - Forgejo: `tea api --login forgejo /repos/{owner}/{repo}/milestones`
2. Create the issue with a concise title and the handoff body as the description:
   - GitHub: `gh issue create --title "..." --body "..." --milestone <id>`
   - Forgejo: `fj -H https://git.ncrmro.com issue create --title "..." --description "..."`
3. Use the created issue as the canonical continuation point.

### 4. Post handoff comment

Use this template for every issue or PR comment:

```markdown
## Session check-in — <YYYY-MM-DD>

**Status:** <one-line summary — complete / in progress / blocked / deferred>

### What happened

- <key action or decision>
- <key action or decision>

### Testing

<what was verified, commands run, outcome — or "not tested in this session">

### Next steps

1. <first concrete action>
2. <second action>

### Deferred

<items punted and why — or "nothing deferred">

---
*Check-in from /wrap-up. Picking this up? Start from this issue/PR thread.*
```

For a deferral, change the header to `## Deferred — <YYYY-MM-DD>` and add a
`**Deferred until:** <event or condition>` line.

### 5. Finish

- List every issue/PR that received a comment with its URL.
- Note any step that failed and suggest the manual fallback.

## Intent parsing

- `/wrap-up` with no arguments — wrap up the current session context.
- `/wrap-up <description>` — use the description as the report title and issue summary focus.
- `/wrap-up defer <reason>` — treat as a deferral; use the "Deferred" comment header.
