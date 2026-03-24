
## Code Delivery

This convention defines the end-to-end lifecycle of delivering features and fixes via code changes: from milestone/issue through to merged PR. It orchestrates existing conventions rather than duplicating them.

## Upstream Dependencies

1. Feature delivery MUST originate from an issue belonging to a milestone.
2. Requirements MUST be documented as specs before implementation begins.
3. If no milestone exists, one MUST be created per `process.product-engineering-handoff`.

## Issue as Plan

4. The issue body MUST serve as the plan of record — no separate `plan.md` files.
5. The issue body MUST include a checklist of deliverables derived from the spec.
6. Large issues MUST be decomposed into sub-issues, each becoming its own branch and PR.
7. Sub-issues MUST reference the parent issue (e.g., "Part of #42").
8. The issue body SHOULD be updated as the plan evolves; comments supplement but do not replace it.

## Branch and Early PR

9. A branch MUST be created from the default branch using `process.version-control` naming conventions (semantic prefix + short description).
10. All implementation work MUST be done in a git worktree at `.repos/{owner}/{repo}/.worktrees/{branch}`. The main checkout at `.repos/{owner}/{repo}/` MUST remain on the default branch.
11. A dummy commit MUST be created immediately after branching (e.g., empty commit or minimal scaffold) to enable opening a PR.
12. A draft PR MUST be opened immediately after the dummy commit (Forgejo: `WIP:` title prefix per `tool.forgejo`; GitHub: `--draft` flag).
13. The PR body MUST include a `# Tasks` section containing the task breakdown as markdown checkboxes mirroring the issue's deliverable checklist.
14. The draft PR SHOULD make the plan visible to reviewers before implementation begins.

## PR Body Format

15. The PR body MUST follow the `process.pull-request` convention (`# Goal`, `# Changes`, `# Demo` sections) plus the `# Tasks` section from rule 13.
16. The PR title MUST follow conventional commit format per `process.version-control` (e.g., `feat(api): add search endpoint`).
17. The PR body MUST include `Closes #N` or `Fixes #N` to auto-close the originating issue on merge.

## Implementation

18. Commits MUST follow `process.version-control` commit discipline (early, often, one logical change per commit).
19. Changes MUST NOT exceed the scope of the issue's acceptance criteria.
20. All tasks in the PR body's `# Tasks` section MUST be updated in real-time as each sub-task is completed (see `process.vcs-context-continuity`). All tasks MUST be checked off before marking the PR ready for review.

## Review and Merge

21. Appropriate reviewers MUST be assigned before marking the PR ready for review.
22. Reviewers MUST be assigned per the ownership matrix in `process.code-review-ownership`. On both GitHub and Forgejo, CODEOWNERS handles automatic reviewer assignment when a PR is created or undrafted, provided the repo has branch protection requiring code owner review enabled. If auto-request is not enabled, the authoring agent MUST manually request reviewers per the ownership matrix.
23. On Forgejo, `tool.forgejo` rule 18 (repo owner as reviewer) is satisfied by including the repo owner in the CODEOWNERS file. Forgejo supports CODEOWNERS natively; no separate manual assignment is needed when CODEOWNERS is configured.
24. Copilot SHOULD also be requested as a supplementary reviewer per `process.copilot-agent`.
25. Review feedback MUST be addressed per `process.copilot-agent` conversation resolution rules (fix or explain every comment). For human reviewer feedback, agents MUST also follow `process.pr-review-response` for the full response lifecycle (fetch comments, push fixes, reply, re-request review).
26. PRs MUST be squash-merged per `process.pull-request`.

## Traceability

27. Every PR MUST reference its issue; every issue MUST belong to a milestone.
28. Issues MUST be closed via PR merge keywords (`Closes`, `Fixes`) — not manually.
29. After merge, demo artifacts MUST be posted on the issue per `process.product-engineering-handoff`.

## Golden Example

End-to-end walkthrough for implementing issue #12 ("Add search endpoint") from milestone "v1.0":

```bash
# 1. From the main checkout, create a branch and worktree (rules 9-10)
cd .repos/acme/api
git fetch origin
git branch feat/add-search-endpoint origin/main
git worktree add .worktrees/feat/add-search-endpoint feat/add-search-endpoint

# 2. Work in the worktree
cd .worktrees/feat/add-search-endpoint

# 3. Dummy commit to enable PR creation (rule 11)
git commit --allow-empty -m "chore: start work on search endpoint"

# 4. Push and open draft PR with tasks in body (rules 12-13)
git push -u origin feat/add-search-endpoint
```

**Forgejo:**
```bash
fj pr create "WIP: feat(api): add search endpoint" \
  --head feat/add-search-endpoint --base main \
  --body "$(cat <<'EOF'
# Goal

Add a search endpoint to the API so users can query items by keyword.
Closes #12

# Tasks

- [ ] Add search route handler
- [ ] Add input validation
- [ ] Add integration tests
- [ ] Update API documentation

# Changes

(to be filled during implementation)

# Demo

(to be filled before review)
EOF
)"
```

**GitHub:**
```bash
gh pr create --draft \
  --title "feat(api): add search endpoint" \
  --body "$(cat <<'EOF'
# Goal

Add a search endpoint to the API so users can query items by keyword.
Closes #12

# Tasks

- [ ] Add search route handler
- [ ] Add input validation
- [ ] Add integration tests
- [ ] Update API documentation

# Changes

(to be filled during implementation)

# Demo

(to be filled before review)
EOF
)"
```

```bash
# 5. Implement in the worktree, committing early and often (rules 18-19)
git add src/routes/search.ts
git commit -m "feat(api): add search route handler"

git add src/routes/search.test.ts
git commit -m "test(api): add search integration tests"

# 6. Update PR body — check off all tasks (rule 20)
# Forgejo: fj pr edit <number> --body "..." or use the web UI
# GitHub: gh pr edit <number> --body "..."

# 7. Remove WIP prefix / mark ready, assign reviewer (rules 21-22)
# Forgejo: edit PR title to remove "WIP: " prefix, then assign reviewer
# GitHub: gh pr ready <number>, then request Copilot review

# 8. Address review feedback, squash merge (rules 24-25)
# Forgejo: fj pr merge <number> --method squash --delete
# GitHub: gh pr merge <number> --squash --delete-branch

# 9. Clean up worktree after merge
cd .repos/acme/api
git worktree remove .worktrees/feat/add-search-endpoint

# 10. Post demo artifacts on the issue (rule 28)
```
