---
name: ks-issue
description: "Start the keystone_system/issue DeepWork workflow to create a GitHub issue"
---

Start the keystone_system/issue DeepWork workflow to create a GitHub issue.

Use the DeepWork MCP tools to start the workflow:
- job_name: "keystone_system"
- workflow_name: "issue"
- goal: "$ARGUMENTS" (use the user's arguments as the feature description)

Follow the workflow instructions returned by the MCP server. This researches the codebase and creates a GitHub issue with context, affected modules, suggested RFC 2119 requirements, and acceptance criteria. No local files are created.
