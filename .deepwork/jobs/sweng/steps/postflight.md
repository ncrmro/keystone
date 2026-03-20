# Clean Up

## Objective

Remove the worktree and local branch for a merged task. Update TASKS.yaml status
to completed.

## Task

### Process

#### Step 1: Read Review Result

Read review.md to confirm the task was merged:

```bash
cat .deepwork/tmp/sweng/review.md
```

Only proceed if verdict is PASS and auto_merge is enabled/completed.

#### Step 2: Clean Up Worktree and Branch

Extract repo and branch from TASK.md or run.md:

```bash
REPO=OWNER/REPO_NAME
BRANCH=feat/task-slug

cd .repos/$REPO

# Remove worktree
git worktree remove .worktrees/$BRANCH 2>/dev/null || \
  git worktree remove --force .worktrees/$BRANCH

# Delete local branch (remote branch deleted by --delete-branch on merge)
git branch -d $BRANCH 2>/dev/null || git branch -D $BRANCH
```

#### Step 3: Update Project Board (Forgejo Only)

On Forgejo, move the issue to "Done" on the project board. GitHub handles this
automatically via built-in board automations (PR merged → Done), so no action
needed on GitHub per `process.project-board` rule 6.

**Forgejo:**
```bash
forgejo-project item move --project $PROJECT_NUM --issue $ISSUE_NUMBER --column "Done"
```

**Skip** if the task has no associated issue or no project board.

#### Step 4: Update TASKS.yaml

Update the task entry in TASKS.yaml:
- Set `status: completed`

```bash
# Read current TASKS.yaml
cat TASKS.yaml
```

Edit the relevant task entry to set status to `completed`.

#### Step 5: Clean Up Temporary Files

Remove workflow artifacts:

```bash
rm -rf .deepwork/tmp/sweng/
```

## Output Format

### TASKS.yaml (updated)

The relevant task entry with `status: completed`:

```yaml
tasks:
  - name: "add-search-endpoint"
    description: "Add search endpoint to catalyst API"
    status: completed
    source: email
    source_ref: "email-42"
    workflow: "sweng/sweng"
    project: "catalyst"
```

## Quality Criteria

- Worktree removed for the merged task
- Local branch deleted
- On Forgejo: issue moved to "Done" on project board (GitHub auto-handles this)
- TASKS.yaml updated with status: completed
- Temporary workflow files cleaned up
- No orphaned worktrees or branches remaining

## Context

Postflight keeps the workspace clean. Without it, worktrees pile up consuming
disk space, stale branches accumulate, and TASKS.yaml shows outdated statuses.
This step runs after review successfully merges the PR.
