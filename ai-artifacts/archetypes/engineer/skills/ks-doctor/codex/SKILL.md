---
name: ks-doctor
description: "Start the keystone_system/doctor DeepWork workflow to check fleet health"
---

Start the keystone_system/doctor DeepWork workflow to check fleet health.

Use the DeepWork MCP tools to start the workflow:
- job_name: "keystone_system"
- workflow_name: "doctor"
- goal: "$ARGUMENTS" (use the user's arguments as context, or "Check all hosts are nominal" if no arguments)

Follow the workflow instructions returned by the MCP server. This runs ks doctor across all hosts and reports fleet health status.

## Codex skill invocation

Use this skill when the user invokes `$ks-doctor` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
