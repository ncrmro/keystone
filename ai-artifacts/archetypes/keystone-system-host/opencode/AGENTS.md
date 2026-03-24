# Keystone Conventions

Archetype: **keystone-system-host**
NixOS host — Nix devshells, direnv, declarative config

---


## Version Control

## Pre-Commit Hygiene

1. Before committing, the working tree MUST be checked for files that should be gitignored (e.g., `.env`, `node_modules/`, build artifacts).
2. `git status` MUST be reviewed before every commit to verify only intended files are staged.
3. Files matching `.gitignore` patterns MUST NOT be committed — if they appear in status, the `.gitignore` MUST be fixed first.

## Conventional Commits

4. Commit messages MUST follow the Conventional Commits format: `type(scope): subject`.
5. Valid types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`, `build`.
6. The scope SHOULD identify the affected area (e.g., `backend`, `frontend`, `nix`, `ci`).
7. PR titles MUST also follow the `type(scope): subject` format.
8. The subject SHOULD match an existing spec, milestone, or issue name — avoid introducing new subjects when an existing one fits.

## Commit Discipline

9. Commits MUST be early and often — each commit SHOULD represent one logical change.
10. Dependency additions or updates MUST be in their own dedicated commit (e.g., `chore(deps): add serde`).
11. When doing TDD, the failing test MUST be committed separately from the implementation that makes it pass.
12. Commits MUST NOT bundle unrelated changes — split them into separate commits.

## Cloning Repositories

15. Repos MUST be cloned to `.repos/{owner}/{repo}` relative to the agent-space root — never to the home directory or agent-space root.
16. Internal Forgejo repos MUST use SSH URLs: `git clone ssh://forgejo@git.ncrmro.com:2222/{owner}/{repo}.git .repos/{owner}/{repo}`.
17. GitHub repos MUST use `gh repo clone {owner}/{repo} .repos/{owner}/{repo}`.
18. Full clones MUST be used — do NOT use `--depth 1` unless explicitly requested.
19. The `.repos/` directory MUST be gitignored.

## Rebasing & Lock Files

For rebase conflict resolution, lockfile handling, and advanced git operations, see `process.version-control-advanced`.

---

# Convention: Writing and Prose (process.prose)

Standards for writing clear, concise, and professional prose across all project
communications, including issues, notes, and general documentation.

## Clarity and Conciseness

1. Prose MUST be succinct, delivering maximum information with minimum words.
2. Prose MUST prioritize clarity and ease of understanding.
3. Sentences SHOULD be short and direct. Avoid unnecessary complexity.
4. Passive voice SHOULD NOT be used when the subject of the action is known.
   Bad: "The report was finished by the team."
   Good: "The team finished the report."
5. Filler words and phrases (e.g., "basically", "actually", "at this point in time", "in order to") SHOULD NOT be used.

## Grammar and Punctuation

6. The Oxford comma (serial comma) MUST be used for all lists of three or more items to ensure unambiguous separation.
7. American English spelling MUST be used (e.g., "organization" not "organisation").
8. Punctuation MUST be placed inside quotation marks in narrative text.

## Formatting and Structure

9. All narrative text MUST be formatted using Markdown.
10. Titles and headings MUST use sentence case (e.g., "Weekly status update" not "Weekly Status Update").
11. Dates MUST follow the ISO 8601 format (YYYY-MM-DD) or use full month names (e.g., "March 23, 2026") to avoid regional ambiguity.
12. Large blocks of text SHOULD be broken up with lists or sub-headings to improve readability.

## Tone and Accessibility

13. The tone MUST be professional, objective, and helpful.
14. Gender-neutral language MUST be used (e.g., "they/them" instead of "he/she").
15. Narrative SHOULD avoid unnecessary jargon or obscure metaphors.

## Golden Example

### Topic: System Migration Schedule

The migration to the new storage backend will occur over three days to minimize
service interruptions.

#### Schedule

1. Infrastructure preparation MUST be completed by 2026-04-01.
2. Data synchronization SHOULD begin immediately following the preparation.
3. The final cutover MUST NOT occur until all synchronization tasks are verified.

#### Communication

We will notify all stakeholders via email, the project board, and the internal
chat system once the migration is complete.

---

# Convention: Standard Utilities (tool.standard-utilities)

Standards for using common Unix and development utilities (`jq`, `yq`, `rg`, `sed`, `awk`) within the keystone environment. These tools are pre-installed on all keystone hosts.

## JSON Processing (jq)

1. `jq` MUST be used for parsing and filtering JSON output from APIs and CLI tools.
2. Complex `jq` filters SHOULD be broken into multiple pipes for readability.
3. For scripts, use the `-r` (raw-output) flag when extracting string values to avoid unwanted quotes.
4. `jq` filters MUST handle missing keys gracefully using the `?` operator or `//` default values.

## YAML Processing (yq)

5. `yq` (mikefarah/yq) MUST be used for YAML manipulation in scripts and CI/CD pipelines.
6. When converting YAML to JSON for further processing with `jq`, use `yq -o=json eval '.'`.
7. In-place edits with `yq -i` MUST be backed up or performed within a git-tracked directory to allow for reversal.

