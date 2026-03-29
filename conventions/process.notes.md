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
8. When the initiative uses one or more VCS repositories, the hub MUST include
   a `repos:` frontmatter list with one full remote URL per repo. SSH and HTTPS
   URLs are both valid.
9. The hub MUST summarize:
   - the objective,
   - the current state,
   - the next actions,
   - curated links to permanent notes and decision notes,
   - links to related repos and trackers, and
   - a report ledger or query snippet for project reports and presentations.
10. Repo links and `repo/<owner>/<repo>` tags MUST be derived from the declared
    remote URLs rather than handwritten in a competing format.
11. The hub SHOULD act as a dynamic ledger. It MAY include canonical `zk`
    queries that list related reports, presentations, inbox captures, or recent
    activity.
12. Agents MUST link new initiative decisions, reports, and presentations from
    the relevant hub before they consider the note complete, when a suitable
    hub exists.
13. Automation that needs the active project set SHOULD discover it from active
    hub notes via `zk --notebook-dir <notes_path> list index/ --tag "status/active" --format json`.

## Report notes

14. Recurring operational output, research summaries, diagnostics, and other
    time-stamped run artifacts MUST be stored as `report` notes in
    `docs/reports/`.
15. Report notes MUST include these frontmatter fields: `id`, `title`, `type`,
    `created`, `author`, `tags`, `report_kind`, and `source_ref`. `project` MAY
    be omitted for operational reports that are not initiative-scoped.
16. Report notes MUST set `type: report`.
17. If a prior report of the same kind exists for the same initiative or system,
    the new report MUST include a `previous_report` field pointing to the prior
    note ID.
18. Report notes SHOULD contain a concise summary, key findings, related issues
    or pull requests, and explicit next actions. Raw logs MAY be summarized, but
    the note SHOULD NOT become a raw dump unless the workflow explicitly needs it.
19. Workflows that generate a report repeatedly, such as `ks.doctor`, SHOULD
    search for the latest matching report note before creating a new one.

## Shared-surface references

20. Notes that refer to VCS shared-surface artifacts such as milestones, issues,
    pull requests, or repos MUST store those references in frontmatter fields,
    not ad hoc tags.
21. GitHub tracker references MUST use the format
    `gh:<owner>/<repo>#<number>`.
22. Forgejo tracker references MUST use the format
    `fj:<owner>/<repo>#<number>`.
23. Repo references without an issue-like number MUST use the format
    `gh:<owner>/<repo>` or `fj:<owner>/<repo>`.
24. Recommended frontmatter fields for shared-surface references are:
    - `repo_ref`
    - `milestone_ref`
    - `issue_ref`
    - `pr_ref`
25. These fields MUST store real normalized refs, not placeholders. Values such as
    `gh:owner/repo-name#ID`, `gh:repo#123`, or bare `#123` are invalid.
26. When a note includes one of these fields, any corresponding `repo/<owner>/<repo>`
    tag MUST agree with the normalized repo identity in the frontmatter ref.
27. Agents MUST NOT invent alternate tracker formats such as bare issue numbers,
    local path aliases, or custom prefixes when a GitHub or Forgejo shared
    surface exists.
28. If both a human notes repo and one or more owner mirror notes refer to the
    same shared-surface artifact, they SHOULD reuse the same normalized
    `gh:` or `fj:` ref string.
29. When milestone, issue, or pull request identity is known during note capture,
    agents SHOULD record all known refs together so later workflows do not have
    to reconstruct the shared-surface context from prose alone.

## Presentation decks

30. Slidev decks and other Markdown-native presentation artifacts MUST be
    stored as `presentation` notes in `docs/presentations/`.
31. Presentation notes MUST include these frontmatter fields: `id`, `title`,
    `type`, `created`, `author`, `tags`, and `presentation_kind`. `project` MAY
    be omitted for non-initiative decks.
32. Initiative presentation decks MUST link to the relevant hub note, and the
    hub SHOULD link back to the active deck.
33. Presentation notes SHOULD include a concise statement of objective,
    references to source notes or decisions, and explicit next actions when the
    deck drives follow-up work.
34. Presentation notes SHOULD preserve valid Slidev frontmatter, slide
    separators, and any speaker-note links needed to trace source material.

## Decisions and VCS continuity

35. Agents MUST record repo-level or initiative-level decisions that materially affect
    implementation, operations, or prioritization in the zk notebook.
36. If a decision relates to a Git issue or pull request, the note MUST link to
    the tracker item, and the tracker item MUST reference the note ID or path.
37. Decision notes SHOULD live in `decisions/` when the decision is durable and
    worth preserving independently of a single report.
38. If a report captures a short-lived operational decision, the report MAY hold
    it directly, and a relevant hub SHOULD link to that report when one exists.

## Tagging

39. Tags MUST use a constrained namespace.
40. The primary tags are:
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
41. Project tags MUST be the primary discovery path for initiative-scoped notes.
42. Repo tags SHOULD be added when a note materially concerns one specific repo and MAY be the primary discovery path for operational reports or decks.
43. Repo tags MUST be derived from the normalized `owner/repo` identity implied
    by the hub note's declared remote URL or the note's explicit repo reference.
44. Agents SHOULD NOT introduce new tag namespaces.
45. Agents MAY introduce new values within an approved namespace only when the
    value is directly derived from an existing project slug, repo path, or
    recurring report or presentation kind already established by the workflow.
46. If a workflow appears to need an ad hoc tag outside the approved namespaces,
    the agent SHOULD avoid creating it and SHOULD prefer frontmatter fields or
    explicit links instead.

## Archival lifecycle

47. When an initiative is completed, abandoned, or superseded, its active hub note
    and associated initiative-specific notes SHOULD be moved to `archive/`.
48. Archived notes MUST replace `status/active` with `status/archived`.
49. Archived notes SHOULD record `archived_at`, `archived_reason`, and
    `archived_from` in frontmatter when the workflow performs the move.
50. Archiving MUST preserve backlinks, report chains, presentation deck
    provenance, and project discoverability.
51. Active workflows, dashboards, and periodic reviews SHOULD exclude
    archived notes by policy unless the task is historical research.

## Agent workflow integration

52. Before starting work, agents SHOULD search for the relevant hub and recent
    reports with tags that match the note's identity, such as `project/<slug>`,
    `repo/<owner>/<repo>`, `report/<kind>`, or `presentation/<kind>`.
53. After completing a task that produced meaningful findings, agents SHOULD
    create or update either a project decision note, a report note, or a
    presentation note.
54. DeepWork workflows that produce documentation for later use MUST write their
    durable output into the notebook rather than leaving it only in scratch files.
55. Inbox processing workflows SHOULD attach promoted notes to a hub when the
    note contains a recognized `project/<slug>` tag or another clear hub relationship.
56. Humans and agents SHOULD resolve non-keystone project repos to
    `$HOME/code/{owner}/{repo}` and keystone-managed repos to
    `~/.keystone/repos/{owner}/{repo}` after normalizing the declared remote URL.
57. Notes repos MUST gitignore transient notebook database files and other local
    junk while keeping `.zk/config.toml`, `.zk/templates/`, and operational YAML
    state files tracked.

## References

- `process.knowledge-management`
- `tool.zk`
- `tool.zk-notes`
