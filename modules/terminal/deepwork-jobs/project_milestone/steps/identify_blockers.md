# Identify Blockers

## Objective

Surface tasks that are blocked, overdue, or at risk, and propose actionable mitigations
in `milestones/<milestone-name>/blockers.md`.

## Task

### Step 1: Read Inputs

- Read `milestones/<milestone-name>/progress_report.md` for the overall health signal
- Re-read `milestones/<milestone-name>/TASKS.yaml` to find tasks with `status: blocked`
  or tasks that are `in_progress` without recent progress notes

### Step 2: Classify Each Blocker

For each blocked or at-risk task, identify:
- **Type**: external dependency | missing information | resource constraint | technical debt
- **Impact**: which milestone goal does this put at risk?
- **Mitigation**: what could unblock this? Who can act?

### Step 3: Write blockers.md

Create `milestones/<milestone-name>/blockers.md`:

```markdown
# Blockers: <Milestone Name>

**Date**: <today>

## Active Blockers

### 1. <Task ID> — <Task Name>

- **Type**: <type>
- **Impact**: Goal <n> is at risk
- **Details**: <what is blocking this task>
- **Mitigation**: <proposed action>
- **Owner**: <who should act>

...

## No blockers

<If no blockers exist, state that explicitly so readers know the review was done.>
```

### Step 4: Update TASKS.yaml

If any `pending` tasks have clear blockers that weren't yet tagged, update their
`status` to `blocked` and add a `notes` entry.

### Step 5: Confirm

Confirm the file is saved and every blocker has a named owner or escalation path.
