# Audit Existing Repo

## Objective

Inventory an existing notes repo to understand its current structure before migration.
If a `detection_report.md` exists from the `detect` step, use it to focus the audit
on format-specific concerns.

## Task

1. **File inventory**: Count all markdown files, grouped by directory:
   ```bash
   find <notes_path> -name "*.md" -not -path "*/.zk/*" -not -path "*/.git/*" -not -path "*/.obsidian/*" -not -path "*/.deepwork/*" -not -path "*/.claude/*" | wc -l
   find <notes_path> -name "*.md" -not -path "*/.zk/*" -not -path "*/.git/*" -not -path "*/.obsidian/*" -not -path "*/.deepwork/*" -not -path "*/.claude/*" -printf '%h\n' | sort | uniq -c | sort -rn
   ```

2. **Structure detection**: Is the repo flat, shallow (1 level of dirs), or deeply nested?

3. **Frontmatter analysis**: Sample 10-20 markdown files and check:
   - Do they have YAML frontmatter (`---` delimiters)?
   - What fields are present? (title, date, tags, etc.)
   - What format are dates in?
   - Is there any existing ID scheme?

4. **Link format detection**: Search for existing links:
   ```bash
   # Wikilinks (standard and Obsidian-style)
   grep -r '\[\[' <notes_path> --include="*.md" | head -20
   # Markdown links to local files
   grep -rP '\[.*\]\((?!http)' <notes_path> --include="*.md" | head -20
   # Obsidian embedded files
   grep -r '!\[\[' <notes_path> --include="*.md" | head -10
   ```

5. **Naming convention**: Are files named with dates, slugs, titles, or randomly?

6. **Format-specific analysis** (based on detection_report.md if available):

   **Obsidian vaults:**
   - Count files using callout syntax (`> [!`)
   - Count files with dataview blocks
   - Check for Obsidian-specific frontmatter fields (aliases, cssclass, publish)
   - List Obsidian plugins that affect content format (dataview, templater, etc.)
   - Check for `_archive/` or other Obsidian-convention dirs

   **Apple Notes exports:**
   - Count files with HTML fragments
   - Check for attachment references
   - Identify date patterns from filenames

7. **Operational files**: Identify and list files that MUST NOT be migrated:
   - TASKS.yaml, PROJECTS.yaml, SCHEDULES.yaml
   - SOUL.md, AGENTS.md, CLAUDE.md, HUMAN.md
   - SERVICES.md, ARCHITECTURE.md, REQUIREMENTS.md
   - Any dotfiles/directories (.git, .zk, .agents, .deepwork, .envrc, .repos)
   - Build/config files: flake.nix, flake.lock, pyproject.toml, uv.lock, etc.

8. **Legacy tree inventory**: Explicitly identify noncanonical directories that still contain note-like markdown:
   - Check common legacy trees such as `projects/`, `workflow/`, `research/`, `talks/`, `people/`, `journal/`, `ideas/`, `spikes/`, and `_archive/`
   - Separate them into:
     - note-like markdown that still needs migration
     - operational or generated markdown that should remain excluded
   - If a large legacy tree remains, do not stop at the canonical groups — call it out clearly in the audit

## Output Format

Write `.deepwork/tmp/audit_report.md` with sections:

```markdown
# Audit Report

## Summary
- Total markdown files: N
- Files with frontmatter: N
- Files without frontmatter: N
- Existing link format: wikilinks / markdown / mixed / none
- Source format: Obsidian / Apple Notes / Plain Markdown
- Keystone repo: yes / no

## Directory Structure
(tree or listing)

## Frontmatter Analysis
(field frequency table)

## Link Analysis
(existing link patterns)

## Format-Specific Findings
(Obsidian callouts count, dataview usage, Apple Notes HTML fragments, etc.)

## Naming Conventions
(observed patterns)

## Legacy Trees Requiring Migration
(noncanonical directories that still contain note-like markdown, plus which content is operational residue)

## Excluded Files (not to be migrated)
(list of operational/identity/config files)
```

## Important Notes

- Do NOT modify any files during audit — this is read-only
- Do NOT read personal note content in detail — only scan structure and metadata
- Sample files for frontmatter analysis rather than reading every file
- Exclude `.obsidian/`, `.deepwork/`, `.claude/` from file counts and analysis
- The audit report is transient workflow state. Store it under `.deepwork/tmp/` and do not commit it.
