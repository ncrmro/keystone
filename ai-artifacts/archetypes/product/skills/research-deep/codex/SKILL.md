---
name: research-deep
description: "Start the research/deep DeepWork workflow for a comprehensive multi-platform investigation"
---

Start the research/deep DeepWork workflow for a comprehensive multi-platform investigation.

Use the DeepWork MCP tools to start the workflow:
- job_name: "research"
- workflow_name: "deep"
- goal: "$ARGUMENTS" (the research topic or question)

Follow the workflow instructions returned by the MCP server. This produces a full report with 8+ diverse sources, multi-platform synthesis (Gemini, ChatGPT, Grok, Perplexity), and a categorized bibliography.

## Codex skill invocation

Use this skill when the user invokes `$research-deep` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
