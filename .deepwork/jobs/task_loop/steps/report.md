# Report Results

## Objective

Write a brief execution report documenting what happened with the task: what was done, the outcome, and any issues encountered.

## Task

Read the updated TASKS.yaml and ISSUES.yaml from the execute step and produce a concise report for this single task. This report serves as a log entry for the task execution and MUST be formatted as valid JSON to allow downstream parsing.

### Process

1. **Read the updated files**
   - Read TASKS.yaml from the working directory
   - Read ISSUES.yaml from the working directory
   - Identify the task that was just processed (it should be the one with status `completed` or `blocked` that was most recently changed)

2. **Write the report**
   - Provide the requested JSON object detailing what was attempted, the outcome, and any related artifacts created.
   - Do NOT wrap the JSON in markdown code blocks, do not add introductory text. Only return the valid JSON string.

## Output Format

### task_report.json

A JSON object matching the following schema.

**Structure**:

```json
{
  "task_name": "string (the name of the task)",
  "status": "completed | blocked",
  "message": "string (Detailed description of what was done or what went wrong)",
  "issues_or_blockers": [
    "string (Descriptions of issues encountered or IDs from ISSUES.yaml)"
  ],
  "pull_requests_created": [
    "string (URLs or branch names of PRs created during this task)"
  ],
  "issues_created": ["string (URLs or titles of any new issues opened)"]
}
```

**Concrete example (completed)**:

```json
{
  "task_name": "reply-to-nicholas-timeline",
  "status": "completed",
  "message": "Read the original email via himalaya. Composed a reply with the updated timeline and sent it to nicholas.romero@ncrmro.com.",
  "issues_or_blockers": [],
  "pull_requests_created": [],
  "issues_created": []
}
```

**Concrete example (blocked)**:

```json
{
  "task_name": "deploy-grafana-dashboards",
  "status": "blocked",
  "message": "Attempted to authenticate to Grafana API at grafana.ncrmro.com but no credentials or API key were found in environment variables or config files.",
  "issues_or_blockers": [
    "grafana-credentials-missing: No API key found for Grafana. Needs to be provisioned."
  ],
  "pull_requests_created": [],
  "issues_created": []
}
```

## Quality Criteria

- The output MUST be strictly valid, parsable JSON without markdown wrapping (no ` ```json ` tags).
- The report correctly states whether the task was completed or blocked.
- If blocked, the report includes enough detail for a human to understand and resolve the blocker.
- The `message` property accurately reflects what was done during execution.
- Any references to ISSUES.yaml entries are properly included in the `issues_or_blockers` array.

## Context

This is the final step in a single-task run. The JSON report provides a machine-parsable record of what happened, allowing dashboards and orchestrators to index blockers, PRs, and completion states natively.
