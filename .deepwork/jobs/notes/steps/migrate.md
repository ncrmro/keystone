# Execute Migration

## Objective

Execute the migration plan: add frontmatter, assign IDs, move files to correct directories, and convert links. The execution model is determined during planning — do not create one commit per migrated file.

## Execution modes

Before mutating any files, confirm the execution mode recorded in the migration plan:

- **No-commit mode**: Apply all mutations to the working tree and do not create any git commits. Reversibility is provided by `git diff` and the migration log. Use this when the notes repo is a Keystone-managed main checkout that must stay on `main`.
- **Logical-batch mode**: Group mutations into a small number of phase-based commits (e.g., one commit for structure moves, one for frontmatter, one for link rewrites). Each commit covers a cohesive migration phase rather than a single file. Use this when the notes repo is a personal, non-Keystone-managed checkout, or when the operator has checked out a dedicated migration worktree per `process.git-repos`.
- **Worktree mode**: Create a git worktree at `~/.worktrees/<owner>/<repo>/<branch>/` (per `process.git-repos`), apply all mutations there, then open a PR. Use this when the notes repo IS a Keystone-managed checkout and the operator wants a reviewable commit history.

**Keystone main-checkout detection**: If the current working directory is the primary checkout of a Keystone-managed repo (i.e., `git rev-parse --abbrev-ref HEAD` returns `main` and the repo appears under `~/repos/<owner>/<repo>/`), the workflow MUST NOT create per-file or ad-hoc implementation commits directly in that directory. Switch to no-commit mode or create a worktree before proceeding.

## Task

1. **Read the migration plan** from `migration_plan.md`. Confirm the execution mode and phase boundaries.

