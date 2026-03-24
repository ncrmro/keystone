# Review and Merge

## Objective

Collect agent results from the worktree. Review the diff against TASK.md acceptance
criteria. Push changes. Gate on CI. Request review. Auto-merge on PASS (squash).
Max 3 fix attempts on FAIL.

## Task

### Process

#### Step 1: Collect Results

Read run.md to get the worktree path, then collect agent output:

```bash
WORKTREE=.repos/OWNER/REPO/.worktrees/BRANCH

# Check agent committed work
git -C $WORKTREE log --oneline -10

# Read the updated TASK.md (agent checked off criteria + added notes)
cat $WORKTREE/TASK.md

# See what changed
git -C $WORKTREE diff main..HEAD --stat
git -C $WORKTREE diff main..HEAD
```

#### Step 2: Review the Diff

Review the diff against TASK.md acceptance criteria. For each criterion:

1. **Check requirement met**: Is there code that satisfies this criterion?
2. **Check evidence**: Are tests, output, or other evidence present?
3. **Check scope**: Does every changed file/hunk trace back to an acceptance criterion?

**Scope validation is critical.** Flag changes NOT required by any acceptance criterion:
- Reformatting/linting code not part of the task
- Refactoring existing code (extracting, renaming, restructuring)
- Adding features or elements not in acceptance criteria
- Modifying files not related to the task

If out-of-scope changes exist, verdict is **FAIL** with instructions to revert them.

**Task-type-specific review focus:**
- **implement**: Verify new behavior works, tests cover it, no existing tests broken
- **fix**: Verify bug is fixed, regression test exists, root cause addressed (not just symptoms)
- **refactor**: Verify behavior is UNCHANGED, structure improved, all tests still pass

Verdict: **PASS** (all requirements met AND no out-of-scope changes) or **FAIL**.

#### Step 3: Push Changes

```bash
cd $WORKTREE
git push origin $BRANCH
```

Update TASK.md status to `in-review`.

#### Step 4: CI Gate

**GitHub:**
```bash
# Verify CI exists
CI_COUNT=$(gh pr view $PR_NUM --repo OWNER/REPO --json statusCheckRollup --jq '.statusCheckRollup | length')

if [ "$CI_COUNT" -gt 0 ]; then
  # Watch CI to completion — do NOT read logs into chat
  gh pr checks $PR_NUM --repo OWNER/REPO --watch
fi
```

If CI fails, download and search logs per `process.continuous-integration`:

**Check for missing secrets first** — a common cause of CI failures on new or recently
configured repos:
```bash
gh secret list --repo OWNER/REPO
gh variable list --repo OWNER/REPO
```

If secrets are missing (empty output), tell the user what secrets are needed and offer
the CLI commands to set them. After secrets are configured, offer to rerun:
```bash
gh run rerun $RUN_ID --repo OWNER/REPO
```

For Cloudflare Workers projects, also check wrangler secrets:
```bash
# Wrangler secrets must be set from the server or via wrangler CLI
wrangler secret list
```

Then download and search logs:
```bash
RUN_ID=$(gh run list --repo OWNER/REPO --branch $BRANCH -L 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RUN_ID" --repo OWNER/REPO --log > /tmp/ci-$RUN_ID.log
rg -i 'error|fail|fatal|exit code' /tmp/ci-$RUN_ID.log
```

**Forgejo:**
```bash
SHA=$(git -C $WORKTREE rev-parse HEAD)

# Poll commit status until terminal
tea api --login forgejo /repos/OWNER/REPO/commits/$SHA/status
# Repeat until all statuses reach success/failure
```

If CI fails on Forgejo:
```bash
# Find job ID
tea api --login forgejo /repos/OWNER/REPO/actions/runs
JOB_ID=123
tea api --login forgejo /repos/OWNER/REPO/actions/jobs/$JOB_ID/logs > /tmp/ci-$JOB_ID.log
rg -i 'error|fail|fatal|exit code' /tmp/ci-$JOB_ID.log
```

**CRITICAL**: Never read full CI logs into conversation context. Download to file, search with rg.

#### Step 4b: Deploy Preview Verification

If the project has deploy previews (Cloudflare Workers, Vercel, Netlify, etc.),
verify the changes on the deployed preview environment:

1. **Check for preview URL**: Look for deploy preview comments on the PR from
   platform bots (Cloudflare, Vercel, Netlify):
   ```bash
   gh pr view $PR_NUM --repo OWNER/REPO --comments | grep -i 'preview\|deploy'
   ```

2. **Verify the deployed service**: Visit the preview URL and confirm:
   - The changes are visible and working as expected
   - No regressions in existing functionality
   - The service loads without errors

