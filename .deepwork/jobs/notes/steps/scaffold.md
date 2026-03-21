# Scaffold Notebook

## Objective

Create the standard Zettelkasten directory structure, zk configuration, and note templates for a notes repository. This step is idempotent — running it on an existing repo adds missing pieces without destroying existing content.

## Task

### Process

1. **Validate inputs**
   - Confirm `notes_path` exists and is a git repository (`git -C "$notes_path" rev-parse --git-dir`)
   - If the directory does not exist, abort — scaffolding requires a pre-cloned repo

2. **Create directory structure**
   ```bash
   cd "$notes_path"
   mkdir -p .zk/templates inbox literature notes decisions index
   ```

3. **Write .zk/config.toml**
   - Use the standard config from `tool.zk` convention
   - Configure groups for each directory (inbox, literature, notes, decisions, index)
   - Set ID format to 12-digit numeric timestamp
   - Set filename pattern to `{{id}} {{slug title}}`
   - Set link format to wiki
   - Enable LSP diagnostics (dead-link = error, wiki-title = hint)

4. **Write templates to .zk/templates/**
   Create six template files:
   - `default.md` — Permanent note template (fallback)
   - `fleeting.md` — Inbox fleeting note with minimal frontmatter
   - `literature.md` — Literature note with source field and Summary/Key Points/Relevance sections
   - `permanent.md` — Permanent note with Links section
   - `decision.md` — ADR with Context/Decision/Consequences/Links sections and status field
   - `index.md` — Map of Content with Notes section

   Each template MUST include YAML frontmatter with: id, title, type, created, author, tags.
   The `author` field SHOULD default to the provided author input.

5. **Commit the scaffold**
   ```bash
   cd "$notes_path"
   git add .zk/ inbox/ literature/ notes/ decisions/ index/
   git commit -m "chore(notes): scaffold Zettelkasten structure"
   ```
   - If there are no changes to commit (idempotent run), skip the commit

## Output Format

### config_toml

The `.zk/config.toml` file path. Confirm it exists and is valid TOML.

## Quality Criteria

- All five note directories exist: `inbox/`, `literature/`, `notes/`, `decisions/`, `index/`
- `.zk/config.toml` exists with correct group configuration
- All six templates exist in `.zk/templates/`
- Templates contain valid YAML frontmatter with required fields
- Changes are committed (or no changes needed)

## Context

This is the first step in the `init` workflow. The `seed` step depends on this completing successfully to create initial index notes. This step can also be run standalone to repair a partially scaffolded repo.
