# Launch Agent

## Objective

Launch a coding agent in the prepared worktree via `agentctl`. The agent reads
TASK.md, implements the task, and commits its work. Record run metadata in run.md.

## Task

### Process

#### Step 1: Read Task Metadata

Read TASK.md from the worktree to extract task details:

```bash
WORKTREE=.repos/OWNER/REPO/.worktrees/BRANCH
cat $WORKTREE/TASK.md
```

Extract from frontmatter:
- `repo` — owner/repo
- `branch` — branch name
- `agent` — agent type (claude, gemini, opencode, claude-local)
- `platform` — github or forgejo
- `task_type` — implement, fix, or refactor

#### Step 2: Verify Worktree State

Confirm the worktree is ready:

```bash
cd $WORKTREE

# Verify we're on the right branch
git branch --show-current

# Verify TASK.md exists
test -f TASK.md && echo "TASK.md present" || echo "ERROR: TASK.md missing"

# Verify clean state
git status --short
```

#### Step 3: Launch Agent via agentctl

Launch the coding agent using `agentctl`:

```bash
agentctl drago AGENT --project SLUG --worktree $WORKTREE
```

Where:
- `AGENT` is one of: `claude`, `gemini`, `opencode`, `claude-local`
- `SLUG` is a short project identifier derived from the repo name
- `$WORKTREE` is the absolute path to the worktree

The agent contract (what the agent sees):

```
# Agent Contract

You are implementing a task. Read TASK.md for requirements.

## Scope Rules
- ONLY implement what is described in TASK.md. Nothing more.
- Do NOT create additional task files. Only TASK.md exists.
- If you finish early, stop.

## Rules
1. Read AGENTS.md / CLAUDE.md first for environment setup and build commands
2. Check off acceptance criteria in TASK.md as you complete them (- [ ] → - [x])
3. Add ## Agent Notes to TASK.md about decisions made
4. Add ## Results to TASK.md with test output
5. COMMIT your work — uncommitted work is lost
6. If blocked, add a ## Blockers section to TASK.md and commit
```

#### Step 4: Update TASK.md Status

Update TASK.md frontmatter to `status: assigned`:

```bash
cd $WORKTREE
sed -i 's/status: ready/status: assigned/' TASK.md
git add TASK.md
git commit -m "chore: mark task as assigned to $AGENT"
git push
```

#### Step 5: Write run.md

Write run metadata to `.deepwork/tmp/sweng/run.md`:

```bash
mkdir -p .deepwork/tmp/sweng
```

## Output Format

### run.md

```markdown
---
agent: claude
started: 2026-03-21T14:30:00Z
finished:
status: running
worktree: .repos/ncrmro/catalyst/.worktrees/feat/add-search-endpoint
branch: feat/add-search-endpoint
repo: ncrmro/catalyst
platform: github
task_type: implement
pr_number: 42
fix_attempts: 0
---

## Summary

Agent launched to implement: Add Search Endpoint

## Launch Command

```bash
agentctl drago claude --project catalyst --worktree .repos/ncrmro/catalyst/.worktrees/feat/add-search-endpoint
```

## Timing

- Agent started: 2026-03-21T14:30:00Z
- Agent completed: [will be populated]
- CI started: [will be populated]
- CI completed: [will be populated]

## Files Changed

[Will be populated after agent completes]

## Test Results

[Will be populated after agent completes]
```

## Quality Criteria

- Agent launched via `agentctl drago <agent> --project <slug> --worktree <path>`
- TASK.md present in worktree before launch
- TASK.md status updated to `assigned`
- run.md created with: agent, started, worktree, branch, repo, platform, task_type, pr_number
- Launch command recorded in run.md

## Context

This step is deliberately lightweight. It copies the task into the agent's workspace
and launches. The heavy lifting happens in the agent's execution and the review phase.

**Key rules:**
1. The agent MUST commit its work — uncommitted work is lost
2. The agent reads TASK.md for requirements, AGENTS.md for environment setup
3. agentctl handles the agent lifecycle (launch, monitor, signal completion)
