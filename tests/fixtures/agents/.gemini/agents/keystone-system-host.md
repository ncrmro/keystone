---
name: "keystone-system-host"
description: "Keystone archetype agent for keystone-system-host. Use when you want this role without impersonating a specific OS agent."
---

# Keystone Archetype Agent: keystone-system-host

Archetype: **keystone-system-host**
NixOS host — Nix devshells, direnv, declarative config

---

## Agent context

- Identity kind: archetype
- Archetype: keystone-system-host
- Development mode: disabled
- You are a reusable Keystone archetype agent, not a concrete OS-agent identity.
- Do not claim another agent's notebook, host, or personal history unless the user provides that context explicitly.

---

## Version Control

## Pre-Commit Hygiene

Before committing, ensure the working tree is clean and matches the intended state. For strategic guidance on searching project history and discovering requirements using git tools, see `process.project-navigation`.

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

# Convention: Git repos (process.git-repos)

This convention standardizes where repositories are cloned depending on their
relationship to the Keystone platform, and how git worktrees are created and
used for active implementation work.

## Repository roots

1. Keystone-managed repositories (those defining or operating this machine's
   infrastructure) MUST keep their main checkout at
   `~/.keystone/repos/{owner}/{repo}/`.
2. `~/.keystone/repos/` MUST only contain repositories that are part of the
   Keystone system itself (e.g., `ncrmro/keystone`, `ncrmro/nixos-config`,
   `Unsupervisedcom/deepwork`). It MUST NOT be used for general project work.
3. All other (non-Keystone) repositories MUST keep their main checkout at
   `$HOME/repos/{owner}/{repo}/`.
4. The main checkout MUST remain on the default branch and serve as the anchor
   for fetch, branch creation, and worktree management.
5. Home Manager activation SHOULD ensure that `$HOME/repos/` and
   `$HOME/.worktrees/` exist before worktree-aware tooling runs.
6. Tooling SHOULD prefer the exported `CODE_DIR`, `WORKTREE_DIR`, and
   `NOTES_DIR` environment variables when it needs to discover workspace roots.

## Worktree layout

7. Implementation work MUST happen in git worktrees rooted at
   `$HOME/.worktrees/{owner}/{repo}/{branch}/`.
8. Worktrees MUST live outside the main checkout directory. Placing worktrees
   inside the repo causes problems with tools that index or glob the directory
   tree (e.g., language servers, file watchers, IDE indexers), because those
   tools are not worktree-aware and treat each worktree as part of the main
   project tree.
9. The worktree directory name MUST match the git branch name exactly.
10. Branch names MUST follow the existing version-control naming conventions.

## Creation and lifecycle

11. Worktrees MUST be created from the main checkout after fetching the latest
    remote state.
12. If the branch does not exist locally, the branch SHOULD be created from the
    appropriate base branch before adding the worktree.
13. Reusing an existing worktree for the same branch SHOULD be preferred over
    creating duplicates.
14. After a branch is merged or abandoned, the external worktree SHOULD be
    removed.

## Project session integration

15. Project tooling that launches a repo-scoped session, such as `pz` or
    `agentctl`, SHOULD resolve the repo root first and then derive the worktree
    path as `$HOME/.worktrees/{owner}/{repo}/{branch}/`.
16. When a requested worktree does not exist, tooling MAY create it if the
    command contract allows creation. Otherwise it MUST fail with a clear error.
17. Repo-scoped sessions MUST expose both the repo root and the worktree path
    in their environment when a worktree is active.

## Environment handling

18. Tools that create a new worktree SHOULD run `direnv allow` in the worktree
    when the repo uses direnv-managed environments.
19. Tooling MUST set the session working directory to the worktree path when a
    worktree is active, not the main checkout.

## Golden example

```bash
# Clone a non-Keystone project repo into the standard location
gh repo clone acme/api "$HOME/repos/acme/api"

# Create a worktree for feature work outside the repo (avoids indexing issues)
cd "$HOME/repos/acme/api"
git fetch origin
git branch feat/add-search-endpoint origin/main
git worktree add "$HOME/.worktrees/acme/api/feat/add-search-endpoint" feat/add-search-endpoint
cd "$HOME/.worktrees/acme/api/feat/add-search-endpoint"
direnv allow
```

---

# Convention: Privileged approval flow (process.privileged-approval)

Standards for requesting, approving, and executing privileged commands on
Keystone hosts. The canonical flow is terminal-first: a user or agent starts
the request from the terminal, then a local desktop approval prompt authorizes
the specific command.

This convention defines the policy and future module contract. It does not
require the approval broker to exist yet.

## Core flow

1. Privileged Keystone operations MUST use an approval-aware terminal flow,
   not an unstructured `sudo` prompt.
2. The canonical future entrypoint MUST be:
   ```bash
   ks approve --reason "<reason>" -- <command> [args...]
   ```
3. The approval flow MUST begin in the terminal or agent session that wants to
   run the command, even when the actual approval UI is desktop-visible.
4. When a graphical session is available, the system MUST show a desktop PAM or
   polkit-style approval popup for the request.
5. When no graphical session is available, the system SHOULD fall back to a
   terminal approval prompt while preserving the same command, host, and reason
   semantics.

## Dialog and execution requirements

1. The approval UI MUST show the exact command and argv that will run.
2. The approval UI MUST show the target host, or `local` when the command runs
   on the current machine.
3. The approval UI MUST show a short human-readable reason string.
4. Approval MUST be scoped to one explicit command entry. A successful approval
   MUST NOT grant broad shell access or a reusable root session.
5. The execution layer MUST reject commands that are not declared in the
   allowlist before any approval prompt is shown.

## Authentication methods

