# Break Down Tasks

## Objective

Decompose the milestone goals into a concrete, prioritized list of tasks and record them
in `milestones/<milestone-name>/TASKS.yaml`.

## Task

Read `milestone.md` to understand the goals and scope, then create or update `TASKS.yaml`
with tasks that, when completed, will satisfy every milestone goal.

### Step 1: Read the Milestone

- Read `milestones/<milestone-name>/milestone.md`
- List the goals and success criteria
- Note what is in and out of scope

### Step 2: Generate Tasks

For each goal, generate one or more tasks. Each task must be:
- **Actionable**: A single agent can pick it up without asking for clarification
- **Scoped**: Completable in one focused work session
- **Linked**: Traceable back to its parent goal

### Step 3: Write TASKS.yaml

Create or append to `milestones/<milestone-name>/TASKS.yaml` using this schema:

```yaml
tasks:
  - id: <short-id>           # e.g. PM-001
    name: <task title>
    description: <one sentence>
    status: pending           # pending | in_progress | done | blocked
    priority: high            # high | medium | low
    goal: <goal number>       # which milestone goal this task supports
    notes: ""
```

### Step 4: Review

- Count tasks per goal — every goal must have at least one
- Sort by priority (high first) within each goal
- Confirm the file is saved
