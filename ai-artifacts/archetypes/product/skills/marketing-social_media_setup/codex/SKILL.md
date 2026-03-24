---
name: marketing-social_media_setup
description: "Start the marketing/social_media_setup DeepWork workflow to set up social media"
---

Start the marketing/social_media_setup DeepWork workflow to set up social media.

Use the DeepWork MCP tools to start the workflow:
- job_name: "marketing"
- workflow_name: "social_media_setup"
- goal: "$ARGUMENTS" (project name and desired social platforms)

Follow the workflow instructions returned by the MCP server. This sets up social media credentials and content strategy for a project.

## Codex skill invocation

Use this skill when the user invokes `$marketing-social_media_setup` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
