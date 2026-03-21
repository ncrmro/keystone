# Verify Migration

## Objective

Run post-migration health checks to confirm the notebook is valid and no data was lost.

## Task

1. **Index check**: Run `zk index` — should complete without errors.

2. **Frontmatter coverage**: Check all markdown files in `notes/`, `literature/`, `decisions/`, and `index/` have valid frontmatter:
   ```bash
   # List files missing frontmatter
   for f in notes/*.md literature/*.md decisions/*.md index/*.md; do
     [ -f "$f" ] && head -1 "$f" | grep -q "^---" || echo "MISSING: $f"
   done
   ```

3. **Required fields**: Spot-check 5-10 migrated files for all required fields (id, title, type, created, author, tags).

4. **Orphan check**: Find permanent notes with no links:
   ```bash
   zk list notes/ --orphan --format json
   ```
   Report the count. Orphans are acceptable post-migration but should be addressed over time.

5. **Dead link check**: Search for wikilinks pointing to non-existent notes:
   ```bash
   # zk lsp diagnostics can detect this, or:
   grep -roh '\[\[[0-9]\{12\}\]\]' notes/ literature/ decisions/ index/ | sort -u | while read link; do
     id=$(echo "$link" | tr -d '[]')
     zk list --format json --match "id: $id" | grep -q "$id" || echo "DEAD: $link"
   done
   ```

6. **Operational files intact**: Verify TASKS.yaml, PROJECTS.yaml, SCHEDULES.yaml are unchanged:
   ```bash
   git diff HEAD~N -- TASKS.yaml PROJECTS.yaml SCHEDULES.yaml
   ```
   (where N = number of migration commits)

7. **Content preservation**: Verify total markdown content is preserved:
   ```bash
   # Compare word count before/after (approximate check)
   git stash  # or compare against pre-migration commit
   ```

## Output Format

Write `doctor_report.md`:

```markdown
# Doctor Report

## Index Status
- `zk index`: OK (N notes indexed)

## Frontmatter Coverage
- notes/: N/N files have valid frontmatter
- literature/: N/N
- decisions/: N/N
- index/: N/N
- inbox/: N/N (frontmatter optional for fleeting)

## Orphan Notes
- Count: N orphan permanent notes
- (list if < 10)

## Dead Links
- Count: N dead wikilinks
- (list if any)

## Operational Files
- TASKS.yaml: unchanged
- PROJECTS.yaml: unchanged
- SCHEDULES.yaml: unchanged

## Overall: PASS / FAIL
```
