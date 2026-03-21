# Task Intake

## Objective

Accept a single task, identify the target repo and platform, create a branch and
worktree per `process.feature-delivery`, write TASK.md with acceptance criteria,
create a draft PR, and update TASKS.yaml.

The workflow that invoked this step determines the task type:
- `implement` → new feature (branch prefix: `feat/`)
- `fix` → bug fix (branch prefix: `fix/`)
- `refactor` → code restructuring (branch prefix: `refactor/`)

## Task

### Process

#### Step 1: Gather Inputs

Ask structured questions to determine the task, repo, and agent:

- **task_source**: One of:
  - TASKS.yaml entry name — read the entry for description and context
  - User describes the task directly — extract what needs to change and why
  - Issue URL — fetch via `gh issue view` (GitHub) or `fj issue view` (Forgejo)
- **repo**: Target repository as `owner/repo` (e.g., `ncrmro/catalyst`)
- **agent**: Which agent to assign. Options: `claude`, `gemini`, `opencode`, `claude-local`

If any input is ambiguous, ask the user before proceeding.

Determine the **task_type** from the invoking workflow:
- `/sweng.implement` → `implement`
- `/sweng.fix` → `fix`
- `/sweng.refactor` → `refactor`

If invoked without a workflow context, ask the user which type applies.

#### Step 2: Detect Platform

Determine the platform from the git remote URL:

```bash
cd .repos/OWNER/REPO
REMOTE_URL=$(git remote get-url origin)

if echo "$REMOTE_URL" | grep -q 'github.com'; then
  PLATFORM=github
elif echo "$REMOTE_URL" | grep -q 'git.ncrmro.com'; then
  PLATFORM=forgejo
else
  echo "Unknown platform for remote: $REMOTE_URL"
  exit 1
fi
```

#### Step 3: Fetch Issue Context (if applicable)

If the task comes from an issue:

**GitHub:**
```bash
gh issue view NUMBER --repo OWNER/REPO --json title,body,number
```

**Forgejo:**
```bash
fj issue view NUMBER --repo OWNER/REPO
```

Extract the title, description, and acceptance criteria from the issue body.

#### Step 4: Read Repo Context

Check the target repo for tech stack and conventions:
```bash
cat .repos/OWNER/REPO/AGENTS.md 2>/dev/null || cat .repos/OWNER/REPO/CLAUDE.md 2>/dev/null
```

Include relevant tech stack details in TASK.md so the agent has full context.

#### Step 5: Create Branch and Worktree

Per `process.feature-delivery` rules 9-10:

```bash
cd .repos/OWNER/REPO
git fetch origin

# Determine default branch
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')

# Create branch with semantic prefix matching task_type:
# implement → feat/task-slug
# fix → fix/task-slug
# refactor → refactor/task-slug
BRANCH="$PREFIX/task-slug"
git branch $BRANCH origin/$DEFAULT_BRANCH
git worktree add .worktrees/$BRANCH $BRANCH
```

The main checkout at `.repos/OWNER/REPO/` MUST remain on the default branch.

#### Step 6: Write TASK.md

Write TASK.md to the worktree root:

```markdown
---
repo: owner/repo
branch: feat/task-slug
agent: claude
platform: github           # or forgejo
issue: 42                  # optional
task_type: implement       # implement | fix | refactor
status: planning
created: 2026-03-21
---

# Task Title

## Description

[What needs to change and why — focused, not a full spec]

Tech stack: [from AGENTS.md / CLAUDE.md]

## Acceptance Criteria

- [ ] Criterion 1 (specific, testable)
- [ ] Criterion 2
- [ ] Existing tests pass

## Key Files

- path/to/relevant/file.ts — why it matters
```

**Task-type-specific guidance for acceptance criteria:**

- **implement**: Focus on new behavior, API contracts, test coverage
- **fix**: Include the bug reproduction steps, expected vs actual behavior, regression test
- **refactor**: Include behavioral invariants (what must NOT change), before/after structure

Update status to `ready` after writing.

#### Step 7: Dummy Commit and Draft PR

Per `process.feature-delivery` rules 11-12:

```bash
cd .repos/OWNER/REPO/.worktrees/$BRANCH

git add TASK.md
git commit -m "chore: start work on [task title]"
git push -u origin $BRANCH
```

