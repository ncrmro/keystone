# Convention: Session wrap-up (process.wrap-up)

A human-facing tool for winding down engineering work when there are too many open
threads. Use `/wrap-up` to distill in-flight context into durable issue
comments and PR check-ins so work can be set down cleanly and resumed later by
another agent or human.

This is not an agent operational convention. It is intentionally invoked by the human
when switching out of engineering mode.

## When to wrap up

1. Humans SHOULD run `/wrap-up` when they have too many open threads and need to step
   back from engineering work.
2. Humans SHOULD run `/wrap-up` before handing off work to another person or agent.
3. Use `/wrap-up defer <reason>` to explicitly record why work is being set aside and
   what condition should trigger picking it back up.

## What wrap-up produces

Every wrap-up MUST produce at minimum:

- A structured handoff comment on every open issue or PR that was touched during the session.

When no tracking issue exists for in-flight work, wrap-up MUST create one and link it
to an appropriate milestone before commenting.

## Issue and PR comment requirements

4. Agents MUST post a handoff comment to every open issue or PR touched in the session.
5. The comment header MUST be `## Session check-in — <YYYY-MM-DD>` for normal wrap-ups
   or `## Deferred — <YYYY-MM-DD>` for deferred wrap-ups.
6. Every comment MUST include these subsections: **What happened**, **Testing**,
    **Next steps**, and **Deferred** (or "nothing deferred").
7. The comment MUST end with a footer identifying it as a wrap-up check-in.

## Tracking issue creation

8. When no tracking issue exists for in-flight work, agents MUST create one before
    commenting. The issue title MUST be concise and follow Conventional Commits style.
9. The new issue MUST be linked to an existing milestone. If no suitable milestone
    exists, agents MUST ask the user before creating one.

## Project linkage

15. Wrap-up MUST NOT update the project hub note just to record a session check-in,
    report, or tracking issue.
16. Instead, the report note and any created tracking issue MUST carry the project
    linkage directly through canonical refs such as `repo_ref`, `milestone_ref`,
    and `issue_ref`, plus the appropriate project or repo tags.
17. If a project hub note is already in scope for unrelated substantive work, it MAY
    be updated as part of that separate work, but wrap-up itself MUST NOT treat hub
    mutation as a required or default step.

## Completion

18. Wrap-up is complete when the agent has:
    - Confirmed the report note path.
    - Listed every issue/PR that received a comment with its URL.
    - Noted any step that failed and the manual fallback.
