---
name: agent-onboard
description: "Start the agent_builder/onboard DeepWork workflow to onboard an agent to services"
---

Start the agent_builder/onboard DeepWork workflow to onboard an agent to services.

Use the DeepWork MCP tools to start the workflow:
- job_name: "agent_builder"
- workflow_name: "onboard"
- goal: "$ARGUMENTS" (agent name to onboard)

Follow the workflow instructions returned by the MCP server. This signs into all configured services (Google, GitHub, Forgejo, Vaultwarden) and configures the agent's local CLIs.

## Codex skill invocation

Use this skill when the user invokes `$agent-onboard` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
