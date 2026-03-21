<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->
# Convention: Knowledge Management (process.knowledge-management)

This convention defines the Zettelkasten-based knowledge management methodology for keystone notes repos. Both human users and OS agents share the same structure, tooling (`zk` CLI), and information pipeline.

## Problems Addressed

1. **Knowledge loss** — Agent sessions end and reasoning evaporates. The next session rediscovers the same constraints.
2. **No cross-pollination** — Agents cannot access each other's learned context.
3. **Human context drought** — No structured trail showing *why* decisions were made.
4. **Inconsistent terminology** — Notes repos lack a shared structure.

## Note Types

5. A notes repo MUST organize notes into five types, each in its own directory:

| Type | Directory | Purpose | Lifecycle |
|------|-----------|---------|-----------|
| Fleeting | `inbox/` | Quick captures, raw observations, session notes | Ephemeral — promote or delete within 48h |
| Literature | `literature/` | Summaries of external sources (docs, papers, articles) | Permanent — one note per source |
| Permanent | `notes/` | Atomic, self-contained knowledge notes | Permanent — single idea per note |
| Decision | `decisions/` | Architecture Decision Records (ADRs) | Permanent — append-only status updates |
| Index | `index/` | Maps of Content (MOCs) linking related notes | Permanent — updated as graph grows |

6. Every note MUST belong to exactly one type directory.

## Information Pipeline

7. New information MUST enter the system as a **fleeting note** in `inbox/`.
8. During processing (manual or via DeepWork `notes/process_inbox`), fleeting notes MUST be triaged:
   - **Promote to permanent**: Extract the atomic insight, create a permanent note in `notes/`, link to related notes, delete the fleeting note.
   - **Promote to literature**: If the note summarizes an external source, create a literature note in `literature/`, link to permanent notes it supports, delete the fleeting note.
   - **Promote to decision**: If the note captures an architectural decision, create a decision record in `decisions/`, delete the fleeting note.
   - **Discard**: If the note has no lasting value, delete it.
9. Agents SHOULD process their inbox at least once per day.

## Note Quality Rules

10. Permanent notes MUST be **atomic** — one idea per note. If a note covers multiple ideas, it MUST be split.
11. Permanent notes MUST be **self-contained** — understandable without reading linked notes.
12. Permanent notes MUST explain the **why**, not just the **what**.
13. Literature notes MUST include a source reference (URL, paper title, or document path).
14. Decision records MUST include: context, decision, consequences, and status (`proposed`, `accepted`, `deprecated`, `superseded`).

## Linking Rules

15. Every permanent note SHOULD link to at least one other note — orphan notes indicate missing context.
16. Links MUST use wikilink syntax: `[[202603201430]]`.
17. Index notes (MOCs) MUST link to all notes in their topic area and SHOULD provide a narrative structure explaining the relationships.
18. When creating a new permanent note, agents MUST search for related existing notes (`zk list --match "..."`) and add links.

## ID Schema

19. Note IDs MUST use 12-digit timestamps: `YYYYMMDDHHmm`.
20. IDs are generated automatically by `zk new` — agents MUST NOT assign IDs manually.

## Frontmatter Schema

21. Every note MUST include YAML frontmatter per `tool.zk` convention (id, title, type, created, author, tags).
22. Tags SHOULD be lowercase, hyphen-separated, and reuse existing tags where possible (`zk tag list`).

## Cross-Pollination

23. Agents MAY reference notes from other agents' repos by including the repo name and note ID: `agent-drago:202603201430`.
24. Shared insights SHOULD be published to the team's shared notes repo (if one exists) as permanent notes.

## Operational Boundaries

25. `TASKS.yaml` MUST NOT be managed by `zk` — it is operational state owned by the task loop.
26. `PROJECTS.yaml` MUST NOT be managed by `zk` — it is project metadata owned by `pz`.
27. The `projects/` directory (if present) MUST NOT be treated as a zk group — it follows `pz` conventions.
