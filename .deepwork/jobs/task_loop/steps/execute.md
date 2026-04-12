# Execute Task

## Objective

Perform the work for a single task specified in the prompt, then update TASKS.yaml with the outcome and document any blockers in ISSUES.yaml.

## Task

The task loop orchestrator has read the next pending task from TASKS.yaml and passed its name and description into this prompt. Execute the work described by the task. This session handles exactly one task — when done, exit so the orchestrator can start the next task in a fresh session.

### Process

1. **Read current state**
   - Read TASKS.yaml from the working directory
   - Read ISSUES.yaml from the working directory (create with `issues: []` if missing)
   - Locate the specified task by name

2. **Update status to in_progress**
   - Edit TASKS.yaml, setting the task's status to `in_progress`

3. **Assess feasibility**
   - Before committing to execution, verify the task is doable
   - Check that required tools, services, or files are available
   - If clearly blocked (e.g., a required service is unreachable, a dependency isn't installed), skip to step 5

4. **Read tool conventions** (before any external tool use)
   - Read AGENTS.md and CLAUDE.md in the working directory
   - These contain required conventions for tools like himalaya, git, etc.
   - You MUST follow these conventions exactly — incorrect usage can cause commands to hang or fail silently in this automated (non-TTY) environment

5. **Perform the work**
   - If the task has a `workflow` field, invoke that DeepWork workflow using `/deepwork {workflow}` instead of interpreting the task description freely. Pass the task description as the goal.
   - Otherwise, read the task description and execute the work it describes
   - This may involve: writing code, running commands, researching topics, configuring systems, editing files, sending emails, interacting with APIs, browser automation, or any other operational task
   - For browser UI tasks (signing into websites, filling forms, clicking through web flows): use the chrome-devtools MCP tools (`mcp__chrome-devtools__*`) to navigate, click, fill, and take screenshots. These are NOT the same as CLI commands — do not confuse browser sign-in with CLI auth tools like `gh auth login`.
   - Use available tools (Bash, Read, Write, Edit, WebSearch, chrome-devtools MCP, etc.) as appropriate

6. **Verify the work was done**
   - Before marking any task as completed, confirm you actually performed the work
   - You MUST be able to cite concrete evidence: commands you ran and their output, files you created or modified, responses you received, repos you cloned, etc.
   - "Completed" means the work described in the task description has been fully performed and the result is observable in the system (a file exists, an email was sent, a repo was cloned, etc.)
   - If you cannot point to a specific action you took and its result, you have NOT completed the task -- go back to step 5
   - NEVER mark a task as completed just because you read or understood the description

7. **Handle the outcome**

   **If the task completes successfully:**
   - Update the task's status to `completed` in TASKS.yaml

   **If the task is blocked by an external issue:**
   - Update the task's status to `blocked` in TASKS.yaml
   - Add an entry to ISSUES.yaml:
     ```yaml
     - name: "descriptive-issue-name"
       description: "Clear description of the blocking issue and what would resolve it"
       discovered_during: "task-name"
       status: open
     ```
   - If the blocker is infrastructure-related (not project-specific), also file on keystone via `/deepwork agent_builder.issue`

   **If the task fails for a non-external reason:**
   - Retry once with a different approach if possible
   - If still failing, mark as `blocked` and document the issue

### Important guidelines

- **Single task only.** This session handles one task. Do not process other pending tasks.
- **Keep TASKS.yaml consistent.** Follow the schema in `steps/shared/tasks_schema.md`. Only valid statuses: `pending`, `in_progress`, `completed`, `blocked`. Do NOT rename fields, add new fields, or restructure the file.
- **Never mark completed without evidence.** If you cannot describe what you did and what changed in the system, the task is not complete. Go back and do the work.
- **Issues are for external blockers only.** A coding bug in your own work is not an issue — fix it. An issue is something like "package X is not installed" or "cannot reach service Y".
- **Infrastructure issues go to keystone.** When you encounter a non-project infrastructure problem (auth expired, NixOS config error, missing dev shell, service permission denied, etc.), file it on the admin's repo using `/deepwork agent_builder.issue` with a description of the problem. This creates a tracked GitHub issue on ncrmro/keystone assigned to the admin. Do NOT silently swallow infrastructure issues or only document them locally in ISSUES.yaml — the admin needs visibility.
- **Preserve existing entries.** Do not remove or reorder other tasks. Only update the status of the task you're working on.
- **Validate after writing.** After modifying TASKS.yaml, run `yq e '.' TASKS.yaml` to confirm valid YAML.
- **Nix-managed configs are immutable.** This system uses NixOS and home-manager. Config files in `/nix/store/` or symlinked from it cannot be edited directly. If a task requires config changes to Nix-managed files, mark it as blocked, document in ISSUES.yaml, and file on keystone via `/deepwork agent_builder.issue`.

## Output Format

### TASKS.yaml

The updated task file with this task's status changed.

**Structure**:

```yaml
tasks:
  - name: "previous-task"
    description: "A previously completed task"
    status: completed
  - name: "this-task"
    description: "The task that was just executed"
    status: completed # or blocked
    project: "agent-space"
    source: "github-issue"
    source_ref: "https://github.com/ncrmro/agent-space/issues/5"
```

### ISSUES.yaml

Updated only if the task was blocked.

```yaml
issues:
  - name: "descriptive-issue-name"
    description: "Cannot send email — himalaya SMTP config uses wrong outgoing folder name"
    discovered_during: "send-weekly-report"
    status: open
```

If no issues:

```yaml
issues: []
```

## Quality Criteria

- The specified task's status has been changed from pending/in_progress to completed or blocked
- If blocked, a corresponding entry exists in ISSUES.yaml with a clear description
- No other tasks were modified or removed
- TASKS.yaml and ISSUES.yaml are valid YAML

## Context

This is the core execution step. Each task runs in its own isolated Claude Code session. The model is pre-assigned by the prioritize step (stored in the task's `model` field in TASKS.yaml). Task logs are saved to per-task log files by the orchestrator. The report step follows to document what happened.