## Searching (rg/ripgrep)

8. `rg` (ripgrep) MUST be the primary tool for searching text within files.
9. For searching code, use the `--type` flag (e.g., `rg --type nix`) to narrow results and improve performance.
10. `rg` SHOULD be used with `--hidden` to include hidden files (e.g., `.env`, `.github/`) and `--no-ignore` if searching ignored files is necessary.
11. Large search results SHOULD be piped to `head` or `less` to avoid overwhelming the terminal or agent context.

## Text Processing (sed/awk)

12. `sed` and `awk` SHOULD only be used for simple stream edits where `jq` or `yq` are not applicable.
13. For complex text transformations, prefer specialized tools or small script fragments (Bash/Python) over intricate `sed`/`awk` one-liners.
14. `sed` commands MUST use a delimiter other than `/` if the pattern contains slashes (e.g., `sed 's|/old/path|/new/path|'`).

## Performance and Safety

15. Tools MUST NOT be used on binary files unless specifically designed for them.
16. For large-scale find-and-replace, use `git grep` or `rg` with `xargs` to ensure safety and speed.
17. Avoid piping secrets or sensitive data into these utilities unless the output is immediately redirected to a secure location.

## Environment and Tool Availability

18. Projects SHOULD utilize Nix devshells (`nix develop`) to provide required tools when possible. In repositories where introducing Nix configuration is undesirable, tools MUST be provided by the pre-installed host environment or a local untracked shell. See `tool.nix-devshell` for standards on project-specific environments.

---

<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->
# Convention: VCS Context Continuity (process.vcs-context-continuity)

Standards for maintaining real-time visibility and state tracking on issues and 
pull requests to ensure that any agent or human can seamlessly resume 
in-flight work.

## Real-Time Progress Tracking

1. The `# Tasks` checklist in the PR body (or Issue body) MUST be updated 
   immediately as each sub-task is completed.
2. If the implementation plan changes or a sub-task is found to be 
   unnecessary, the checklist MUST be updated to reflect the new path.
3. If a task is skipped or pivoted, a brief comment MUST explain why the 
   change was made.

## Environmental and Technical Blockers

4. Any difficulties encountered with the development environment (e.g., 
   missing dependencies, flakey tests, Nix evaluation errors) MUST be 
   documented as a comment on the tracking Issue or PR. See `process.blocker` 
   for the authoritative standard on escalating blockers.
5. If a "workaround" or temporary hack is required to proceed, it MUST be 
   explicitly noted so the next agent understands the non-standard setup.
6. System-level issues that affect the developer experience (DX) SHOULD be 
   reported as separate infrastructure issues while referencing the current 
   task.

## Observable Evidence

7. Every PR MUST provide observable evidence of progress (screenshots for 
   UI, terminal output code blocks for CLI, or video for complex interactions).
   See `tool.terminal-screenshots` for specific PNG rendering standards.
8. Evidence MUST be updated if subsequent changes significantly alter the 
   observable behavior of the feature.
9. For backend or library changes, the demo MUST include logs or test output 
   demonstrating the code working in a realistic scenario. See `process.pull-request` 
   for structural PR requirements.

## Resumability and State

10. The PR/Issue history MUST provide enough context for another agent to 
    understand the current delta between the stated Goal and the current 
    branch state. See `process.task-tracking` for internal state standards.
11. Before pausing work, the agent MUST ensure all local changes are pushed 
    to the remote branch and the platform (Issue/PR) accurately reflects 
    the current progress.

## Golden Example

An agent is implementing a new UI component but hits a build issue:

### PR Body Update:
    # Tasks
    - [x] Create component scaffold
    - [x] Implement theme support
    - [ ] Add interaction tests
    - [ ] Update documentation

### Comment on PR:
    ## Technical Note: Build Environment
    
    The local `node_modules` required a manual `pnpm install --force` due to 
    a version conflict in the shared archetype. I have noted this in the 
    `# Tasks` for anyone picking up the next sub-task.
    
    ## Progress Demo
    ![Screenshot of the component in light and dark mode](https://example.com/demo.png)
    
    The interaction tests are currently failing because the test-runner cannot 
    find the new fonts; I have pushed my WIP fixes to the branch.

---

## Reference Conventions

The following conventions are available for on-demand context:

- [os.requirements](conventions/os.requirements.md)
- [tool.nix-devshell](conventions/tool.nix-devshell.md)
- [tool.nix](conventions/tool.nix.md)
- [code.shell-scripts](conventions/code.shell-scripts.md)
- [tool.bitwarden](conventions/tool.bitwarden.md)
- [tool.himalaya](conventions/tool.himalaya.md)
- [tool.forgejo](conventions/tool.forgejo.md)
- [tool.github](conventions/tool.github.md)
- [tool.zk](conventions/tool.zk.md)
- [process.notes](conventions/process.notes.md)
- [tool.zk-notes](conventions/tool.zk-notes.md)
- [process.enable-by-default](conventions/process.enable-by-default.md)
- [os.zfs-backup](conventions/os.zfs-backup.md)
- [tool.stalwart](conventions/tool.stalwart.md)
- [tool.standard-utilities](conventions/tool.standard-utilities.md)
