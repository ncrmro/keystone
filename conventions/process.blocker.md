<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->
# Convention: Blocker Escalation (process.blocker)

This convention defines how agents identify, report, and recover from platform and infrastructure blockers that prevent task completion.

## Identifying Blockers

1. A blocker MUST be declared when an agent cannot proceed due to a platform, infrastructure, or ops issue outside the task's feature scope.
2. Blocker categories include:
   - **Keystone OS**: missing package, config change, service misconfiguration, environment issue.
   - **Project ops**: broken CI pipeline, dependency conflict, build tooling failure, database migration issue.
   - **External dependency**: upstream bug or incompatibility in a public repo that affects our project.
3. Blockers MUST NOT be declared for feature-scope issues — implementation failures are task failures (max 3 attempts per `process.feature-delivery`), not blockers.

## Filing Blocker Issues

4. Blocker issues MUST be filed in a repo we control — never directly in external or public repos.
5. Target repo MUST be selected as follows:
   - Keystone OS issues → `ncrmro/keystone`.
   - Project-specific ops issues → the project's own repo.
   - External dependency issues → our repo that depends on it, with a reference to the upstream repo.
6. The issue title MUST follow conventional format: `fix(scope): description of blocker`.
7. The issue body MUST include:
   - **What is blocked**: link to the task, PR, or issue that cannot proceed.
   - **Root cause**: the platform or infra problem preventing progress.
   - **Error evidence**: error messages, log excerpts, or reproduction steps.
   - **External reference** (if applicable): link to the public repo, upstream issue, or relevant documentation.
   - **Suggested fix** (if known): what change would unblock the agent.

## Labeling and Board Management

8. The blocker issue MUST be labeled `blocked`.
9. The original task's issue (if it has one) MUST also be labeled `blocked`.
10. The original task's project board item MUST be moved to "Backlog" per `process.project-board`.
11. TASKS.yaml MUST be updated: set the blocked task's status to `blocked` with a `blocker_ref` noting the blocker issue URL.

## Handoff and Notification

12. The blocker issue MUST be assigned to the appropriate person — Keystone OS issues to the human operator (see `TEAM.md`), project ops issues to the repo owner.
13. A comment MUST be posted on the blocked task's issue (if it has one) linking to the blocker issue and explaining the dependency.
14. The agent SHOULD send a brief email notification to the assignee via himalaya per `tool.himalaya`.

## Resuming After Unblock

15. When a blocker issue is closed, the agent MUST verify the fix is available in the environment before resuming.
16. After verification, the agent MUST:
   - Update the task's status from `blocked` to `pending` in TASKS.yaml.
   - Remove the `blocked` label from the original task's issue.
   - Move the task's project board item to "To Do" per `process.project-board`.
17. The task SHOULD be picked up in the next task loop iteration.
18. Agents SHOULD monitor blocker issues for resolution by checking issue status during task loop runs.

## Golden Example

Agent running inside an `agentctl` podman container cannot access the host's GitHub
token, blocking issue creation for task #42 on `ncrmro/catalyst`:

```bash
# 1. Agent hits blocker: gh CLI fails inside podman container
#    Error: "gh: authentication required — run gh auth login"
#    The container does not have access to the host's gh auth token.

# 2. File blocker issue on keystone (rule 5)
gh issue create --repo ncrmro/keystone \
  --title "fix(agentctl): mount gh auth token into podman container" \
  --label "blocked" \
  --assignee ncrmro \
  --body "$(cat <<'EOF'
## What is blocked

[Issue #42](https://github.com/ncrmro/catalyst/issues/42) — agent cannot
create issues or PRs from inside the agentctl podman container.

## Root cause

The agentctl podman container does not mount the host's GitHub CLI
auth token (`~/.config/gh/hosts.yml`). The `gh` CLI inside the
container has no credentials and cannot authenticate to GitHub.

## Error evidence

```
$ gh issue create --repo ncrmro/catalyst --title "test"
error: authentication required
hint: run `gh auth login` to authenticate
```

## Suggested fix

Mount the host's gh config into the container read-only:
`-v ~/.config/gh:/home/agent/.config/gh:ro`
in the agentctl podman run command.
EOF
)"

# 3. Label the original task issue as blocked (rule 9)
gh issue edit 42 --repo ncrmro/catalyst --add-label "blocked"

# 4. Comment on the original task issue (rule 13)
gh issue comment 42 --repo ncrmro/catalyst \
  --body "Blocked by ncrmro/keystone#NEW — gh auth not available in agentctl container."

# 5. Move task board item to Backlog (rule 10)
# gh project item-edit ...

# 6. Update TASKS.yaml (rule 11)
# status: blocked, blocker_ref: https://github.com/ncrmro/keystone/issues/NEW

# --- After the human merges the keystone fix and rebuilds ---

# 7. Verify fix (rule 15)
gh auth status  # confirms gh is now authenticated inside container

# 8. Resume (rule 16)
gh issue edit 42 --repo ncrmro/catalyst --remove-label "blocked"
# Update TASKS.yaml status: pending
# Move board item to "To Do"
# Task picked up in next task loop run
```
