# Migrate Notes

## Objective

Apply the fixes identified in the audit report to bring all notes into compliance with the Zettelkasten standard. Each file change is committed separately for reversibility.

## Task

### Process

1. **Read the audit report**
   - Parse `.deepwork/tmp/notes/audit_report.md` from the previous step
   - Group fixes by category for ordered application

2. **Apply fixes in this order** (to avoid conflicts):

   **a) Add missing frontmatter** (first — establishes IDs needed for renames)
   - For each file missing frontmatter:
     - Generate a 12-digit timestamp ID based on the file's git creation date or current time
     - If multiple files share the same minute-granularity timestamp, increment the ID by one minute to avoid collisions
     - Infer `type` from the file's directory (or default to `permanent`)
     - Infer `title` from the first `# Heading` or filename
     - Add YAML frontmatter block
     - Commit: `fix(notes): add frontmatter to {filename}`

   **b) Rename files** (second — establishes standard filenames)
   - For each non-standard filename:
     - Rename to `{id} {slug}.md` format
     - Update any wikilinks in other files that reference the old name
     - Commit: `refactor(notes): rename {old} to {new}`

   **c) Move files to correct directories** (third — uses established IDs and names)
   - For each misplaced file:
     - Move to the directory matching its `type` field
     - Commit: `refactor(notes): move {filename} to {directory}/`

   **d) Fix broken links** (fourth — after all moves/renames are done)
   - For each broken wikilink:
     - If the target was renamed or moved, update the link
     - If the target does not exist, add a comment `<!-- broken link: {target} -->`
     - Commit: `fix(notes): update broken links in {filename}`

3. **Verify migration**
   ```bash
   cd "$notes_path"
   zk list --orphan   # Check remaining orphans
   ```

4. **Write migration log**

## Output Format

### migration_log.md

Write to `.deepwork/tmp/notes/migration_log.md`:

```markdown
# Migration Log

**Repository**: {notes_path}
**Date**: {YYYY-MM-DD}

## Changes Applied

| # | Action | File | Commit | Details |
|---|--------|------|--------|---------|
| 1 | Add frontmatter | notes/foo.md | abc1234 | Generated ID 202603201430, type: permanent |
| 2 | Rename | my notes.md → 202603201430 my-notes.md | def5678 | Standardized filename |
| 3 | Move | inbox/adr.md → decisions/adr.md | ghi9012 | Type mismatch: decision in inbox |
| 4 | Fix link | notes/bar.md | jkl3456 | Updated [[old-id]] → [[202603201430]] |

## Remaining Issues

| File | Issue | Reason |
|------|-------|--------|
| notes/ambiguous.md | Orphan | No clear topic cluster to link from |

## Summary

- {N} frontmatter additions
- {N} renames
- {N} moves
- {N} link fixes
- {N} remaining issues (manual review needed)
```

## Quality Criteria

- Each file change is a separate git commit with a descriptive conventional commit message
- No note body text was lost or truncated during migration
- Wikilinks were updated to reflect any ID or filename changes
- Each commit can be reverted independently (`git revert {sha}`)

## Context

This step consumes the audit report from the `audit` step. The per-file commit strategy ensures that any mistake can be surgically reverted without affecting other fixes. After migration, the notebook should pass a clean `zk list` with no broken links.
