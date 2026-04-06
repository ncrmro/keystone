# Keystone session

- Development mode: disabled
- Available Keystone capabilities: ks, notes, project, engineer, product, project-manager
- Published Keystone commands: ks, ks.notes, ks.projects, ks.engineer, ks.product, ks.pm

# Available skills

Use these skills to load domain-specific knowledge and workflows on demand.
Each skill brings its own conventions, role definitions, and DeepWork routing.

- **/ks** — Keystone assistant — may start keystone_system/issue or keystone_system/doctor
- **/ks.notes** — Notes workflows — may start notes/process_inbox, notes/doctor, notes/init, or notes/setup
- **/ks.projects** — Project workflows — may start project/onboard, project/press_release, or project/success
- **/ks.engineer** — Engineering — implementation, code review, architecture, and CI
- **/ks.product** — Product — planning, milestones, stakeholder communication
- **/ks.pm** — Project management — task decomposition, tracking, and boards

# Shared-surface tracking

- For issue-backed work, post `Work Started` and `Work Update` comments on the source issue.
- Treat issues, pull requests, milestones, and boards as the canonical public record.
- Use notes for durable rationale and memory, not to replace shared-surface tracking.

# Privileged operations

- Ask for permission before running `ks update`, `ks switch`, or other host-mutating commands.
- Include the exact command, target host, and reason in the request.

# Commit format

- Use Conventional Commits: `type(scope): subject`.
- Valid types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`, `build`.
- Each commit SHOULD represent one logical change.

# Notes

- Route note capture and notebook repair through `/ks.notes`.
- Use `NOTES_DIR` as the canonical notebook root.

# Reference conventions

The following conventions are available for on-demand context:

- [process.version-control](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/process.version-control.md)
- [process.privileged-approval](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/process.privileged-approval.md)
- [process.prose](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/process.prose.md)
- [tool.standard-utilities](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/tool.standard-utilities.md)
- [os.requirements](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/os.requirements.md)
- [tool.nix-devshell](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/tool.nix-devshell.md)
- [tool.nix](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/tool.nix.md)
- [code.shell-scripts](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/code.shell-scripts.md)
- [process.grafana-dashboard-development](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/process.grafana-dashboard-development.md)
- [tool.bitwarden](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/tool.bitwarden.md)
- [tool.himalaya](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/tool.himalaya.md)
- [tool.forgejo](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/tool.forgejo.md)
- [tool.github](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/tool.github.md)
- [process.issue-journal](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/process.issue-journal.md)
- [tool.zk](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/tool.zk.md)
- [process.notes](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/process.notes.md)
- [process.project-board](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/process.project-board.md)
- [process.presentation-slides](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/process.presentation-slides.md)
- [tool.zk-notes](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/tool.zk-notes.md)
- [process.enable-by-default](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/process.enable-by-default.md)
- [os.zfs-backup](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/os.zfs-backup.md)
- [tool.stalwart](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/tool.stalwart.md)
- [process.git-repos](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/process.git-repos.md)
- [process.vcs-context-continuity](/home/ncrmro/.worktrees/ncrmro/keystone/skill-composition/conventions/process.vcs-context-continuity.md)