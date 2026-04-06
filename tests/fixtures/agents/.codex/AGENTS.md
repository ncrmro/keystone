# Available skills

Each skill loads domain-specific conventions and DeepWork workflows on demand.

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