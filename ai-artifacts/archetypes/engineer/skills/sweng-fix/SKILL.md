---
name: sweng-fix
description: "Start the sweng/fix DeepWork workflow to fix a bug or issue"
---

Start the sweng/fix DeepWork workflow to fix a bug or issue.

Use the DeepWork MCP tools to start the workflow:
- job_name: "sweng"
- workflow_name: "fix"
- goal: "$ARGUMENTS" (task source: TASKS.yaml entry, user description, or issue URL)

Follow the workflow instructions returned by the MCP server. This handles the full bug fix lifecycle: plan fix, assign agent (agentctl), review, CI gate, merge, and clean up. Branch prefix: fix/.
