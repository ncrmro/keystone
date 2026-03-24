# Repair Notebook

## Objective

Normalize an existing notebook so it follows the current project, report, and
archive conventions without rewriting note content unnecessarily.

## Task

1. Read `audit_report.md` and identify:
   - missing groups,
   - missing frontmatter,
   - notes that belong in `reports/` or `archive/`,
   - project tags without a matching hub note, and
   - recurring reports that are missing `previous_report`.

2. Ensure the standard groups exist:
   - `inbox/`
   - `literature/`
   - `notes/`
   - `decisions/`
   - `reports/`
   - `index/`
   - `archive/`

3. Repair frontmatter for touched notes:
   - preserve existing fields,
   - add missing required fields for the note type, and
   - normalize `project`, `report_kind`, `source_ref`, and archive metadata when relevant.

4. Repair project hubs:
   - find each active `project/<slug>` tag,
   - ensure there is exactly one active index note for that slug,
   - if missing, create the hub in `index/`,
   - if duplicated, mark one as canonical and link the others for manual follow-up.

5. Repair report chains:
   - for each recurring `report/<kind>` + `project/<slug>` combination, sort by creation time,
   - set `previous_report` on each note after the first, and
   - ensure the relevant project hub links the latest reports.

6. Archive concluded projects:
   - identify notes tagged or marked as archived, completed, abandoned, or superseded,
   - move those notes into `archive/`,
   - replace `status/active` with `status/archived`,
   - record `archived_at`, `archived_reason`, and `archived_from` when the move is performed.

7. Commit the repair in one logical commit:
   ```bash
   git add -A
   git commit -m "chore(notes): repair notebook structure and project report graph"
   ```

## Output Format

Write `repair_log.md`:

```markdown
# Repair Log

## Summary
- Groups created: [list]
- Notes retagged: N
- Project hubs created: N
- Project hubs refreshed: N
- Reports chained: N
- Notes archived: N

## Project hubs
| Project | Hub Path | Action |
|---------|----------|--------|
| keystone | index/202603241200 project-keystone.md | created |

## Report chains
| Project | Report Kind | Note | Previous Report |
|---------|-------------|------|-----------------|
| keystone | fleet-health | reports/202603241230 keystone-fleet-health-2026-03-24.md | 202603221015 |

## Archive moves
| Note | Old Path | New Path | Reason |
|------|----------|----------|--------|
| 202603011200 old-project.md | index/202603011200 old-project.md | archive/202603011200 old-project.md | archived project |
```

## Important Notes

- Prefer minimal, structural edits over rewriting note bodies.
- Do NOT modify operational files such as `TASKS.yaml`, `PROJECTS.yaml`, or `SCHEDULES.yaml`.
- If a case is ambiguous, preserve the note and record it for manual follow-up instead of guessing.
