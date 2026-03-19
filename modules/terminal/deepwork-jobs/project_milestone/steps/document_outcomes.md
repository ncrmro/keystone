# Document Outcomes

## Objective

Write `outcomes.md` — a completion report that compares what was delivered against the
original milestone goals and captures anything deferred.

## Task

### Step 1: Read Inputs

- Read `milestones/<milestone-name>/milestone.md` for the original goals and success criteria
- Read `milestones/<milestone-name>/TASKS.yaml` for final task statuses

### Step 2: Evaluate Each Goal

For each milestone goal, determine:
- **Met**: All tasks done, success criterion observable
- **Partially met**: Most tasks done, core criterion met but some edges deferred
- **Deferred**: Not achieved; tasks moved to a future milestone

### Step 3: List Deferred Work

Compile any tasks with `status: pending` or `status: blocked` that were not completed.
These become candidates for the next milestone's planning step.

### Step 4: Write outcomes.md

Create `milestones/<milestone-name>/outcomes.md`:

```markdown
# Outcomes: <Milestone Name>

**Completed**: <date>
**Original target**: <date from milestone.md>

## Goal Outcomes

| Goal | Status | Notes |
|------|--------|-------|
| <Goal 1> | ✅ Met / ⚠️ Partial / ❌ Deferred | <brief note> |
...

## Deferred Work

- <task or item> — *Reason: <why deferred>*

## Summary

<3–5 sentence narrative suitable for sharing with stakeholders>
```

### Step 5: Update milestone.md

Change `**Status**: planning` to `**Status**: complete` in `milestone.md`.

### Step 6: Confirm

- File is saved
- Every original goal is accounted for (met, partial, or deferred)
- The summary is readable without prior context
