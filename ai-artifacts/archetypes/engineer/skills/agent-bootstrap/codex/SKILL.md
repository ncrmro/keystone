---
name: agent-bootstrap
description: "Start the agent_builder/bootstrap DeepWork workflow to create a new agent-space repo"
---

Start the agent_builder/bootstrap DeepWork workflow to create a new agent-space repo.

Use the DeepWork MCP tools to start the workflow:
- job_name: "agent_builder"
- workflow_name: "bootstrap"
- goal: "$ARGUMENTS" (agent name, owner/org, and repo name)

Follow the workflow instructions returned by the MCP server. This creates a new agent-space from scratch with identity (SOUL.md), roles, conventions, and task loop files.

## Codex skill invocation

Use this skill when the user invokes `$agent-bootstrap` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
