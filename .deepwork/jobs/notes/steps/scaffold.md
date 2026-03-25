# Scaffold Notebook

## Objective

Create the `.zk/` configuration, templates, and directory structure for a Zettelkasten notebook.

## Task

1. Check if `.zk/` already exists at the target path. If it does, skip initialization and report "already scaffolded."

2. Run `zk init --no-input <notes_path>` to create the `.zk/` directory.

3. Write `.zk/config.toml` with the canonical configuration:
   - Note ID format: `{{format-date now '%Y%m%d%H%M'}}`
   - Filename pattern: `{{id}} {{slug title}}`
   - Wikilink format enabled
   - Groups configured: fleeting (inbox/), literature (literature/), permanent (notes/), decision (decisions/), report (reports/), index (index/), archive (archive/)
   - Each group maps to its template file

4. Create `.zk/templates/` with six template files:
   - `fleeting.md` — Minimal: id, title, type, created, author, tags, then content
   - `literature.md` — Includes source, source_url fields + Summary/Key Points/Links sections
   - `permanent.md` — Single idea + Links section
   - `decision.md` — Includes status, supersedes fields + Context/Decision/Consequences/Links sections
   - `report.md` — Includes project, report_kind, source_ref, previous_report + Findings/Actions sections
   - `index.md` — Includes project tag support + sections for objective, reports, decisions, and queries

5. Create a root `.gitignore` with at least these entries:
   - `.zk/notebook.db`
   - `.zk/notebook.db-journal`
   - `.direnv/`
   - `.env`
   - `.env.local`
   - `.venv/`
   - `__pycache__/`
   - `result`
   - `result-*`
   - `.DS_Store`
   - `Thumbs.db`

   The `.gitignore` MUST NOT ignore `TASKS.yaml`, `PROJECTS.yaml`, `SCHEDULES.yaml`,
   `.zk/config.toml`, or `.zk/templates/`.

6. Create note directories with `.gitkeep` files:
   - `inbox/`
   - `literature/`
   - `notes/`
   - `decisions/`
   - `reports/`
   - `index/`
   - `archive/`

7. Verify with `zk --notebook-dir <notes_path> index` — should complete without errors.

## Output Format

Write `scaffold_report.md` listing every file and directory created, e.g.:

```markdown
# Scaffold Report

## Created
- .zk/config.toml
- .gitignore
- .zk/templates/fleeting.md
- .zk/templates/literature.md
- .zk/templates/permanent.md
- .zk/templates/decision.md
- .zk/templates/report.md
- .zk/templates/index.md
- inbox/.gitkeep
- literature/.gitkeep
- notes/.gitkeep
- decisions/.gitkeep
- reports/.gitkeep
- index/.gitkeep
- archive/.gitkeep

## Verification
- `zk --notebook-dir <notes_path> index`: OK
```

## Important Notes

- Do NOT modify existing files (TASKS.yaml, PROJECTS.yaml, SCHEDULES.yaml, SOUL.md, AGENTS.md)
- If the repo has an existing `.zk/` directory, report it and skip — do not overwrite
- Template content uses `zk` template syntax (`{{id}}`, `{{title}}`, `{{format-date ...}}`, `{{env "USER"}}`)
