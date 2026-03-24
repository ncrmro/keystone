---
name: notes-project
description: "Start the notes/project_hub DeepWork workflow to create or refresh a project hub note"
---

Start the notes/project_hub DeepWork workflow to create or refresh a project hub note.

Use the DeepWork MCP tools to start the workflow:
- job_name: "notes"
- workflow_name: "project_hub"
- goal: "$ARGUMENTS" (the project name or slug)

Follow the workflow instructions returned by the MCP server. This ensures the
project has one active hub note with the standard sections, canonical tags, and
links to related reports, decisions, and repos.

## Codex skill invocation

Use this skill when the user invokes `$notes-project` or asks for this workflow implicitly.
Interpret `$ARGUMENTS` as any text that follows the skill mention. If the user did not
provide extra text, continue without additional arguments.
