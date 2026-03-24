---
name: task-ingest
description: "Start the task_loop/ingest DeepWork workflow to ingest tasks from source files"
---

Start the task_loop/ingest DeepWork workflow to ingest tasks from source files.

Use the DeepWork MCP tools to start the workflow:
- job_name: "task_loop"
- workflow_name: "ingest"
- goal: "$ARGUMENTS" (optional, a specific task source JSON file or directory)

Follow the workflow instructions returned by the MCP server. This parses pre-fetched source JSON and creates or updates tasks in the agent-space TASKS.yaml.

## Codex skill invocation

Use this skill when the user invokes `$task-ingest` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
