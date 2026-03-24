---
name: research-quick
description: "Start the research/quick DeepWork workflow for a fast, local-only research summary"
---

Start the research/quick DeepWork workflow for a fast, local-only research summary.

Use the DeepWork MCP tools to start the workflow:
- job_name: "research"
- workflow_name: "quick"
- goal: "$ARGUMENTS" (the research topic or question)

Follow the workflow instructions returned by the MCP server. This produces a concise research summary using 3+ sources via local web search tools (WebSearch, WebFetch).

## Codex skill invocation

Use this skill when the user invokes `$research-quick` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