2. **For each file to migrate**, execute in order:

   a. **Format-specific content conversion** (before frontmatter/move):
   - **Obsidian callouts**: Keep as-is (`> [!type]` is widely supported)
   - **Dataview queries**: Wrap in HTML comment with TODO marker:
     ````
     <!-- TODO: dataview query removed during migration
     ```dataview
     LIST FROM #tag
     ```
     -->
     ````
   - **Apple Notes HTML**: Strip HTML tags, preserve text content:
     ```bash
     sed -i 's/<br>/\n/g; s/<[^>]*>//g' "$file"
     ```
   - **Obsidian inline tags**: Extract `#tag-name` from body text, add to frontmatter tags array, remove from body

   b. **Add/update YAML frontmatter**:
   - Insert `---` delimiters if absent
   - Add required fields: id, title, type, created, author, tags
   - Preserve any existing frontmatter fields
   - **Obsidian**: Keep `aliases` field if present

   c. **Rename and move the file**:
   - New filename: `{id} {title-slug}.md`
   - Move to target directory (inbox/, literature/, notes/, decisions/, index/, or reports/)

   d. **Convert links** (if applicable):
   - Standard markdown links to local files: `[text](file.md)` -> `[[id]]`
   - Obsidian wikilinks by filename: `[[filename]]` -> `[[id]]` (match by old filename)
   - Obsidian embeds: `![[filename]]` -> `![[id]]`
   - Update links in OTHER files that reference this file's old path

   e. **Normalize VCS ref fields** (from the migration plan's ref normalization list):
   - Rename non-standard fields to canonical names (`issue_ref`, `pr_ref`, `milestone_ref`, `repo_ref`)
   - Convert raw GitHub/Forgejo URLs to `gh:<owner>/<repo>#<N>` / `fj:<owner>/<repo>#<N>` format
   - Convert bare issue/PR numbers to include the repo prefix, deriving the repo from `repo_ref` in the same frontmatter or from the project hub note
   - Preserve all other frontmatter fields — this is a rename+reformat only, no content deletion
   - Example transformation:
     ```yaml
     # Before
     issue: 225
     repo: https://github.com/ncrmro/keystone

     # After
     repo_ref: gh:ncrmro/keystone
     issue_ref: gh:ncrmro/keystone#225
     ```

   f. **Apply project ownership tags where the evidence is strong**:
   - Derive project names and aliases from project hub notes in `index/`
   - Search with `rg` or `scripts/find_missing_project_tags.py` to find migrated files that mention a project but still lack that project tag
   - Add the missing project tag when the file has a clear project owner
   - Leave ambiguous ownership untouched and record it in the migration log instead of guessing

   g. **Respect project hub and spike conventions**:
   - Keep project hub notes in `index/`
   - If the repo uses root spike trees, keep `spikes/<slug>/README.md` as the canonical spike note
   - Do not force spike support docs such as `scope.md`, `research.md`, or `prototype/README.md` into `notes/` just because they are markdown
   - If `.zk/config.toml` intentionally ignores spike support docs, preserve that behavior

   h. **Record the transformation** in the migration log (no git commit needed at this point):
   - Add a row to the Transformations table in `.deepwork/tmp/migration_log.md`
   - Note the execution mode and phase boundary if a commit will be created at the end of this phase

3. **Commit boundaries** (logical-batch or worktree mode only):
   - Commit at natural phase boundaries, not per file. Suggested phases:
     1. `chore(notes): move files to canonical groups` — all renames and directory moves
     2. `chore(notes): add frontmatter and IDs` — all frontmatter additions
     3. `chore(notes): convert links and normalize VCS refs` — link rewrites and ref field normalization
     4. `chore(notes): apply project tags and clean up artifacts` — tag additions, artifact removal
   - Fewer, larger commits are preferred over many small ones. Merge phases when they touch the same files.
   - In no-commit mode, skip all git commands — mutations accumulate in the working tree only.

4. **Large repos** (> 500 files):
   - Group files by source directory when processing
   - After each batch of 50 files, run `zk index` as a sanity check
   - If errors, stop and report — do not continue with broken state
   - In logical-batch mode, still commit at phase boundaries — not per batch

5. **After all files are migrated**, in logical-batch or worktree mode, do a final commit for any remaining changes (e.g., deleted empty directories, updated cross-references).

6. **Clean up format artifacts** (final pass):
   - Remove `.obsidian/` directory if present (commit separately: `chore(notes): remove obsidian config`)
   - Remove Apple Notes export artifacts (empty attachment dirs, etc.)
   - Do NOT remove `.deepwork/`, `.claude/`, or other tool directories

7. **Resolve legacy note trees**:
   - Revisit every noncanonical directory identified in the migration plan
   - Migrate all note-like markdown into canonical zk groups unless the plan explicitly marked that subtree as operational residue
   - If a directory still exists afterward, it should contain only operational/generated files or non-markdown assets
   - If note-like markdown remains outside canonical groups, the migration is incomplete
   - Root `spikes/` is allowed when the plan marked it as a canonical spike-note convention rather than a legacy tree

## Output Format

Write `.deepwork/tmp/migration_log.md`:

```markdown
# Migration Log

## Execution Mode

(no-commit / logical-batch / worktree — from migration plan)

## Source Format

(Obsidian / Apple Notes / Plain Markdown)

## Transformations

| #   | Old Path              | New Path                            | Type      | ID           | Phase          |
| --- | --------------------- | ----------------------------------- | --------- | ------------ | -------------- |
| 1   | journal/2026-03-15.md | notes/202603151200 daily-journal.md | permanent | 202603151200 | structure-move |

## Format-Specific Conversions

- Dataview blocks commented out: N
- HTML tags stripped: N
- Inline tags extracted: N
- Obsidian callouts preserved: N

## VCS Ref Field Normalization

- Files with ref fields normalized: N
- Field renames applied: (e.g., `issue:` → `issue_ref:`, N files)
- URL-to-prefix conversions: (e.g., `https://github.com/...` → `gh:...`, N files)
- Bare-number expansions: N files

## Project Tag Updates

- Files given missing project tags: N
- Ambiguous project-tag candidates left for manual review: N

## Commits Created

(logical-batch/worktree mode only — list phase commits with hashes; "N/A (no-commit mode)" otherwise)

## Summary

- Files migrated: N
- Commits created: N (or 0 for no-commit mode)
- Errors: 0
```

## Important Notes

- NEVER use one commit per migrated file — this creates commit spam and conflicts with Keystone worktree safety rules
- In no-commit mode, mutations are reversible via `git checkout -- .` or `git diff` inspection — the migration log is the detailed reversibility record
- NEVER delete note content — only add frontmatter, rename, and move
- Preserve existing frontmatter fields — merge, don't replace
- Skip operational files (TASKS.yaml, SOUL.md, SOUL.md, PROJECTS.yaml, SCHEDULES.yaml, AGENTS.md, etc.) entirely
- If a file already conforms to the standard, skip it and note "already compliant" in the log
- Obsidian callouts are PRESERVED — they are valid markdown
- Prefer `rg` over `grep` when searching for project-name matches and old link paths
- The migration log is transient workflow state. Store it under `.deepwork/tmp/` and do not commit it.
- Do not declare success while `projects/`, `workflow/`, `spikes/`, or similar legacy directories still contain note-like markdown that should have been migrated.