3. **For Cloudflare Workers specifically**:
   - Preview deployments are created automatically by the Workers Builds integration
   - Preview URLs are posted as PR comments by the Cloudflare bot in a table format
   - **Branch preview**: `https://{branch-slug}-{project-name}.{account}.workers.dev`
   - **Commit preview**: `https://{commit-hash-prefix}-{project-name}.{account}.workers.dev`
   - Example: `https://feat-keystone-docs-pipeline-ks-systems-web.ncrmro.workers.dev`
   - Parse the PR comments to extract these URLs:
     ```bash
     gh pr view $PR_NUM --repo OWNER/REPO --json comments --jq '.comments[].body' | grep -o 'https://[^ ]*workers.dev[^ ]*'
     ```
   - **Limitation**: CF Workers native builds run only `pnpm build` — they don't support
     git submodules, custom build scripts (tsx), or multi-step builds. If your build
     requires these, the preview will show a partial build. Use GitHub Actions for full
     production deploys.

4. **Update the PR Demo section**: Per `process.pull-request`, every PR MUST have a
   `# Demo` section with evidence the work is correct. When a deploy preview is available,
   the Demo section MUST include:
   - The preview URL
   - What was verified (specific pages, features, behaviors)
   - Screenshots or terminal output if applicable
   - Confirmation that the deployed service loads without errors

   ```bash
   # Update PR body with deploy preview evidence
   gh pr edit $PR_NUM --repo OWNER/REPO --body "$(cat <<'EOF'
   ...existing body...

   # Demo

   **Deploy Preview**: https://<hash>.<project>.workers.dev
   - Verified: [specific pages/features checked]
   - Service loads without errors
   - Changes visible and working as expected
   EOF
   )"
   ```

5. **Record verification in review.md**: Include the preview URL and what was checked
   in the review document.

**This step is best-effort** — if no deploy preview is available, proceed with CI
results only. But when previews ARE available, always use them. CI passing is necessary
but not sufficient — verify the actual deployed behavior.

#### Step 4c: Screenshot Demo Evidence

If the project has Playwright screenshot tests (e.g., `bun run test:screenshots`,
`npm run test:screenshots`), run them to capture visual evidence of requirements:

1. **Check for screenshot test script**: Look in `package.json` for a
   `test:screenshots` script or similar Playwright screenshot runner.

2. **Run the screenshot tests**:
   ```bash
   cd $WORKTREE
   bun run test:screenshots  # or npm/pnpm equivalent
   ```

3. **Commit and push screenshots**: Screenshots should be committed so they can
   be referenced by URL:
   ```bash
   git add packages/web/tests/browser/screenshots/  # or wherever screenshots land
   git commit -m "test(screenshots): capture requirement evidence"
   git push
   ```

4. **Post screenshots on the PR**: Use `raw.githubusercontent.com` URLs with the
   commit SHA to embed images inline:
   ```bash
   SHA=$(git rev-parse --short HEAD)
   gh pr comment $PR_NUM --repo OWNER/REPO --body "$(cat <<EOF
   ## Demo Screenshots

   Automated Playwright screenshots capturing requirement evidence.

   ### Screenshot 1
   ![Description](https://raw.githubusercontent.com/OWNER/REPO/$SHA/path/to/screenshot.png)
   EOF
   )"
   ```

5. **Record in review.md**: Note which screenshots were captured and which
   requirements they provide evidence for.

**This step is best-effort** — skip if no screenshot test infrastructure exists.
When screenshots ARE available, they provide strong visual evidence for UI requirements.

#### Step 5: Request Review and Update Project Board

**Request review:**

**GitHub:**
```bash
# Mark PR ready for review
gh pr ready $PR_NUM --repo OWNER/REPO

# Request Copilot review per process.copilot-agent
gh pr edit $PR_NUM --repo OWNER/REPO --add-reviewer copilot 2>/dev/null || \
  gh pr comment $PR_NUM --repo OWNER/REPO --body "@copilot review this PR"
```

**Forgejo:**
```bash
# Remove WIP: prefix to mark ready
fj pr edit $PR_NUM --repo OWNER/REPO --title "$TYPE(scope): task title"

# Assign repo owner as reviewer per tool.forgejo
fj pr edit $PR_NUM --repo OWNER/REPO --add-reviewer REPO_OWNER
```

**Move issue to "In Review"** on the project board:

**GitHub:**
```bash
gh project item-edit --id $ITEM_ID --project-id $PROJECT_ID \
  --field-id $STATUS_FIELD_ID --single-select-option-id $IN_REVIEW_OPTION_ID
```

**Forgejo:**
```bash
forgejo-project item move --project $PROJECT_NUM --issue $ISSUE_NUMBER --column "In Review"
```

**Skip board update** if the task has no associated issue or no project board.

