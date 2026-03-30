---
repo: ncrmro/keystone
branch: refactor/presentation-job
agent: claude
platform: github
task_type: refactor
status: completed
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

- [x] `executive_assistant` no longer declares `presentation` or `slide_deck`
      workflows or presentation-specific steps in its `job.yml`
- [x] A new `.deepwork/jobs/presentation/` job exists with its own `job.yml`,
      `AGENTS.md`, and presentation step instruction files
- [x] The new `presentation` job exposes a primary `presentation` workflow and a
      `slide_deck` workflow with equivalent behavior to the pre-refactor paths
- [x] Shared context in the new job is presentation-specific and does not rely
      on `executive_assistant`-only guidance
- [x] DeepWork workflow discovery and repo validation still succeed

## Key Files

- .deepwork/jobs/executive_assistant/job.yml — remove presentation workflows and
  step definitions from the old job
- .deepwork/jobs/executive_assistant/AGENTS.md — update job guidance after the
  split
- .deepwork/jobs/presentation/job.yml — new standalone presentation job
- .deepwork/jobs/presentation/AGENTS.md — job-specific guidance and learnings
- .deepwork/jobs/presentation/steps/*.md — moved presentation and slide deck
  instructions

## Agent Notes

- Created a standalone `presentation` DeepWork job and moved both
  `presentation` and `slide_deck` step files under it.
- Bumped `executive_assistant` to `2.0.0` because removing workflows is a
  breaking job-structure change.
- Updated the REQ-023 spec so `/ks.assistant` routing treats presentation as a
  separate job instead of an executive-assistant workflow.
- The `sweng/refactor` workflow's assign step expects `agentctl ... --worktree`,
  but the current `agentctl` interface no longer supports that flag. I
  implemented directly in the prepared worktree and recorded the mismatch here.

## Results

- `nix flake check` passed in
  `/home/ncrmro/.worktrees/ncrmro/keystone/refactor/presentation-job`
- `yq -o=json eval '.' .deepwork/jobs/executive_assistant/job.yml` passed
- `yq -o=json eval '.' .deepwork/jobs/presentation/job.yml` passed
