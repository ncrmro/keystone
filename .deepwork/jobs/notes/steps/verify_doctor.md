# Verify Repair

## Objective

Run post-repair health checks to confirm the notebook is valid and no data was lost.

## Task

1. **Index check**: Run `zk --notebook-dir <notes_path> index` — should complete without errors.

2. **Frontmatter coverage**: Check all markdown files in `notes/`, `literature/`, `decisions/`, `reports/`, `index/`, and `archive/` have valid frontmatter:
   ```bash
   # List files missing frontmatter
   for f in notes/*.md literature/*.md decisions/*.md reports/*.md index/*.md archive/*.md; do
     [ -f "$f" ] && head -1 "$f" | grep -q "^---" || echo "MISSING: $f"
   done
   ```

3. **Required fields**: Spot-check 5-10 repaired files for all required fields (id, title, type, created, author, tags). Report notes must also have project, report_kind, and source_ref.

4. **Orphan check**: Find permanent notes with no links:
   ```bash
   zk --notebook-dir <notes_path> list notes/ --orphan --format json
   ```
   Report the count. Orphans are acceptable after repair but should be addressed over time.

5. **Dead link check**: Search for wikilinks pointing to non-existent notes:
   ```bash
   # zk lsp diagnostics can detect this, or:
   grep -roh '\[\[[0-9]\{12\}\]\]' notes/ literature/ decisions/ reports/ index/ archive/ | sort -u | while read link; do
     id=$(echo "$link" | tr -d '[]')
     zk --notebook-dir <notes_path> list --format json --match "id: $id" | grep -q "$id" || echo "DEAD: $link"
   done
   ```

6. **Report chain check**: Verify recurring project reports have `previous_report` when a prior report exists.

7. **Gitignore coverage**: Verify the root `.gitignore` exists, includes the required ignore
   patterns for `.zk/notebook.db`, `.zk/notebook.db-journal`, `.direnv/`, `.env`,
   `.env.local`, `.venv/`, `__pycache__/`, `result`, `result-*`, `.DS_Store`,
   and `Thumbs.db`, and does NOT ignore `TASKS.yaml`, `PROJECTS.yaml`, or
   `SCHEDULES.yaml`.

8. **Ignored transient files**: If `.zk/notebook.db` or `.zk/notebook.db-journal` exist,
   verify git treats them as ignored:
   ```bash
   git check-ignore -v .zk/notebook.db .zk/notebook.db-journal
   ```

9. **Operational files intact**: Verify TASKS.yaml, PROJECTS.yaml, SCHEDULES.yaml are unchanged:
   ```bash
   git diff HEAD~N -- TASKS.yaml PROJECTS.yaml SCHEDULES.yaml
   ```
   (where N = number of repair commits)

10. **Content preservation**: Verify total markdown content is preserved:
   ```bash
   # Compare word count before/after (approximate check)
   git stash  # or compare against pre-migration commit
   ```

## Output Format

Write `doctor_report.md`:

```markdown
# Doctor Report

## Index Status
- `zk --notebook-dir <notes_path> index`: OK (N notes indexed)

## Frontmatter Coverage
- notes/: N/N files have valid frontmatter
- literature/: N/N
- decisions/: N/N
- reports/: N/N
- index/: N/N
- archive/: N/N
- inbox/: N/N (frontmatter optional for fleeting)

## Orphan Notes
- Count: N orphan permanent notes
- (list if < 10)

## Dead Links
- Count: N dead wikilinks
- (list if any)

## Report Chains
- Checked report series: N
- Missing previous_report links: N

## Gitignore
- root .gitignore: present / missing
- required ignore patterns: N/N present
- zk database files ignored: yes / no

## Operational Files
- TASKS.yaml: unchanged
- PROJECTS.yaml: unchanged
- SCHEDULES.yaml: unchanged

## Overall: PASS / FAIL
```
