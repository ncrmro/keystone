# Plan Migration

## Objective

Based on the audit report, propose a concrete migration plan that converts the existing repo to standardized zk structure.

## Task

1. **File classification**: For each markdown file (excluding operational files), determine:
   - Target note type: fleeting, literature, permanent, decision, or index
   - Target directory: inbox/, literature/, notes/, decisions/, or index/
   - Classification rationale (brief)

   Classification heuristics:
   - Files with structured analysis or ADR-like format -> `decisions/`
   - Files that summarize external sources (articles, docs) -> `literature/`
   - Files that curate links to other files -> `index/`
   - Files with developed, standalone ideas -> `notes/`
   - Short, unstructured captures -> `inbox/`

2. **ID assignment strategy**: Decide how to assign IDs:
   - **Preferred**: Backdate from git history (`git log --follow --diff-filter=A --format=%ai -- <file>`)
   - **Fallback**: Use file modification time (`stat -c %Y <file>`)
   - **Last resort**: Generate new timestamps (only for files with no git history)
   - Handle collisions: if two files share the same minute, offset by 1 minute

3. **Frontmatter plan**: For each file, specify:
   - Fields to add (id, title, type, created, author, tags)
   - How to derive `title` (from existing frontmatter, filename, or first heading)
   - How to derive `tags` (from existing frontmatter, directory name, or content keywords)

4. **Directory moves**: Map current paths to target paths.

5. **Link conversion**: If existing links use markdown format, plan conversion to wikilinks.

## Output Format

Write `migration_plan.md`:

```markdown
# Migration Plan

## ID Assignment Strategy
(backdating method + collision handling)

## File Mappings

| Current Path | Target Path | Type | ID | Notes |
|-------------|-------------|------|-----|-------|
| journal/2026-03-15.md | notes/202603151200 daily-journal.md | permanent | 202603151200 | Backdate from git |
| research/zfs-tuning.md | literature/202603101430 zfs-tuning.md | literature | 202603101430 | Has source URL |

## Frontmatter Additions
(summary of what needs to be added per file or batch)

## Link Conversions
(before/after examples)

## Excluded (no action)
(list of operational files skipped)
```

## Important Notes

- NEVER plan to delete content — only add frontmatter, move files, and convert links
- Files already conforming to the standard should be left as-is
- The plan must be reviewable before execution (next step is the actual migration)
