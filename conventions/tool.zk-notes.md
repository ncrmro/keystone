# Convention: zk note workflows (tool.zk-notes)

This convention documents the canonical `zk` workflows for hub notes, report
capture, note repair, and archive handling in Keystone notebooks.

## Hub note creation

1. Initiative hubs MUST be created as `index` notes.
2. Humans SHOULD create a hub with:

```bash
zk new index/ --title "Project: Keystone" --extra project="keystone"
```

3. Agents MUST create hubs non-interactively:

```bash
zk new index/ --title "Project: Keystone" --no-input --print-path \
  --extra project="keystone"
```

4. After creation, the note MUST be updated to include `project/keystone` and
   `status/active`, plus links to decisions, reports, repos, and next actions.

## Report capture

5. Reports MUST be created in `reports/`.
6. Interactive capture MAY stream command output into `zk new`, for example:

```bash
cat system_diagnostics.log | zk new reports/ \
  --interactive \
  --title "NixOS telemetry $(date +%Y-%m-%d)" \
  --extra project="unsupervised-platform" \
  --extra report_kind="nixos-telemetry" \
  --extra source_ref="system_diagnostics.log"
```

7. Agents SHOULD use non-interactive creation and then write the summarized
   report content into the created file:

```bash
zk new reports/ --title "Keystone fleet health $(date +%Y-%m-%d)" \
  --no-input --print-path \
  --extra report_kind="keystone-system" \
  --extra source_ref="ks.doctor"
```

8. Before writing a recurring report, agents SHOULD search for the latest prior
   report of the same kind:

```bash
zk list reports/ \
  --tag "report/keystone-system" \
  --tag "repo/ncrmro/nixos-config" \
  --tag "source/deepwork/ks-doctor" \
  --sort created- --limit 1 --format json
```

9. If a prior report exists, the new note MUST record it in `previous_report`.
10. Operational reports MAY omit the `project` field when they are better
    identified by `report/<kind>`, `repo/<owner>/<repo>`, and source tags.

## Repair and cleanup

11. Notebook cleanup SHOULD start with a search-driven audit rather than manual
    browsing of the entire notebook.
12. Agents SHOULD use these queries during cleanup:

```bash
zk list reports/ --format json
zk list index/ --tag "status/active" --format json
zk list notes/ --orphan --format json
zk tag list
```

13. Cleanup workflows SHOULD normalize:
    - missing required frontmatter,
    - report chains,
    - missing hub links,
    - stale status tags, and
    - notes that should move to `archive/`.
14. Cleanup workflows SHOULD prefer frontmatter updates and directory moves over
    destructive rewriting of note bodies.

## Archive handling

15. Archived project material MUST be moved into `archive/`.
16. Archival workflows SHOULD verify that the hub note and latest report are
    still discoverable via `zk list --tag "project/<slug>" --format json`.
17. Archived notes MAY retain project and repo tags. They MUST replace
    `status/active` with `status/archived`.

## Slash command mapping

18. `/notes.project` SHOULD create or refresh a hub note.
19. `/notes.report` SHOULD create a report note, apply the canonical tags, and
    chain it to the latest prior report.
20. `/notes.process_inbox` SHOULD continue to promote inbox notes and SHOULD link
    promoted project notes back to the relevant project hub.
21. `/notes.doctor` SHOULD repair and normalize an existing notebook, especially
    `~/notes`, rather than acting only as a one-time migration command.

## References

- `process.knowledge-management`
- `process.notes`
- `tool.zk`
