Route engineering requests to the appropriate DeepWork workflow.

Use this skill for implementation tasks, code review, architecture decisions,
bug fixes, refactoring, and CI/CD work.

## Supporting references

Before starting implementation, review the relevant convention files
(co-located in this skill directory) for standards and process:

- **Software engineer role**: [software-engineer.md](software-engineer.md) -- implementation behavior, scope discipline, output format
- **Code reviewer role**: [code-reviewer.md](code-reviewer.md) -- review focus, security checks, style enforcement
- **Architect role**: [architect.md](architect.md) -- system design, trade-off analysis, spec writing
- **Feature delivery**: [process.feature-delivery.md](process.feature-delivery.md) -- end-to-end lifecycle from issue through merged PR
- **Pull requests**: [process.pull-request.md](process.pull-request.md) -- PR structure, squash merge rules, demo requirements
- **Code review ownership**: [process.code-review-ownership.md](process.code-review-ownership.md) -- review assignment and approval flow
- **Continuous integration**: [process.continuous-integration.md](process.continuous-integration.md) -- CI pipeline standards
- **Refactoring**: [process.refactor.md](process.refactor.md) -- safe refactoring process
- **Version control**: [process.version-control.md](process.version-control.md) -- commit discipline, conventional commits
- **Version control (advanced)**: [process.version-control-advanced.md](process.version-control-advanced.md) -- rebase, conflict resolution, lock files
- **VCS context continuity**: [process.vcs-context-continuity.md](process.vcs-context-continuity.md) -- PR progress tracking and resumability
- **Git repos**: [process.git-repos.md](process.git-repos.md) -- repo cloning, worktree layout
- **Shell scripts**: [code.shell-scripts.md](code.shell-scripts.md) -- shell script standards
- **Code comments**: [code.comments.md](code.comments.md) -- commenting standards
- **Nix devshell**: [tool.nix-devshell.md](tool.nix-devshell.md) -- project-specific Nix environments

## Available workflows

- **engineer/implement** -- implement a feature, fix, or refactor with TDD and quality gates
- **engineer/doctor** -- diagnose and fix engineering environment issues

## Routing rules

- Implementation tasks, feature work, bug fixes --> `engineer/implement`
- Code review requests --> read `code-reviewer.md`, then review directly
- Architecture or design questions --> read `architect.md`, then answer directly or start `engineer/implement` for spec-driven work
- Engineering environment issues --> `engineer/doctor`
- Keystone module or convention changes --> use `/ks.system` instead
- Filing issues for discovered problems --> use `/ks.system` instead
- If unclear, ask the user which workflow to run before starting

## How to start a workflow

1. Call `get_workflows` to confirm available workflows.
2. Call `start_workflow` with `job_name: "engineer"`, `workflow_name: <chosen>`, and `goal: "$ARGUMENTS"`.
3. Follow the step instructions returned by the MCP server.
