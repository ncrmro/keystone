<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->
# Convention: Code Delivery (code.delivery)

This convention defines the end-to-end lifecycle of delivering features and fixes via code changes: from milestone/issue through to merged PR. It orchestrates existing conventions rather than duplicating them.

## Upstream Dependencies

1. Feature delivery MUST originate from an issue belonging to a milestone.
2. Requirements MUST be documented as specs before implementation begins.
3. If no milestone exists, one MUST be created per `biz.product-engineering-handoff`.

## Issue as Plan

4. The issue body MUST serve as the plan of record — no separate `plan.md` files.
5. The issue body MUST include a checklist of deliverables derived from the spec.
6. Large issues MUST be decomposed into sub-issues, each becoming its own branch and PR.
7. Sub-issues MUST reference the parent issue (e.g., "Part of #42").
8. The issue body SHOULD be updated as the plan evolves; comments supplement but do not replace it.

## Branch and Early PR

9. A branch MUST be created from the default branch using `ops.vcs` naming conventions (semantic prefix + short description).
10. When starting work on an issue that belongs to a milestone with a project board, the issue's board status MUST be updated to "In Progress" — on GitHub via `gh project item-edit` per `process.project-board`, on Forgejo via the web UI.
11. A dummy commit MUST be created immediately after branching (e.g., empty commit or minimal scaffold) to enable opening a PR.
12. A draft PR MUST be opened immediately after the dummy commit (Forgejo: `WIP:` title prefix per `ops.forgejo`; GitHub: `--draft` flag).
13. The PR body MUST include a `# Tasks` section containing the task breakdown as markdown checkboxes mirroring the issue's deliverable checklist.
14. The draft PR SHOULD make the plan visible to reviewers before implementation begins.

## PR Body Format

15. The PR body MUST follow the `code.pull-request` convention (`# Goal`, `# Changes`, `# Demo` sections) plus the `# Tasks` section from rule 13.
16. The PR title MUST follow conventional commit format per `ops.vcs` (e.g., `feat(api): add search endpoint`).
17. The PR body MUST include `Closes #N` or `Fixes #N` to auto-close the originating issue on merge.

## Implementation

18. Commits MUST follow `ops.vcs` commit discipline (early, often, one logical change per commit).
19. Changes MUST NOT exceed the scope of the issue's acceptance criteria.
20. All tasks in the PR body's `# Tasks` section MUST be checked off before marking the PR ready for review.

## Review and Merge

21. When marking a PR ready for review, the issue's board status MUST be updated to "In Review" — on GitHub via `gh project item-edit` per `process.project-board`, on Forgejo via the web UI.
22. Appropriate reviewers MUST be assigned before marking the PR ready for review.
23. Reviewers MUST be assigned per the ownership matrix in `process.code-review-ownership`. On both GitHub and Forgejo, CODEOWNERS handles automatic reviewer assignment when a PR is created or undrafted.
24. Copilot SHOULD also be requested as a supplementary reviewer per `process.copilot-agent`.
25. Review feedback MUST be addressed per `ops.copilot-agent` conversation resolution rules (fix or explain every comment).
26. PRs MUST be squash-merged per `code.pull-request`.

## Traceability

27. Every PR MUST reference its issue; every issue MUST belong to a milestone.
28. Issues MUST be closed via PR merge keywords (`Closes`, `Fixes`) — not manually.
29. After merge, demo artifacts MUST be posted on the issue per `biz.product-engineering-handoff`.

## Golden Example

End-to-end walkthrough for implementing issue #12 ("Add search endpoint") from milestone "v1.0":

```bash
# 1. Branch from default branch (rule 9)
git checkout main && git pull
git checkout -b feat/add-search-endpoint

# 2. Dummy commit to enable PR creation (rule 10)
git commit --allow-empty -m "chore: start work on search endpoint"

# 3. Push and open draft PR with tasks in body (rules 11-12)
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
# 4. Implement, committing early and often (rules 17-18)
git add src/routes/search.ts
git commit -m "feat(api): add search route handler"

git add src/routes/search.test.ts
git commit -m "test(api): add search integration tests"

# 5. Update PR body — check off all tasks (rule 19)
# Forgejo: fj pr edit <number> --body "..." or use the web UI
# GitHub: gh pr edit <number> --body "..."

# 6. Remove WIP prefix / mark ready, assign reviewer (rules 20-21)
# Forgejo: edit PR title to remove "WIP: " prefix, then assign reviewer
# GitHub: gh pr ready <number>, then request Copilot review

# 7. Address review feedback, squash merge (rules 23-24)
# Forgejo: fj pr merge <number> --method squash --delete
# GitHub: gh pr merge <number> --squash --delete-branch

# 8. Post demo artifacts on the issue (rule 27)
```
