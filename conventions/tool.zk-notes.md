# Convention: zk note workflows (tool.zk-notes)

This convention documents the canonical `zk` workflows for hub notes, report
capture, presentation deck capture, note repair, and archive handling in
Keystone notebooks.

## Hub note creation

1. Initiative hubs MUST be created as `index` notes.
2. Humans SHOULD create a hub with:

```bash
zk new index/ --title "Project: Keystone" --extra project="keystone"
```

3. Agents MUST create hubs non-interactively:

```bash
zk --notebook-dir ~/notes new index/ --title "Project: Keystone" --no-input --print-path \
  --extra project="keystone"
```

4. After creation, the note MUST be updated to include `project/keystone` and
   `status/active`, plus links to decisions, reports, presentations, repos, and
   next actions.

## Report capture

5. Reports MUST be created in `docs/reports/`.
6. Interactive capture MAY stream command output into `zk new`, for example:

```bash
cat system_diagnostics.log | zk new docs/reports/ \
  --interactive \
  --title "NixOS telemetry $(date +%Y-%m-%d)" \
  --extra project="unsupervised-platform" \
  --extra report_kind="nixos-telemetry" \
  --extra source_ref="system_diagnostics.log"
```

7. Agents SHOULD use non-interactive creation and then write the summarized
   report content into the created file:

```bash
zk --notebook-dir ~/notes new docs/reports/ --title "Keystone fleet health $(date +%Y-%m-%d)" \
  --no-input --print-path \
  --extra report_kind="keystone-system" \
  --extra source_ref="ks.doctor"
```

8. Before writing a recurring report, agents SHOULD search for the latest prior
   report of the same kind:

```bash
zk --notebook-dir ~/notes list docs/reports/ \
  --tag "report/keystone-system" \
  --tag "repo/ncrmro/nixos-config" \
  --tag "source/deepwork/ks-doctor" \
  --sort created- --limit 1 --format json
```

9. If a prior report exists, the new note MUST record it in `previous_report`.
10. Operational reports MAY omit the `project` field when they are better
    identified by `report/<kind>`, `repo/<owner>/<repo>`, and source tags.
11. When a report or durable note is based on a repo tracker artifact, agents
    SHOULD record the shared-surface refs in frontmatter during initial capture,
    for example:

```yaml
repo_ref: gh:ncrmro/keystone
milestone_ref: gh:ncrmro/keystone#12
issue_ref: gh:ncrmro/keystone#88
pr_ref: gh:ncrmro/keystone#91
```

## Presentation deck capture

12. Slidev decks MUST be created in `docs/presentations/`.
13. Humans SHOULD create a deck with:

```bash
zk new docs/presentations/ --title "Keystone architecture briefing"
```

14. Agents MUST create decks non-interactively and then apply the canonical
    Slidev deck template:

```bash
zk --notebook-dir ~/notes new docs/presentations/ --title "Keystone architecture briefing" \
  --no-input --print-path \
  --extra project="keystone" \
  --extra presentation_kind="architecture-briefing"
```

15. New decks SHOULD be initialized with Slidev YAML frontmatter, `---` slide
    separators, and a speaker-notes block that can contain zk wikilinks.
16. Before writing a replacement or recurring deck, agents SHOULD search for
    the latest related deck first:

```bash
zk --notebook-dir ~/notes list docs/presentations/ \
  --tag "presentation/architecture-briefing" \
  --tag "project/keystone" \
  --sort created- --limit 1 --format json
```

## Repair and cleanup

17. Notebook cleanup SHOULD start with a search-driven audit rather than manual
    browsing of the entire notebook.
18. Agents SHOULD use these queries during cleanup:

```bash
zk --notebook-dir ~/notes list docs/reports/ --format json
zk --notebook-dir ~/notes list docs/presentations/ --format json
zk --notebook-dir ~/notes list index/ --tag "status/active" --format json
zk --notebook-dir ~/notes list notes/ --orphan --format json
zk --notebook-dir ~/notes tag list
```

19. Cleanup workflows SHOULD normalize:
    - missing required frontmatter,
    - report chains,
    - presentation deck metadata,
    - missing hub links,
    - stale status tags, and
    - notes that should move to `archive/`.
20. Cleanup workflows SHOULD prefer frontmatter updates and directory moves over
    destructive rewriting of note bodies.

## Archive handling

21. Archived project material MUST be moved into `archive/`.
22. Archival workflows SHOULD verify that the hub note and latest report are
    still discoverable via `zk --notebook-dir <notes_path> list --tag "project/<slug>" --format json`.
23. Archived notes MAY retain project and repo tags. They MUST replace
    `status/active` with `status/archived`.

## Slash command mapping

24. `/notes.project` SHOULD create or refresh a hub note.
25. `/notes.report` SHOULD create a report note, apply the canonical tags, and
    chain it to the latest prior report.
26. Deck-focused workflows SHOULD create or refresh a presentation note in
    `docs/presentations/` rather than storing the deck in ad hoc folders.
27. `/notes.process_inbox` SHOULD continue to promote inbox notes and SHOULD link
    promoted project notes back to the relevant project hub.
28. `/notes.doctor` SHOULD repair and normalize an existing notebook, especially
    `~/notes`, rather than acting only as a one-time migration command.
29. `/notes.doctor` SHOULD ensure the root `.gitignore` ignores transient zk database
    files and local junk while keeping tracked YAML state files versioned.

## References

- `process.knowledge-management`
- `process.notes`
- `tool.zk`
