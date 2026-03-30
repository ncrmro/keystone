Route note-related requests to the appropriate notes DeepWork workflow.

## Available workflows

- **notes/process_inbox** — review and promote fleeting notes from inbox/ to permanent notes
- **notes/doctor** — audit, repair, and normalize a zk notebook
- **notes/init** — bootstrap a new zk notes repo from scratch
- **notes/setup** — configure an existing zk notebook

## Routing rules

- Mentions of processing, reviewing, or promoting inbox notes → `notes/process_inbox`
- Mentions of repair, health check, audit, or normalize → `notes/doctor`
- Mentions of new notebook, bootstrap, or initializing → `notes/init`
- Mentions of setup or configure → `notes/setup`
- If unclear, ask the user which workflow to run before starting

## How to start a workflow

1. Call `get_workflows` to confirm available notes workflows.
2. Call `start_workflow` with `job_name: "notes"`, `workflow_name: <chosen>`, and `goal: "$ARGUMENTS"`.
3. Follow the step instructions returned by the MCP server.
