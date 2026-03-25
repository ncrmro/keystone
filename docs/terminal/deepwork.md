---
title: DeepWork
description: Workflow-driven development with quality gates for terminal users and OS agents
---

# DeepWork

[DeepWork](https://github.com/Unsupervisedcom/deepwork) is a workflow engine that structures
multi-step development processes with quality gate checkpoints. Keystone integrates it into
the terminal environment so that both human users and OS agents can run structured workflows
via the DeepWork MCP server.

## Enable

```nix
keystone.terminal.deepwork = {
  enable = true;   # Default: true
};
```

## How It Works

DeepWork organises work into **jobs** (collections of related workflows) and **workflows**
(step-by-step processes with quality gates). When the module is enabled, Keystone sets the
`DEEPWORK_ADDITIONAL_JOBS_FOLDERS` environment variable so the DeepWork MCP server
discovers both:

- **Library jobs** — curated jobs from the upstream
  [Unsupervisedcom/deepwork](https://github.com/Unsupervisedcom/deepwork) repository
  (e.g. `spec_driven_development`)
- **Keystone-native jobs** — project-specific jobs defined in `.deepwork/jobs/` inside the
  Keystone repo itself

### Available Keystone Jobs

| Job | Purpose |
|-----|---------|
| `sweng` | Software engineering workflows (design, code review, spec) |
| `research` | Multi-platform research with bibliography |
| `notes` | Note creation and inbox processing |
| `project` | Project and milestone management |
| `repo` | Repository setup and maintenance tasks |
| `task_loop` | Recurring task-loop scheduling |
| `daily_status` | Daily status report generation |

## Using DeepWork with AI Coding Agents

Interact with DeepWork through the MCP tools available in Claude Code, Gemini CLI, Codex,
and OpenCode:

1. **Discover workflows** — call `get_workflows` (or use `/deepwork.review` slash-command
   to run a review)
2. **Start a workflow** — call `start_workflow` with `job_name`, `workflow_name`, and `goal`
3. **Follow the returned instructions** — each step returns the next action to perform

### Slash Commands

| Command | Description |
|---------|-------------|
| `/deepwork.review` | Run `.deepreview` quality-gate rules against current changes |
| `/sweng.design` | Start the `sweng/design` workflow (architecture document) |
| `/research.deep` | Start the `research/deep` workflow (multi-platform investigation) |

## Development Mode

When `keystone.development = true` and the repos are checked out locally, both job folders
resolve to live checkout paths instead of Nix store copies:

- `deepwork` repo → `~/.keystone/repos/Unsupervisedcom/deepwork/library/jobs/`
- `keystone` repo → `~/.keystone/repos/<owner>/keystone/.deepwork/jobs/`

This lets you iterate on job definitions without rebuilding the system. See
[Keystone Development Mode](../../conventions/process.keystone-development-mode.md) for
details.

## References

- [DeepWork on GitHub](https://github.com/Unsupervisedcom/deepwork)
- [Keystone terminal module](terminal.md)
- [OS Agents](../agents/os-agents.md)
