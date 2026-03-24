---
name: agent-issue
description: "Start the agent_builder/issue DeepWork workflow to file an infrastructure issue"
---

Start the agent_builder/issue DeepWork workflow to file an infrastructure issue.

Use the DeepWork MCP tools to start the workflow:
- job_name: "agent_builder"
- workflow_name: "issue"
- goal: "$ARGUMENTS" (description of the infrastructure problem, e.g., 'scheduler permission denied')

Follow the workflow instructions returned by the MCP server. This drafts a GitHub issue with title, body, labels, and assignee for the admin's nixos-config repo (ncrmro/keystone) to address agent-space blockers.

## Codex skill invocation

Use this skill when the user invokes `$agent-issue` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