Create draft PR with the proper body format per `process.pull-request`:

**GitHub:**
```bash
gh pr create --draft \
  --title "$TYPE(scope): task title" \
  --body "$(cat <<'EOF'
# Goal

[What this PR achieves and why]
Closes #ISSUE_NUMBER

# Tasks

- [ ] [Acceptance criterion 1]
- [ ] [Acceptance criterion 2]
- [ ] Tests pass

# Changes

(to be filled during implementation)

# Demo

(to be filled before review)
EOF
)"
```

**Forgejo:**
```bash
fj pr create "WIP: $TYPE(scope): task title" \
  --head $BRANCH --base $DEFAULT_BRANCH \
  --body "$(cat <<'EOF'
# Goal

[What this PR achieves and why]
Closes #ISSUE_NUMBER

# Tasks

- [ ] [Acceptance criterion 1]
- [ ] [Acceptance criterion 2]
- [ ] Tests pass

# Changes

(to be filled during implementation)

# Demo

(to be filled before review)
EOF
)"
```

Record the PR number.

#### Step 7b: Issue Comment and Project Board Update

When starting work on an issue that belongs to a milestone with a project board:

1. **Comment on the issue** to signal work has started:

**GitHub:**
```bash
gh issue comment $ISSUE_NUMBER --repo OWNER/REPO \
  --body "Starting work on branch \`$BRANCH\`. Draft PR: #$PR_NUMBER"
```

**Forgejo:**
```bash
fj issue comment $ISSUE_NUMBER --repo OWNER/REPO \
  --body "Starting work on branch \`$BRANCH\`. Draft PR: #$PR_NUMBER"
```

2. **Move the issue to "In Progress"** on the project board:

**GitHub:**
```bash
gh project field-list $PROJECT_NUM --owner OWNER --format json
gh project item-edit --id $ITEM_ID --project-id $PROJECT_ID \
  --field-id $STATUS_FIELD_ID --single-select-option-id $IN_PROGRESS_OPTION_ID
```

**Forgejo:**
```bash
forgejo-project item move --project $PROJECT_NUM --issue $ISSUE_NUMBER --column "In Progress"
```

**Skip this step** if the task has no associated issue or the issue has no project board.

#### Step 8: Update TASK.md Status

Update TASK.md frontmatter:
- `status: ready`

Commit the status change:
```bash
cd .repos/OWNER/REPO/.worktrees/$BRANCH
git add TASK.md
git commit -m "chore: mark task ready for assignment"
git push
```

## Output Format

### TASK.md

```markdown
---
repo: ncrmro/catalyst
branch: feat/add-search-endpoint
agent: claude
platform: github
issue: 12
task_type: implement
status: ready
created: 2026-03-21
---

# Add Search Endpoint

## Description

Add a search endpoint to the API so users can query items by keyword.
The API uses Express.js with TypeScript and PostgreSQL (from AGENTS.md).

## Acceptance Criteria

- [ ] GET /api/search?q=keyword returns matching items
- [ ] Input validation rejects empty queries
- [ ] Integration tests cover happy path and error cases
- [ ] Existing tests pass

## Key Files

- src/routes/index.ts — route registration
- src/db/queries.ts — database query layer
```

## Quality Criteria

- TASK.md has valid YAML frontmatter with: repo, branch, agent, platform, task_type, status, created
- Description is focused on what needs to change and why
- Acceptance criteria are specific, testable checkboxes
- Branch prefix matches task_type (feat/ for implement, fix/ for fix, refactor/ for refactor)
- Worktree created at the standard worktree path with correct branch
- Main checkout remains on default branch
- Draft PR created with Goal/Tasks/Changes/Demo sections
- PR title follows conventional commit format matching task_type
- If issue exists, PR body includes `Closes #N`
- If issue exists, a comment was posted noting work started
- If issue has a project board, issue moved to "In Progress" column

## Context

This step is shared by the `implement`, `fix`, and `refactor` workflows. The task_type
determines the branch prefix and shapes the acceptance criteria guidance, but the process
is otherwise identical. The key deliverable is a well-scoped TASK.md that gives the
sub-agent clear, testable criteria to implement against.
