---
name: sweng-design
description: "Start the sweng/design DeepWork workflow to create an architecture/design document"
---

Start the sweng/design DeepWork workflow to create an architecture/design document.

Use the DeepWork MCP tools to start the workflow:
- job_name: "sweng"
- workflow_name: "design"
- goal: "$ARGUMENTS" (what to design — a feature, system change, or architectural question)

Follow the workflow instructions returned by the MCP server. This produces an architecture/design document with diagrams, trade-offs, constraints, and an implementation plan.

## Codex skill invocation

Use this skill when the user invokes `$sweng-design` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
