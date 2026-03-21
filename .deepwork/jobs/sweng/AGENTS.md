# Software Engineering Job

This job manages the software engineering lifecycle with agent orchestration:
architecture design, implementation, bug fixes, refactoring, and dev environment auditing.

## Slash Commands

The workflows are accessible as Claude Code slash commands:

- `/sweng.design <goal>` — Create an architecture/design document
- `/sweng.implement <task>` — Full implementation lifecycle (plan → agent → review → merge)
- `/sweng.fix <bug>` — Bug fix lifecycle (plan → agent → review → merge)
- `/sweng.refactor <goal>` — Refactoring lifecycle (plan → agent → review → merge)
- `/sweng.audit [repo_path]` — Audit dev environment against keystone conventions

## Workflows

| Workflow | Steps | Purpose |
|----------|-------|---------|
| `design` | design | Standalone architecture/design document |
| `implement` | plan → assign → review → postflight | New feature lifecycle |
| `fix` | plan → assign → review → postflight | Bug fix lifecycle |
| `refactor` | plan → assign → review → postflight | Refactoring lifecycle |
| `audit` | audit | Dev environment health check |

## Key Conventions

- **Agent orchestration**: Sub-agents launched via `agentctl` with TASK.md as contract
- **Task types**: `implement` (feat/), `fix` (fix/), `refactor` (refactor/) — determines branch prefix
- **Dual-platform**: GitHub (gh) and Forgejo (fj), auto-detected from git remote URL
- **Scope control**: Every change must trace to an acceptance criterion — out-of-scope = FAIL
- **Fix loop**: Max 3 attempts before marking blocked
- **Audit checks**: devshell, git conventions, TDD path, CI pipeline

## Convention Dependencies

This job integrates several keystone conventions. Steps reference them by name:
- `process.feature-delivery` — Branch naming, worktrees, draft PR, squash merge
- `process.version-control` — Conventional commits, commit discipline
- `process.continuous-integration` — CI gating, log handling, fix loop
- `process.pull-request` — PR body format (Goal, Changes, Demo, Tasks)
- `process.copilot-agent` — Copilot review on GitHub PRs
- `process.code-review-ownership` — CODEOWNERS and reviewer assignment
- `tool.nix-devshell` — Flake.nix, .envrc, direnv conventions (audit)
- `process.project-board` — Issue board transitions (In Progress, In Review, Done, Blocked)

## Project Board Integration

Every step that changes issue state MUST also update the project board column:
- **plan**: Issue comment + move to "In Progress" when branch created
- **review**: Move to "In Review" when PR marked ready for review
- **review (failure)**: Move back to "Backlog" when max fix attempts exceeded
- **postflight**: Move to "Done" on Forgejo (GitHub auto-handles via built-in workflows)

GitHub project boards require looking up field/option IDs via `gh project field-list`
before setting statuses — these IDs are project-specific and MUST NOT be hardcoded.

Forgejo has no project board API — use `forgejo-project` CLI for all board operations.

## Platform Detection

Platform is inferred from git remote URL at runtime:
- `*github.com*` → github → use `gh` CLI
- `*git.ncrmro.com*` → forgejo → use `fj` CLI + `forgejo-project` for boards

## Bespoke Learnings

### v2.0.0 — Redesign (2026-03-21)

- Redesigned from single `sweng` workflow to 5 distinct workflows: design, implement, fix, refactor, audit
- Added `task_type` field to TASK.md frontmatter to track workflow semantics
- Implement/fix/refactor share the same step pipeline — the difference is the branch prefix and review focus
- Design and audit are standalone steps that don't launch sub-agents
- The audit workflow serves as a pre-flight check — if it fails, implement/fix/refactor will hit friction

### v2.1.x — Deploy preview verification + PR Demo (2026-03-21)

- For projects deploying to Cloudflare Workers (like ks-systems-web), preview environments are created on every push
- The review step now verifies deployed preview behavior — CI passing alone is not sufficient
- This applies to any platform with preview deployments: Cloudflare Workers, Vercel, Netlify
- Preview URL is typically found in PR comments from the platform's bot
- The PR's `# Demo` section MUST be updated with the preview URL and verification evidence — this ties the deploy check back to the `process.pull-request` convention and provides a complete user story from code → deploy → verified

### v2.1.x — Cloudflare Workers preview URL patterns (2026-03-21)

Discovered from ks-systems-web PR #11 deployment:

- **Branch preview URL**: `https://{branch-slug}-{project}.{account}.workers.dev`
  - Branch name slugified: `feat/keystone-docs-pipeline` → `feat-keystone-docs-pipeline`
  - Example: `https://feat-keystone-docs-pipeline-ks-systems-web.ncrmro.workers.dev`
- **Commit preview URL**: `https://{commit-hash-prefix}-{project}.{account}.workers.dev`
  - Example: `https://e5e23e00-ks-systems-web.ncrmro.workers.dev`
- Preview URLs are posted by the Cloudflare bot as a PR comment with a markdown table
- Parse with: `gh pr view --json comments --jq '.comments[].body' | grep workers.dev`
- **CF Workers Builds limitations**:
  - Only runs `pnpm build` (or configured build command) — no multi-step builds
  - Does NOT support git submodules — submodule dirs are empty
  - Does NOT support `tsx` or custom TypeScript runners outside node_modules
  - Build scripts that need submodules or tsx must use `|| true` to fail gracefully
  - Production deploys should go through GitHub Actions where you control the full pipeline

### v2.1.x — CI secrets checking + CF Workers setup (2026-03-21)

- Review step now checks `gh secret list` / `gh variable list` when CI fails — missing secrets are a common root cause on new repos
- After secrets are configured, the review step offers `gh run rerun $RUN_ID` to retry
- Audit step now includes platform secrets audit (Step 5b) for CF Workers projects
- CF Workers + Next.js (OpenNext.js) project setup requires:
  1. `wrangler.jsonc` with worker config, R2 bindings
  2. `open-next.config.ts` for the adapter
  3. GitHub Actions secrets/variables for db credentials etc.
  4. Wrangler secrets set from server via `wrangler secret put`
  5. CF Workers Builds git integration in Cloudflare dashboard
- The existing `tool.cloudflare-workers` keystone convention (see `conventions/tool.cloudflare-workers.md`) should be expanded to cover: OpenNext.js patterns, GitHub Actions deploy workflows, secrets setup, and preview environment patterns. Use `ks.convention` to update it.

### v1.1.0 — Project board integration (2026-03-19)

- Added project board column transitions to all sweng steps
- GitHub project boards require field/option ID lookups — never hardcode these
- Forgejo board operations use `forgejo-project` CLI (no REST API exists)

## Editing Guidelines

1. **Use workflows** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks
3. **Run `/deepwork learn`** after executing the workflow to capture new learnings
