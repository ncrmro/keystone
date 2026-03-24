# Convention: Notes and reports (process.notes)

This convention standardizes how humans, agents, and DeepWork workflows store
active notes, operational reports, hubs, decisions, and archived material in a
shared zk notebook. It extends `process.knowledge-management`.

## Notebook structure

1. zk notebooks that follow the Keystone notes model MUST include these groups: `inbox/`,
   `literature/`, `notes/`, `decisions/`, `reports/`, `index/`, and `archive/`.
2. The existing flat notebook model MUST be preserved. Note organization MUST
   be expressed through frontmatter, links, and tags, not per-project folders.
3. `archive/` MUST remain zk-managed and searchable. Archived notes MUST remain
   linkable from active notes and historical reports.
4. `archive/` MUST be treated as lifecycle state, not as a separate knowledge
   method. Archived notes keep their original note purpose even after they move.

## Hub notes

5. Every active initiative MUST have exactly one active hub note.
6. The hub MUST be an `index` note and MUST use the initiative title as its
   primary heading.
7. The hub MUST include `project: <slug>` in frontmatter and the tags
   `project/<slug>` and `status/active`.
8. The hub MUST summarize:
   - the objective,
   - the current state,
   - the next actions,
   - curated links to permanent notes and decision notes,
   - links to related repos and trackers, and
   - a report ledger or query snippet for project reports.
9. The hub SHOULD act as a dynamic ledger. It MAY include canonical `zk`
   queries that list related reports, inbox captures, or recent activity.
10. Agents MUST link new initiative decisions and reports from the relevant hub
    before they consider the note complete, when a suitable hub exists.

## Report notes

11. Recurring operational output, research summaries, diagnostics, and other
    time-stamped run artifacts MUST be stored as `report` notes in `reports/`.
12. Report notes MUST include these frontmatter fields: `id`, `title`, `type`,
    `created`, `author`, `tags`, `report_kind`, and `source_ref`. `project` MAY
    be omitted for operational reports that are not initiative-scoped.
13. Report notes MUST set `type: report`.
14. If a prior report of the same kind exists for the same initiative or system,
    the new report MUST include a `previous_report` field pointing to the prior
    note ID.
15. Report notes SHOULD contain a concise summary, key findings, related issues
    or pull requests, and explicit next actions. Raw logs MAY be summarized, but
    the note SHOULD NOT become a raw dump unless the workflow explicitly needs it.
16. Workflows that generate a report repeatedly, such as `ks.doctor`, SHOULD
    search for the latest matching report note before creating a new one.

## Decisions and VCS continuity

17. Agents MUST record repo-level or initiative-level decisions that materially affect
    implementation, operations, or prioritization in the zk notebook.
18. If a decision relates to a Git issue or pull request, the note MUST link to
    the tracker item, and the tracker item MUST reference the note ID or path.
19. Decision notes SHOULD live in `decisions/` when the decision is durable and
    worth preserving independently of a single report.
20. If a report captures a short-lived operational decision, the report MAY hold
    it directly, and a relevant hub SHOULD link to that report when one exists.

## Tagging

21. Tags MUST use a constrained namespace.
22. The primary tags are:
    - `project/<slug>`
    - `repo/<owner>/<repo>`
    - `report/<kind>`
    - `status/active`
    - `status/archived`
    - `source/human`
    - `source/agent`
    - `source/deepwork`
    - `source/deepwork/ks-doctor`
23. Project tags MUST be the primary discovery path for initiative-scoped notes.
24. Repo tags SHOULD be added when a note materially concerns one specific repo and MAY be the primary discovery path for operational reports.
25. Agents SHOULD NOT introduce new tag namespaces.
26. Agents MAY introduce new values within an approved namespace only when the
    value is directly derived from an existing project slug, repo path, or
    recurring report kind already established by the workflow.
27. If a workflow appears to need an ad hoc tag outside the approved namespaces,
    the agent SHOULD avoid creating it and SHOULD prefer frontmatter fields or
    explicit links instead.

## Archival lifecycle

28. When an initiative is completed, abandoned, or superseded, its active hub note
    and associated initiative-specific notes SHOULD be moved to `archive/`.
29. Archived notes MUST replace `status/active` with `status/archived`.
30. Archived notes SHOULD record `archived_at`, `archived_reason`, and
    `archived_from` in frontmatter when the workflow performs the move.
31. Archiving MUST preserve backlinks, report chains, and project discoverability.
32. Active workflows, dashboards, and periodic reviews SHOULD exclude
    archived notes by policy unless the task is historical research.

## Agent workflow integration

33. Before starting work, agents SHOULD search for the relevant hub and recent
    reports with tags that match the note's identity, such as `project/<slug>`,
    `repo/<owner>/<repo>`, or `report/<kind>`.
34. After completing a task that produced meaningful findings, agents SHOULD
    create or update either a project decision note or a report note.
35. DeepWork workflows that produce documentation for later use MUST write their
    durable output into the notebook rather than leaving it only in scratch files.
36. Inbox processing workflows SHOULD attach promoted notes to a hub when the
    note contains a recognized `project/<slug>` tag or another clear hub relationship.

## References

- `process.knowledge-management`
- `tool.zk`
- `tool.zk-notes`
