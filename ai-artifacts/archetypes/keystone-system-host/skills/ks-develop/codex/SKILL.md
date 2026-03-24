---
name: ks-develop
description: "Start the keystone_system/develop DeepWork workflow"
---

Start the keystone_system/develop DeepWork workflow.

Use the DeepWork MCP tools to start the workflow:
- job_name: "keystone_system"
- workflow_name: "develop"
- goal: "$ARGUMENTS" (use the user's arguments as the goal)

Follow the workflow instructions returned by the MCP server. This is the full keystone development lifecycle: plan in worktree → implement → review → build → merge → deploy (human-in-the-loop) → validate all hosts.

## Codex skill invocation

Use this skill when the user invokes `$ks-develop` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