1. The approval flow MUST support password-based approval.
2. The approval flow MUST support hardware-key approval.
3. Hardware-key approval MAY require physical touch or equivalent presence
   confirmation.
4. The command policy MUST be identical regardless of whether the user approves
   with a password or a hardware key.

## Agent behavior

1. Agents MUST ask for permission in chat before requesting any privileged
   Keystone operation.
2. The request MUST include the exact command, target host, and reason.
3. Agents MUST treat `ks update`, `ks update --dev`, `ks switch`, and other
   host-mutating Keystone commands as approval-gated operations.
4. Agents MUST NOT run raw `sudo` as a substitute for the approval-aware flow
   once `ks approve` exists.
5. Until `ks approve` exists, agents MUST still ask the human before invoking
   privileged Keystone operations directly.

## Future Nix module contract

1. Keystone SHOULD expose the approval system under
   `keystone.security.privilegedApproval`.
2. The module MUST provide an `enable` option.
3. The module MUST provide a `backend` option. The initial documented backend
   SHOULD be `desktop-pam`.
4. The module MUST provide a `commands` option containing explicit allowlist
   entries.
5. Each allowlist entry MUST support these fields:
   - `name`
   - `command`
   - `displayName`
   - `reason`
   - `runAs`
   - `approvalMethods`
6. `command` MUST be an exact argv list or an explicit template, not a coarse
   per-binary grant.
7. `approvalMethods` MUST support `password` and `hardware-key`.

## Keystone command policy

1. Keystone host updates SHOULD be exposed through allowlisted commands rather
   than unrestricted shell access.
2. `ks update` MUST be treated as approval-gated.
3. `ks update --dev` MUST be treated as approval-gated.
4. `ks switch` MUST be treated as approval-gated.
5. `ks build` SHOULD remain the non-mutating verification path and SHOULD NOT
   require privileged approval by default.

## Future requirement

1. Keystone SHOULD add remote privileged approval backed by user-held secure
   hardware, such as Google Titan or Secure Enclave-backed credentials.
2. Remote approval is a TODO requirement for a future iteration and MUST NOT be
   assumed by the initial local approval design.

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

Standards for using common Unix and development utilities (`jq`, `yq`, `rg`, `sed`, `awk`) within the keystone environment. These tools are pre-installed on all keystone hosts. For strategic guidance on using these tools for project navigation and discovery, see `process.project-navigation`.

## JSON Processing (jq)

1. `jq` MUST be used for parsing and filtering JSON output from APIs and CLI tools. See `tool.process-compose-agent` Rule 5 for its application in service orchestration.
2. Complex `jq` filters SHOULD be broken into multiple pipes for readability.
3. For scripts, use the `-r` (raw-output) flag when extracting string values to avoid unwanted quotes.
4. `jq` filters MUST handle missing keys gracefully using the `?` operator or `//` default values.

## YAML Processing (yq)

5. `yq` (mikefarah/yq) MUST be used for YAML manipulation in scripts and CI/CD pipelines.
6. When converting YAML to JSON for further processing with `jq`, use `yq -o=json eval '.'`.
7. In-place edits with `yq -i` MUST be backed up or performed within a git-tracked directory to allow for reversal.

## Searching (rg/ripgrep)

8. `rg` (ripgrep) MUST be the primary tool for searching text within files. For requirement discovery using Requirement Prefixes, see `process.project-navigation`.
9. For searching code, use the `--type` flag (e.g., `rg --type nix`) to narrow results and improve performance.
10. `rg` SHOULD be used with `--hidden` to include hidden files (e.g., `.env`, `.github/`) and `--no-ignore` if searching ignored files is necessary.
11. Large search results SHOULD be piped to `head` or `less` to avoid overwhelming the terminal or agent context.

## Text Processing (sed/awk)

12. `sed` and `awk` SHOULD only be used for simple stream edits where `jq` or `yq` are not applicable.
13. For complex text transformations, prefer specialized tools or small script fragments (Bash/Python) over intricate `sed`/`awk` one-liners.
14. `sed` commands MUST use a delimiter other than `/` if the pattern contains slashes (e.g., `sed 's|/old/path|/new/path|'`).

## Performance and Safety

15. Tools MUST NOT be used on binary files unless specifically designed for them.
16. For large-scale find-and-replace, use `git grep` or `rg` with `xargs` to ensure safety and speed. For using `git grep` in project navigation and requirement discovery, see `process.project-navigation`.
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

- [os.requirements](/repo/conventions/os.requirements.md)
- [tool.nix-devshell](/repo/conventions/tool.nix-devshell.md)
- [tool.nix](/repo/conventions/tool.nix.md)
- [code.shell-scripts](/repo/conventions/code.shell-scripts.md)
- [process.grafana-dashboard-development](/repo/conventions/process.grafana-dashboard-development.md)
- [tool.bitwarden](/repo/conventions/tool.bitwarden.md)
- [tool.himalaya](/repo/conventions/tool.himalaya.md)
- [tool.forgejo](/repo/conventions/tool.forgejo.md)
- [tool.github](/repo/conventions/tool.github.md)
- [process.issue-journal](/repo/conventions/process.issue-journal.md)
- [tool.zk](/repo/conventions/tool.zk.md)
- [process.notes](/repo/conventions/process.notes.md)
- [process.project-board](/repo/conventions/process.project-board.md)
- [process.presentation-slides](/repo/conventions/process.presentation-slides.md)
- [tool.zk-notes](/repo/conventions/tool.zk-notes.md)
- [process.enable-by-default](/repo/conventions/process.enable-by-default.md)
- [os.zfs-backup](/repo/conventions/os.zfs-backup.md)
- [tool.stalwart](/repo/conventions/tool.stalwart.md)