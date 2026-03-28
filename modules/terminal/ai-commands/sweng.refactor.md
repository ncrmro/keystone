---
description: Start the sweng/refactor DeepWork workflow for code restructuring without behavior change
argument-hint: <task source>
---

Start the sweng/refactor DeepWork workflow for code restructuring without behavior change.

Use the DeepWork MCP tools to start the workflow:

- job_name: "sweng"
- workflow_name: "refactor"
- goal: "$ARGUMENTS" (task source: TASKS.yaml entry, user description, or issue URL)

Follow the workflow instructions returned by the MCP server. This handles the refactoring lifecycle: plan refactor, assign agent (agentctl), review, CI gate, merge, and clean up. Branch prefix: refactor/.
