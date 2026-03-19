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

Agent discovers a missing Nix package while implementing a task on `ncrmro/catalyst`:

```bash
# 1. Agent hits blocker: `wrangler` not available in devshell
#    Error: "command not found: wrangler"

# 2. File blocker issue on keystone (rule 5)
gh issue create --repo ncrmro/keystone \
  --title "fix(devshell): add wrangler to agent-drago devshell" \
  --label "blocked" \
  --assignee ncrmro \
  --body "$(cat <<'EOF'
## What is blocked

[Issue #42](https://github.com/ncrmro/catalyst/issues/42) — deploy Cloudflare Worker.
Task cannot proceed because `wrangler` CLI is not available in the agent's Nix devshell.

## Root cause

`wrangler` (Cloudflare Workers CLI) is not included in the agent-drago
devshell packages in `modules/agents/drago.nix`.

## Error evidence

```
$ wrangler deploy
zsh: command not found: wrangler
```

## Suggested fix

Add `pkgs.wrangler` to `devShells.default.buildInputs` in the agent's
Nix module, then rebuild.
EOF
)"

# 3. Label the original task issue as blocked (rule 9)
gh issue edit 42 --repo ncrmro/catalyst --add-label "blocked"

# 4. Comment on the original task issue (rule 13)
gh issue comment 42 --repo ncrmro/catalyst \
  --body "Blocked by ncrmro/keystone#NEW — wrangler CLI not in devshell."

# 5. Move task board item to Backlog (rule 10)
# gh project item-edit ...

# 6. Update TASKS.yaml (rule 11)
# status: blocked, blocker_ref: https://github.com/ncrmro/keystone/issues/NEW

# --- After the human merges the keystone fix and rebuilds ---

# 7. Verify fix (rule 15)
which wrangler  # confirms wrangler is now available

# 8. Resume (rule 16)
gh issue edit 42 --repo ncrmro/catalyst --remove-label "blocked"
# Update TASKS.yaml status: pending
# Move board item to "To Do"
# Task picked up in next task loop run
```
