---
repo: ncrmro/keystone
branch: refactor/presentation-job
agent: claude
platform: github
task_type: refactor
status: ready
created: 2026-03-30
---

# Split presentation DeepWork job from executive assistant

## Description

Refactor the DeepWork job layout so presentation creation no longer lives under
`executive_assistant`. Create a standalone `presentation` job that owns the
presentation-specific shared context, workflows, and steps, including a
`slide_deck` workflow. Preserve existing presentation behavior while reducing
scope overlap inside the executive assistant job.

Tech stack: Nix-based monorepo with DeepWork job specs in `.deepwork/jobs/*`,
Markdown step instructions, generated workflow discovery, and repo-native
validation through `nix flake check`.

## Acceptance Criteria

- [ ] `executive_assistant` no longer declares `presentation` or `slide_deck`
      workflows or presentation-specific steps in its `job.yml`
- [ ] A new `.deepwork/jobs/presentation/` job exists with its own `job.yml`,
      `AGENTS.md`, and presentation step instruction files
- [ ] The new `presentation` job exposes a primary `presentation` workflow and a
      `slide_deck` workflow with equivalent behavior to the pre-refactor paths
- [ ] Shared context in the new job is presentation-specific and does not rely
      on `executive_assistant`-only guidance
- [ ] DeepWork workflow discovery and repo validation still succeed

## Key Files

- .deepwork/jobs/executive_assistant/job.yml — remove presentation workflows and
  step definitions from the old job
- .deepwork/jobs/executive_assistant/AGENTS.md — update job guidance after the
  split
- .deepwork/jobs/presentation/job.yml — new standalone presentation job
- .deepwork/jobs/presentation/AGENTS.md — job-specific guidance and learnings
- .deepwork/jobs/presentation/steps/*.md — moved presentation and slide deck
  instructions
