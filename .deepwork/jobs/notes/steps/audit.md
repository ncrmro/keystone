# Audit Repository

## Objective

Scan an existing notes repository and produce a comprehensive migration report identifying all notes that do not conform to the Zettelkasten standard defined in `process.knowledge-management` and `tool.zk`.

## Task

### Process

1. **Scan all Markdown files**
   ```bash
   cd "$notes_path"
   find . -name "*.md" -not -path "./.zk/*" -not -path "./.git/*" -not -path "./projects/*"
   ```
   - Exclude `.zk/`, `.git/`, and `projects/` directories (not zk-managed)
   - Exclude `TASKS.yaml`, `PROJECTS.yaml`, `README.md`, and `AGENTS.md` (operational files)

2. **Check each file for issues**

   For each Markdown file, check:

   **a) Frontmatter**
   - Does the file have YAML frontmatter (delimited by `---`)?
   - Does it contain all required fields: id, title, type, created, author, tags?
   - Is the `type` field valid (fleeting, literature, permanent, decision, index)?

   **b) Directory placement**
   - Does the file's directory match its `type` field?
   - Is the file in a recognized directory (inbox, literature, notes, decisions, index)?
   - Files in the repo root or unrecognized directories need relocation

   **c) Filename format**
   - Does the filename match `{12-digit-id} {slug}.md`?
   - Is the slug lowercase, hyphen-separated, ASCII-only?

   **d) Links**
   - Are wikilinks `[[...]]` used (not Markdown links for internal notes)?
   - Do wikilink targets resolve to existing notes?

3. **Check for orphan notes**
   ```bash
   zk list --orphan
   ```
   - Notes with no incoming links (excluding index notes)

4. **Compile the report**

## Output Format

### audit_report.md

Write to `.deepwork/tmp/notes/audit_report.md`:

```markdown
# Notes Audit Report

**Repository**: {notes_path}
**Date**: {YYYY-MM-DD}
**Total files scanned**: {count}
**Issues found**: {count}

## Missing Frontmatter

| File | Action |
|------|--------|
| path/to/file.md | Add frontmatter with inferred type and generated ID |

## Incorrect Directory Placement

| File | Current Dir | Expected Dir (from type) | Action |
|------|-------------|-------------------------|--------|
| inbox/old-adr.md | inbox | decisions | Move to decisions/ |

## Non-Standard Filenames

| File | Issue | Suggested Name |
|------|-------|----------------|
| my notes.md | Missing ID, spaces | {id} my-notes.md |

## Broken Links

| File | Link | Issue |
|------|------|-------|
| notes/foo.md | [[999999999999]] | Target does not exist |

## Orphan Notes

| File | Suggestion |
|------|------------|
| notes/bar.md | Link from index/moc-topic.md |

## Summary

- {N} files need frontmatter
- {N} files need relocation
- {N} files need renaming
- {N} broken links
- {N} orphan notes
```

## Quality Criteria

- All `.md` files in the repo were scanned (excluding .zk, .git, projects)
- Issues are grouped by category with specific file paths
- Each issue includes a concrete remediation action
- The report is machine-parseable (consistent table format)

## Context

This is the first step of the `doctor` workflow. The `migrate` step consumes this report to apply fixes. A thorough audit prevents data loss during migration — every issue must be identified before any files are moved or renamed.
