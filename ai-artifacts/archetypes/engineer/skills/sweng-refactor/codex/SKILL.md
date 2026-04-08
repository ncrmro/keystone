---
name: sweng-refactor
description: "Start the sweng/refactor DeepWork workflow for code restructuring without behavior change"
---

Start the sweng/refactor DeepWork workflow for code restructuring without behavior change.

Use the DeepWork MCP tools to start the workflow:
- job_name: "sweng"
- workflow_name: "refactor"
- goal: "$ARGUMENTS" (task source: TASKS.yaml entry, user description, or issue URL)

Follow the workflow instructions returned by the MCP server. This handles the refactoring lifecycle: plan refactor, assign agent (agentctl), review, CI gate, merge, and clean up. Branch prefix: refactor/.

## Codex skill invocation

Use this skill when the user invokes `$sweng-refactor` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
