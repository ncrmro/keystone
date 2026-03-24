---
name: sweng-implement
description: "Start the sweng/implement DeepWork workflow for a new feature or capability"
---

Start the sweng/implement DeepWork workflow for a new feature or capability.

Use the DeepWork MCP tools to start the workflow:
- job_name: "sweng"
- workflow_name: "implement"
- goal: "$ARGUMENTS" (task source: TASKS.yaml entry, user description, or issue URL)

Follow the workflow instructions returned by the MCP server. This handles the full lifecycle: plan, assign agent (agentctl), review, CI gate, merge, and clean up. Branch prefix: feat/.

## Codex skill invocation

Use this skill when the user invokes `$sweng-implement` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
