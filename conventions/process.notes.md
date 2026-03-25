# Convention: Notes, reports, and presentations (process.notes)

This convention standardizes how humans, agents, and DeepWork workflows store
active notes, operational reports, Slidev decks, hubs, decisions, and archived
material in a shared zk notebook. It extends
`process.knowledge-management`.

## Notebook structure

1. zk notebooks that follow the Keystone notes model MUST include these groups: `inbox/`,
   `literature/`, `notes/`, `decisions/`, `docs/reports/`,
   `docs/presentations/`, `index/`, and `archive/`.
2. The existing flat notebook model MUST be preserved within those canonical
   groups. Note organization MUST be expressed through frontmatter, links, and
   tags, not per-project folders.
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
    - a report ledger or query snippet for project reports and presentations.
9. The hub SHOULD act as a dynamic ledger. It MAY include canonical `zk`
   queries that list related reports, presentations, inbox captures, or recent
   activity.
10. Agents MUST link new initiative decisions, reports, and presentations from
    the relevant hub before they consider the note complete, when a suitable
    hub exists.
11. Automation that needs the active project set SHOULD discover it from active
    hub notes via `zk --notebook-dir <notes_path> list index/ --tag "status/active" --format json`.

## Report notes

12. Recurring operational output, research summaries, diagnostics, and other
    time-stamped run artifacts MUST be stored as `report` notes in
    `docs/reports/`.
13. Report notes MUST include these frontmatter fields: `id`, `title`, `type`,
    `created`, `author`, `tags`, `report_kind`, and `source_ref`. `project` MAY
    be omitted for operational reports that are not initiative-scoped.
14. Report notes MUST set `type: report`.
15. If a prior report of the same kind exists for the same initiative or system,
    the new report MUST include a `previous_report` field pointing to the prior
    note ID.
16. Report notes SHOULD contain a concise summary, key findings, related issues
    or pull requests, and explicit next actions. Raw logs MAY be summarized, but
    the note SHOULD NOT become a raw dump unless the workflow explicitly needs it.
17. Workflows that generate a report repeatedly, such as `ks.doctor`, SHOULD
    search for the latest matching report note before creating a new one.

## Presentation decks

18. Slidev decks and other Markdown-native presentation artifacts MUST be
    stored as `presentation` notes in `docs/presentations/`.
19. Presentation notes MUST include these frontmatter fields: `id`, `title`,
    `type`, `created`, `author`, `tags`, and `presentation_kind`. `project` MAY
    be omitted for non-initiative decks.
20. Initiative presentation decks MUST link to the relevant hub note, and the
    hub SHOULD link back to the active deck.
21. Presentation notes SHOULD include a concise statement of objective,
    references to source notes or decisions, and explicit next actions when the
    deck drives follow-up work.
22. Presentation notes SHOULD preserve valid Slidev frontmatter, slide
    separators, and any speaker-note links needed to trace source material.

## Decisions and VCS continuity

23. Agents MUST record repo-level or initiative-level decisions that materially affect
    implementation, operations, or prioritization in the zk notebook.
24. If a decision relates to a Git issue or pull request, the note MUST link to
    the tracker item, and the tracker item MUST reference the note ID or path.
25. Decision notes SHOULD live in `decisions/` when the decision is durable and
    worth preserving independently of a single report.
26. If a report captures a short-lived operational decision, the report MAY hold
    it directly, and a relevant hub SHOULD link to that report when one exists.

## Tagging

27. Tags MUST use a constrained namespace.
28. The primary tags are:
    - `project/<slug>`
    - `repo/<owner>/<repo>`
    - `report/<kind>`
    - `presentation/<kind>`
    - `status/active`
    - `status/archived`
    - `source/human`
    - `source/agent`
    - `source/deepwork`
    - `source/deepwork/ks-doctor`
29. Project tags MUST be the primary discovery path for initiative-scoped notes.
30. Repo tags SHOULD be added when a note materially concerns one specific repo and MAY be the primary discovery path for operational reports or decks.
31. Agents SHOULD NOT introduce new tag namespaces.
32. Agents MAY introduce new values within an approved namespace only when the
    value is directly derived from an existing project slug, repo path, or
    recurring report or presentation kind already established by the workflow.
33. If a workflow appears to need an ad hoc tag outside the approved namespaces,
    the agent SHOULD avoid creating it and SHOULD prefer frontmatter fields or
    explicit links instead.

## Archival lifecycle

34. When an initiative is completed, abandoned, or superseded, its active hub note
    and associated initiative-specific notes SHOULD be moved to `archive/`.
35. Archived notes MUST replace `status/active` with `status/archived`.
36. Archived notes SHOULD record `archived_at`, `archived_reason`, and
    `archived_from` in frontmatter when the workflow performs the move.
37. Archiving MUST preserve backlinks, report chains, presentation deck
    provenance, and project discoverability.
38. Active workflows, dashboards, and periodic reviews SHOULD exclude
    archived notes by policy unless the task is historical research.

## Agent workflow integration

39. Before starting work, agents SHOULD search for the relevant hub and recent
    reports with tags that match the note's identity, such as `project/<slug>`,
    `repo/<owner>/<repo>`, `report/<kind>`, or `presentation/<kind>`.
40. After completing a task that produced meaningful findings, agents SHOULD
    create or update either a project decision note, a report note, or a
    presentation note.
41. DeepWork workflows that produce documentation for later use MUST write their
    durable output into the notebook rather than leaving it only in scratch files.
42. Inbox processing workflows SHOULD attach promoted notes to a hub when the
    note contains a recognized `project/<slug>` tag or another clear hub relationship.
43. Notes repos MUST gitignore transient notebook database files and other local
    junk while keeping `.zk/config.toml`, `.zk/templates/`, and operational YAML
    state files tracked.

## References

- `process.knowledge-management`
- `tool.zk`
- `tool.zk-notes`