#### Step 6: Auto-Merge (PASS Verdict)

**GitHub:**
```bash
gh pr merge $PR_NUM --repo OWNER/REPO --auto --squash --delete-branch
```

**Forgejo:**
```bash
# Poll until CI passes, then merge
fj pr merge $PR_NUM --repo OWNER/REPO --method squash --delete
```

Update TASK.md status to `merged`.

#### Step 7: Handle Failures (Fix Loop)

If review verdict is FAIL or CI fails, send work back to the same agent.

**Track attempts in run.md:**
```yaml
fix_attempts: 1  # Increment on each failure
```

**Send fix instructions:**
```bash
cd $WORKTREE

# Append fix requirements to TASK.md
cat >> TASK.md << 'EOF'

## Fix Required (Attempt N/3)

### Issues Found
- [specific issues from review]

### CI Failures
- [error details from log search]

### Files to Modify
- [specific guidance]
EOF

git add TASK.md
git commit -m "chore: add fix requirements (attempt N/3)"
git push
```

Re-launch the agent via agentctl:
```bash
agentctl drago AGENT --project SLUG --worktree $WORKTREE
```

After fixes, loop back to Step 1 (collect → review → CI → merge or fix again).

**Max 3 fix attempts.** After 3 failures:
1. Update TASK.md status to `failed`
2. Update TASKS.yaml with status `blocked`
3. Move issue to "Blocked" on the project board (if applicable):
   - **GitHub:** `gh project item-edit` to set status to a blocked/backlog column
   - **Forgejo:** `forgejo-project item move --column "Backlog"`
4. Comment on the issue with failure summary
5. Report the failure summary to the user

```
collect → review → CI → pass? → auto-merge
                       │
                       fail? → send back to SAME agent → collect (loop)
                       │
                       3 failures? → mark failed, report to user
```

#### Step 8: Write review.md

Write the review document to `.deepwork/tmp/sweng/review.md`:

## Output Format

### review.md (PASS)

```markdown
---
verdict: PASS
pr_number: 42
pr_url: https://github.com/ncrmro/catalyst/pull/42
auto_merge: enabled
fix_attempts: 0
reviewed: 2026-03-21T15:30:00Z
platform: github
task_type: implement
---

# Review: feat/add-search-endpoint

## Verdict: PASS

## Acceptance Criteria

| Criterion | Status | Evidence |
|-----------|--------|----------|
| GET /api/search returns results | Pass | src/routes/search.ts:45 |
| Input validation | Pass | src/routes/search.ts:12 |
| Integration tests | Pass | tests/search.test.ts — 8/8 passed |
| Existing tests pass | Pass | CI green |

## Scope Check

All changes are in-scope. Each modified file traces to acceptance criteria:
- `src/routes/search.ts` — search endpoint (criteria 1, 2)
- `tests/search.test.ts` — test coverage (criterion 3)

## Diff Summary

- **Commits**: 3
- **Files changed**: 2
- **Insertions**: +85
- **Deletions**: -0

## CI Status

All checks passed.

## Auto-Merge

Enabled. PR will merge when CI passes and review is approved.
```

### review.md (FAIL)

```markdown
---
verdict: FAIL
pr_number: 42
fix_attempts: 2
reviewed: 2026-03-21T15:30:00Z
platform: github
task_type: fix
---

# Review: fix/null-pointer-crash

## Verdict: FAIL (Attempt 2/3)

## Issues Found

- [ ] Missing null check in search.ts:34
- [ ] Test search.test.ts:12 failing with TypeError

## Action

Sending back to claude for fixes. TASK.md updated with fix requirements.
```

## Quality Criteria

- Agent's updated TASK.md reviewed against each acceptance criterion
- Diff reviewed for scope — all changes trace to acceptance criteria
- If PASS: changes pushed, CI gated, review requested, auto-merge enabled (squash), issue moved to "In Review"
- If FAIL: work sent back to same agent with specific fix instructions via TASK.md
- If 3 failures: issue moved to "Blocked", comment posted on issue
- Max 3 fix attempts enforced before marking failed
- review.md written with verdict, evidence, and merge status
- run.md updated with fix_attempts and timing
- **CRITICAL**: CI logs never read into chat — download to file, search with rg
- Deploy preview verified when available (Cloudflare Workers, Vercel, Netlify) and PR Demo section updated with evidence
- Platform-appropriate commands used throughout (gh vs fj)

## Context

This is the most complex phase. The key design principle: **keep the human OUT
of the loop for successful tasks.** CI passes + review approval = merged.

If a task can't be fixed in 3 attempts, that's a signal the task needs replanning:
- Task description was ambiguous → fix in planning
- Acceptance criteria didn't cover the failure case → fix in planning
- Agent choice wasn't capable enough → try a different agent
