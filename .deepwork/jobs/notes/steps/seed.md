# Seed Index Notes

## Objective

Create initial Map of Content (MOC) index notes that serve as entry points into the knowledge graph. If the repo already has notes, discover topic clusters and create MOCs for them. If the repo is empty, create a welcome index note.

## Task

### Process

1. **Check existing content**
   ```bash
   cd "$notes_path"
   find notes/ literature/ decisions/ -name "*.md" 2>/dev/null | head -20
   ```

2. **If the repo has existing notes** (non-empty `notes/`, `literature/`, or `decisions/`):
   - Scan tags across all notes: `zk tag list`
   - Identify the top 3-5 tag clusters (tags used by 2+ notes)
   - For each cluster, create an index note:
     ```bash
     zk new index --title "MOC: {Topic Area}"
     ```
   - In each index note, list and link all notes with that tag
   - Add a brief narrative explaining how the notes relate

3. **If the repo is empty** (no notes in any directory):
   - Create a welcome index note:
     ```bash
     zk new index --title "MOC: Welcome"
     ```
   - The welcome note SHOULD explain the notebook structure and link to the five directories
   - Optionally create a "MOC: Getting Started" note with tips for the Zettelkasten workflow

4. **Update author field** in all seed notes to match the provided `author` input

5. **Commit seed notes**
   ```bash
   cd "$notes_path"
   git add index/
   git commit -m "chore(notes): seed initial index notes"
   ```

## Output Format

### seed_notes

A plain text file listing one created index note path per line:

```
index/202603201430 moc-welcome.md
index/202603201431 moc-storage-architecture.md
```

## Quality Criteria

- At least one index note was created in `index/`
- All seed notes have valid YAML frontmatter with type: index
- If existing notes were found, index notes link to them via wikilinks
- Changes are committed with a conventional commit message

## Context

This step runs after `scaffold` in the `init` workflow. The seed notes provide immediate navigational structure so the notebook is useful from day one, not an empty set of directories.
