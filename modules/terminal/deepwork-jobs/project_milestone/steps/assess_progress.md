# Assess Progress

## Objective

Produce `progress_report.md` — a snapshot of how far along the milestone is — by
reading the current task statuses and mapping them back to milestone goals.

## Task

### Step 1: Read Inputs

- Read `milestones/<milestone-name>/milestone.md` for the goals and success criteria
- Read `milestones/<milestone-name>/TASKS.yaml` (or the path provided) for task statuses

### Step 2: Tally Status

Count tasks in each state: `pending`, `in_progress`, `done`, `blocked`.

Calculate completion percentage: `done / total * 100`.

### Step 3: Map to Goals

For each milestone goal:
- List tasks that support it
- Note how many are done vs. pending
- Give a health signal: ✅ on-track | ⚠️ at-risk | 🚫 blocked

Overall milestone health:
- **On-track**: all goals have ≥50% tasks done or no blockers
- **At-risk**: one or more goals behind schedule
- **Blocked**: one or more goals have blocked tasks with no mitigation

### Step 4: Write progress_report.md

Create `milestones/<milestone-name>/progress_report.md`:

```markdown
# Progress Report: <Milestone Name>

**Date**: <today>
**Overall health**: <On-track | At-risk | Blocked>
**Completion**: <done>/<total> tasks (<pct>%)

## Goal Status

### Goal 1: <name>
- Health: ✅ / ⚠️ / 🚫
- Done: <n> tasks | Remaining: <n> tasks
- Key remaining: <task names>

...

## Summary

<2–3 sentences on overall trajectory>
```

### Step 5: Confirm

Save the file and confirm the health signal is defensible given the task data.
