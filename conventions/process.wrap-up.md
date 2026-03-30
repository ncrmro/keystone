# Convention: Session wrap-up (process.wrap-up)

Standards for checkpointing agent sessions so another agent or human can resume
without loss of context. The canonical entrypoint is `/wrap-up`.

## When to wrap up

1. Agents MUST run `/wrap-up` before ending any session that produced work, decisions,
   or deferred items — unless the user explicitly says no wrap-up is needed.
2. Agents SHOULD run `/wrap-up` before handing off to another agent or human reviewer.
3. Agents SHOULD use `/wrap-up defer <reason>` when pausing mid-task rather than
   abandoning context silently.

## What wrap-up produces

Every wrap-up MUST produce at minimum:

- A `docs/reports/` note in `~/notes` capturing context, status, testing, next steps,
  and deferred items.
- A structured handoff comment on every open issue or PR that was touched during the session.

When no tracking issue exists for in-flight work, wrap-up MUST create one and link it
to an appropriate milestone before commenting.

## Report note requirements

4. The report MUST be created non-interactively in `docs/reports/` using `zk`:

   ```bash
   zk --notebook-dir ~/notes new docs/reports/ \
     --title "Wrap-up: <short description> $(date +%Y-%m-%d)" \
     --no-input --print-path \
     --extra report_kind="session-wrap-up" \
     --extra source_ref="wrap-up-skill"
   ```

5. Before creating a new report, agents MUST search for a prior wrap-up of the same scope:

   ```bash
   zk --notebook-dir ~/notes list docs/reports/ \
     --tag "report/session-wrap-up" --sort created- --limit 1 --format json
   ```

6. If a prior report exists, the new note MUST set `previous_report` in frontmatter.
7. The report body MUST include these sections in order:
   - **Context** — what was being worked on, key decisions, relevant refs (SHAs, branches, files).
   - **Status** — what is complete, in progress, and blocked.
   - **Testing** — commands run and outcomes, or an explicit statement that no testing occurred.
   - **Next steps** — ordered concrete actions for the next agent or human (name files, commands, issue numbers).
   - **Deferred** — items explicitly punted with the reason and a suggested trigger for revisiting.

## Issue and PR comment requirements

8. Agents MUST post a handoff comment to every open issue or PR touched in the session.
9. The comment header MUST be `## Session check-in — <YYYY-MM-DD>` for normal wrap-ups
   or `## Deferred — <YYYY-MM-DD>` for deferred wrap-ups.
10. Every comment MUST include these subsections: **What happened**, **Testing**,
    **Next steps**, and **Deferred** (or "nothing deferred").
11. The comment MUST end with a footer identifying it as a wrap-up check-in and linking
    the report note path or URL.

## Tracking issue creation

12. When no tracking issue exists for in-flight work, agents MUST create one before
    commenting. The issue title MUST be concise and follow Conventional Commits style.
13. The new issue MUST be linked to an existing milestone. If no suitable milestone
    exists, agents MUST ask the user before creating one.
14. The issue ref MUST be recorded in the report note frontmatter using the canonical
    format: `gh:<owner>/<repo>#<number>` or `fj:<owner>/<repo>#<number>`.

## Hub note update

15. After creating the report and commenting on issues/PRs, agents SHOULD update the
    relevant project hub note to link the new report and any new issues.

## Completion

16. Wrap-up is complete when the agent has:
    - Confirmed the report note path.
    - Listed every issue/PR that received a comment with its URL.
    - Noted any step that failed and the manual fallback.
