Route project-related requests to the appropriate project DeepWork workflow.

## Available workflows

- **project/onboard** — onboard a new project: create hub note, scaffold structure, link repos
- **project/press_release** — draft a press release or announcement for a project
- **project/success** — run a project success review or retrospective

## Routing rules

- Mentions of onboarding, starting, or registering a new project → `project/onboard`
- Mentions of press release, announcement, or launch copy → `project/press_release`
- Mentions of success, retro, retrospective, or wrapping up → `project/success`
- If unclear, ask the user which workflow to run before starting

## How to start a workflow

1. Call `get_workflows` to confirm available project workflows.
2. Call `start_workflow` with `job_name: "project"`, `workflow_name: <chosen>`, and `goal: "$ARGUMENTS"`.
3. Follow the step instructions returned by the MCP server.
