Route project-related requests to the appropriate project DeepWork workflow.

## Available workflows

- **project/onboard** — onboard a new project: create hub note, scaffold structure, link repos
- **project/press_release** — draft a press release or announcement for a project
- **project/milestone** — parse press release or scope notes, refine user stories, create milestone, and link issue
- **project/milestone_engineering_handoff** — internal FAQ, document review, optional spikes, specs, and plan issue — full engineering gate before implementation
- **project/success** — run a project success review or retrospective
- **project/doctor** — audit a project's health: hub note completeness, repo conventions, and release post coverage on the website
- **project/wrap_up** — wind down engineering work: group uncommitted changes into logical commits, push, document in notes, and check in on open issues/PRs

## Routing rules

- Mentions of onboarding, starting, or registering a new project → `project/onboard`
- Mentions of press release, announcement, or launch copy → `project/press_release`
- Mentions of milestone, planning, user stories, or sprint scope → `project/milestone`
- Mentions of engineering handoff, specs, FAQ, or implementation gate → `project/milestone_engineering_handoff`
- Mentions of success, retro, or retrospective → `project/success`
- Mentions of health audit, hub note, repo conventions, or release post coverage → `project/doctor`
- Mentions of wrap up, wind down, committing changes, or finishing a session → `project/wrap_up`
- If unclear, ask the user which workflow to run before starting

## How to start a workflow

1. Call `get_workflows` to confirm available project workflows.
2. Call `start_workflow` with `job_name: "project"`, `workflow_name: <chosen>`, and `goal: "$ARGUMENTS"`.
3. Follow the step instructions returned by the MCP server.
