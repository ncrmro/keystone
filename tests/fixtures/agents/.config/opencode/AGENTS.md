# Keystone session

- Development mode: disabled
- Available Keystone capabilities: ks, notes, project, engineer, product, project-manager
- Published Keystone commands: ks.system, ks.notes, ks.projects, ks.engineer, ks.product, ks.pm

# Available skills

Use these skills to load domain-specific knowledge and workflows on demand.
Each skill brings its own conventions, role definitions, and DeepWork routing.

- **/ks.system** — Keystone system — may start keystone_system/issue or keystone_system/doctor
- **/ks.notes** — Notes workflows — may start notes/process_inbox, notes/doctor, notes/init, or notes/setup
- **/ks.projects** — Project workflows — may start project/onboard, project/press_release, project/milestone, project/milestone_engineering_handoff, or project/success
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

- [process.version-control](/repo/conventions/process.version-control.md)
- [process.privileged-approval](/repo/conventions/process.privileged-approval.md)
- [process.prose](/repo/conventions/process.prose.md)
- [tool.standard-utilities](/repo/conventions/tool.standard-utilities.md)
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
- [process.git-repos](/repo/conventions/process.git-repos.md)
- [process.vcs-context-continuity](/repo/conventions/process.vcs-context-continuity.md)