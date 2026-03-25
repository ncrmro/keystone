# Verify Initialization

## Objective

Confirm the notebook structure is valid and functional.

## Task

1. Run `zk --notebook-dir <notes_path> index` — should complete without errors.

2. Test each group resolves:
   ```bash
   zk --notebook-dir <notes_path> list inbox/ --format json 2>&1
   zk --notebook-dir <notes_path> list literature/ --format json 2>&1
   zk --notebook-dir <notes_path> list notes/ --format json 2>&1
   zk --notebook-dir <notes_path> list decisions/ --format json 2>&1
   zk --notebook-dir <notes_path> list reports/ --format json 2>&1
   zk --notebook-dir <notes_path> list index/ --format json 2>&1
   zk --notebook-dir <notes_path> list archive/ --format json 2>&1
   ```
   Each should return an empty array or results — no errors.

3. Test template creation for each group:
   ```bash
   zk --notebook-dir <notes_path> new inbox/ --title "Test fleeting" --no-input --print-path --dry-run
   ```
   If `--dry-run` is not supported, create a test note, verify frontmatter, then delete it.

4. Verify the index notes from the seed step exist and have valid frontmatter.

5. Verify the root `.gitignore` exists and contains required entries for:
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

   Also verify `TASKS.yaml`, `PROJECTS.yaml`, and `SCHEDULES.yaml` are not ignored.

## Output Format

Write `init_report.md`:

```markdown
# Initialization Report

## Index Status
- `zk --notebook-dir <notes_path> index`: OK (N notes indexed)

## Group Resolution
| Group | Status | Note Count |
|-------|--------|------------|
| inbox | OK | 0 |
| literature | OK | 0 |
| notes | OK | 0 |
| decisions | OK | 0 |
| reports | OK | 0 |
| index | OK | 3 |
| archive | OK | 0 |

## Template Verification
- fleeting: OK (id, title, type, created, author, tags present)
- literature: OK (includes source, source_url)
- permanent: OK
- decision: OK (includes status, supersedes)
- report: OK (includes project, report_kind, source_ref)
- index: OK (includes index tag)

## Gitignore Verification
- root .gitignore: present
- required ignore patterns: OK
- TASKS.yaml / PROJECTS.yaml / SCHEDULES.yaml: not ignored

## Overall: PASS
```
