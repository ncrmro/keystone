# Reorder Tasks by Priority

## Objective

Read TASKS.yaml and PROJECTS.yaml, then reorder pending tasks so that higher-priority project tasks come first. This step runs with haiku for cheap, fast ordering.

## Task

Reorder the pending tasks in TASKS.yaml based on project priority defined in PROJECTS.yaml. Projects are listed in priority order (first = highest). Tasks associated with higher-priority projects should appear before tasks from lower-priority projects. Tasks without a project association go last.

### Process

1. **Read both files**
   - Read TASKS.yaml from the working directory
   - Read PROJECTS.yaml from the working directory
   - Extract the project priority order from PROJECTS.yaml (list position = priority rank)

2. **Categorize tasks**
   - Separate tasks into: pending, in_progress, completed, blocked
   - Only pending tasks will be reordered
   - All other tasks retain their current position

3. **Assign model for each pending task**
   - For each pending task that does NOT already have a `model` field, assess its complexity from the description and assign a model:
     - `haiku` — Simple, mechanical tasks: replying "pong", forwarding a message, simple lookups, single-command operations
     - `sonnet` — Standard tasks: research, multi-step work, coding, email composition, system interaction, browser automation, anything requiring judgment or tool chaining
     - `opus` — Advanced tasks: complex architectural decisions, multi-system debugging, workflow design, tasks requiring deep reasoning across many files or systems, novel problem-solving with no clear precedent
   - If a task already has a `model` field, leave it unchanged (it was set intentionally)
   - Write the `model` field on the task entry in TASKS.yaml

4. **Sort pending tasks by project priority**
   - For each pending task, look up its `project` field
   - Map the project to its position in PROJECTS.yaml (index 0 = highest priority)
   - Sort pending tasks by this priority rank (ascending = highest priority first)
   - Tasks with the same project priority maintain their relative order
   - Tasks without a `project` field or with a project not in PROJECTS.yaml go after all project-associated tasks

5. **Reconstruct TASKS.yaml**
   - Write the reordered task list back to TASKS.yaml
   - Non-pending tasks remain in their original positions
   - Pending tasks are inserted in their new priority order

6. **Write the priority report**
   - Explain the ordering decisions briefly
   - Note any tasks that couldn't be associated with a project
   - List the model assigned to each pending task and why

### Important guidelines

- **Follow the schema exactly.** See `steps/shared/tasks_schema.md` for the canonical TASKS.yaml schema. Do NOT rename fields, add new fields (like `id`, `priority`, `urgency`, `effort`, `depends_on`), or add sections (like `summary:`). The only top-level key is `tasks`.
- **Do not change any task fields** other than position in the list and the `model` field. Copy every existing task entry character-for-character, only changing list order and adding/updating `model`.
- **Do not change task statuses** — this step only reorders and assigns models
- **Preserve all tasks** — every task in the input MUST appear in the output. No tasks should be added or removed.
- **Handle missing projects gracefully** — if a task references a project not in PROJECTS.yaml, place it after project-associated tasks
- **Validate after writing.** After writing TASKS.yaml, run `yq e '.' TASKS.yaml` to verify it's valid YAML. If invalid, re-read the original file and try again.

## Output Format

### TASKS.yaml

The reordered task file.

**Structure**:

```yaml
tasks:
  # Completed/blocked tasks stay in place
  - name: "setup-email"
    description: "Configure email access"
    status: completed
  # Pending tasks reordered by project priority, with model assigned
  - name: "high-priority-task"
    description: "Task from the highest priority project"
    status: pending
    project: "agent-space"
    model: "sonnet"
  - name: "reply-pong"
    description: "Reply with pong to a ping email"
    status: pending
    project: "agent-space"
    model: "haiku"
  - name: "unaffiliated-task"
    description: "Task without a project"
    status: pending
    model: "sonnet"
```

### priority_report.md

Brief explanation of the ordering.

**Structure**:

```markdown
# Priority Report

**Date**: [current date]

## Project Priority Order

1. [project-name] — [n] pending tasks
2. [project-name] — [n] pending tasks
   ...

## Reordering Summary

- [n] pending tasks reordered
- [n] tasks associated with projects
- [n] tasks without project association (placed last)

## Model Assignments

| Task        | Model  | Reason                         |
| ----------- | ------ | ------------------------------ |
| [task-name] | opus   | Complex multi-system debugging |
| [task-name] | sonnet | Multi-step system interaction  |
| [task-name] | haiku  | Simple reply                   |

## Changes

- Moved **[task-name]** up (project: [project-name], priority: [n])
- **[task-name]** remains last (no project association)
```

## Quality Criteria

- Pending tasks are ordered by their project's position in PROJECTS.yaml (first project = highest priority)
- Completed, blocked, and in_progress tasks are not reordered or removed
- Tasks without a project association appear after all project-associated pending tasks
- Every pending task has a `model` field (either pre-existing or newly assigned)
- No task fields other than position and `model` are modified
- All tasks from the original file are present in the output
- The priority report accurately describes what was reordered and why, and lists model assignments

## Context

This step runs between ingest and execution. By ordering tasks by project priority and assigning execution models, the task loop orchestrator can process tasks top-to-bottom, with the most important work first. Each task runs with the model specified in its `model` field. This step uses haiku since the logic is straightforward sorting and classification.
