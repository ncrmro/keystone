<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: In-Flight Work Routing (process.in-flight-work-routing)

This convention defines how agents decide whether new work (a bug, missing piece, or refinement) belongs on an existing in-flight PR's branch or in a new PR. It applies to both engineering agents (before cutting a branch) and product agents (before writing a delegation prompt that names a branch or PR).

## Core Heuristic

### Rule 1 — Same deliverable → existing branch

If the new work is a bug in an open PR's code, a missing piece of that PR's stated scope, or a refinement triggered by review feedback on that PR, the agent MUST push commits to the existing PR's branch and update the PR body's `# Tasks` checklist per `process.vcs-context-continuity:1`. The agent MUST NOT cut a new branch for this work.

### Rule 2 — Separate concern → new PR

If the new work is independently mergeable, has its own user-visible value, or could ship without the in-flight PR, the agent MUST open a new PR. Stacking on the in-flight PR's branch is appropriate when the new work depends on unmerged code from that PR.

### Rule 3 — Closed or merged → new PR off the integration target

If the referenced PR is merged, closed, or abandoned, the agent MUST cut a new branch off the integration target (the default branch, or the parent PR's branch when part of an existing stack).

## Applying the Heuristic Before Creating a Branch

When beginning implementation work, agents MUST evaluate this heuristic before creating a new branch:

1. Identify any open PRs related to the goal (search by issue reference, title keyword, or referenced branch).
2. If an open PR exists whose stated scope covers the new goal, apply **Rule 1**: check out that PR's branch in the worktree instead of creating a new branch.
3. If the goal is independent or the open PR is already merged/closed, apply **Rule 2** or **Rule 3** and create a new branch.

```bash
# Check for an open PR whose scope covers the goal
gh pr list --repo {owner}/{repo} --state open --json number,title,headRefName,body \
  | jq '.[] | select(.body | test("closes #N|part of #N"; "i"))'
```

## Applying the Heuristic When Writing Delegation Prompts

When a product agent creates an issue or delegation prompt that references an in-flight PR, the agent MUST apply this heuristic before writing the acceptance criteria:

- If the new work is in scope for an open PR (Rule 1 applies): write **"push commits to PR #N's branch (`{branch-name}`)"** — NOT "PR against `{branch-name}`", which implies opening a new PR.
- If the new work is a separate concern (Rule 2 applies): write **"open a new PR"** with the correct base branch.

**Wrong** (implies new PR stacked on existing branch):

> PR against `feat/garden-bed-planner-ui-mock`

**Correct** (instructs push to existing PR):

> Push commits to PR #79's branch (`feat/garden-bed-planner-ui-mock`)

## Counter-Examples

### Correct: push to existing branch (Rule 1)

A bug in the click-to-add widget is found during review of an open UI PR. The bug is in the PR's own code and the PR's scope covers the widget. The agent MUST push a fix commit to that PR's branch, not open a new PR.

### Correct: new PR for separate concern (Rule 2)

An auth redirect-proxy env var fix is independently mergeable and not bound to any open UI PR's scope. The agent MUST open a new PR, optionally cherry-picked to main.

### Incorrect: new stacked PR for in-scope fix

A bug is filed for an open PR's UI code. The issue body says "PR against `feat/garden-bed-planner-ui-mock`." The agent opens `feat/planner-requirements-and-click-fix` and a new PR stacked on top. This violates Rule 1 — the fix belongs on the existing PR's branch.

## Relationship to Other Conventions

- `process.feature-delivery` rule 6 governs large issue decomposition into sub-issues; this convention covers the narrower case of follow-up work on an existing open PR.
- `process.pr-review-response` covers reviewer-triggered fixes; this convention covers author- or user-triggered follow-ups that arise while the PR is open.
- `process.vcs-context-continuity:1` requires updating the PR body's `# Tasks` checklist whenever work is added to an existing PR's branch.
