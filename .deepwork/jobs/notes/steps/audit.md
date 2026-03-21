# Audit Existing Repo

## Objective

Inventory an existing notes repo to understand its current structure before migration.

## Task

1. **File inventory**: Count all markdown files, grouped by directory:
   ```bash
   find <notes_path> -name "*.md" -not -path "*/.zk/*" -not -path "*/.git/*" | wc -l
   find <notes_path> -name "*.md" -not -path "*/.zk/*" -not -path "*/.git/*" -printf '%h\n' | sort | uniq -c | sort -rn
   ```

2. **Structure detection**: Is the repo flat, shallow (1 level of dirs), or deeply nested?

3. **Frontmatter analysis**: Sample 10-20 markdown files and check:
   - Do they have YAML frontmatter (`---` delimiters)?
   - What fields are present? (title, date, tags, etc.)
   - What format are dates in?
   - Is there any existing ID scheme?

4. **Link format detection**: Search for existing links:
   ```bash
   # Wikilinks
   grep -r '\[\[' <notes_path> --include="*.md" | head -20
   # Markdown links
   grep -rP '\[.*\]\((?!http)' <notes_path> --include="*.md" | head -20
   ```

5. **Naming convention**: Are files named with dates, slugs, titles, or randomly?

6. **Operational files**: Identify and list files that MUST NOT be migrated:
   - TASKS.yaml, PROJECTS.yaml, SCHEDULES.yaml
   - SOUL.md, AGENTS.md, CLAUDE.md, HUMAN.md
   - SERVICES.md, ARCHITECTURE.md, REQUIREMENTS.md
   - Any dotfiles/directories (.git, .zk, .agents, .deepwork, .envrc, .repos)

## Output Format

Write `audit_report.md` with sections:

```markdown
# Audit Report

## Summary
- Total markdown files: N
- Files with frontmatter: N
- Files without frontmatter: N
- Existing link format: wikilinks / markdown / mixed / none

## Directory Structure
(tree or listing)

## Frontmatter Analysis
(field frequency table)

## Link Analysis
(existing link patterns)

## Naming Conventions
(observed patterns)

## Excluded Files (not to be migrated)
(list of operational/identity files)
```

## Important Notes

- Do NOT modify any files during audit — this is read-only
- Do NOT read personal note content in detail — only scan structure and metadata
- Sample files for frontmatter analysis rather than reading every file
