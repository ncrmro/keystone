# Execute Migration

## Objective

Execute the migration plan: add frontmatter, assign IDs, move files to correct directories, and convert link formats. Each transformation is a separate commit for reversibility.

## Task

1. **Read the migration plan** from `migration_plan.md`.

2. **For each file to migrate**, execute in order:

   a. Add/update YAML frontmatter:
      - Insert `---` delimiters if absent
      - Add required fields: id, title, type, created, author, tags
      - Preserve any existing frontmatter fields

   b. Rename and move the file:
      - New filename: `{id} {title-slug}.md`
      - Move to target directory (inbox/, literature/, notes/, decisions/, or index/)

   c. Convert links (if applicable):
      - Replace markdown links to internal files with wikilinks: `[text](file.md)` -> `[[id]]`

   d. **Commit this single file's changes**:
      ```bash
      git add -A
      git commit -m "chore(notes): migrate {old-filename} to {type}/{new-filename}"
      ```

3. **After all files are migrated**, do a final commit for any remaining changes (e.g., deleted empty directories).

## Output Format

Write `migration_log.md`:

```markdown
# Migration Log

## Transformations

| # | Old Path | New Path | Type | ID | Commit |
|---|----------|----------|------|-----|--------|
| 1 | journal/2026-03-15.md | notes/202603151200 daily-journal.md | permanent | 202603151200 | abc1234 |
| 2 | research/zfs-tuning.md | literature/202603101430 zfs-tuning.md | literature | 202603101430 | def5678 |

## Summary
- Files migrated: N
- Commits created: N
- Errors: 0
```

## Important Notes

- ONE COMMIT PER FILE — this is critical for reversibility (`git revert <hash>` undoes one file)
- NEVER delete note content — only add frontmatter, rename, and move
- Preserve existing frontmatter fields — merge, don't replace
- Skip operational files (TASKS.yaml, SOUL.md, etc.) entirely
- If a file already conforms to the standard, skip it and note "already compliant" in the log
