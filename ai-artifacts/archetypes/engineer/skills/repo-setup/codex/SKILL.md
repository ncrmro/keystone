---
name: repo-setup
description: "Start the repo/setup DeepWork workflow to make a repo ready for work"
---

Start the repo/setup DeepWork workflow to make a repo ready for work.

Use the DeepWork MCP tools to start the workflow:
- job_name: "repo"
- workflow_name: "setup"
- goal: "$ARGUMENTS" (optional, a specific repo path or name)

Follow the workflow instructions returned by the MCP server. This ensures the repo follows team conventions: labels, branch protection, milestones, and project boards.

## Codex skill invocation

Use this skill when the user invokes `$repo-setup` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
