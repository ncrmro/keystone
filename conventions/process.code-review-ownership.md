<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->
# Convention: Code Review Ownership (process.code-review-ownership)

This convention defines code ownership areas, maps them to team roles from `TEAM.md`, and ensures the right reviewers are automatically notified when a PR is ready for review. It relies on CODEOWNERS files for both GitHub and Forgejo, with the task loop's notification-driven ingestion as the discovery mechanism.

## Ownership Matrix

1. Code ownership MUST be defined by team role (CPO, CTO, CEO), not by hardcoded usernames.
2. Usernames for each role MUST be resolved from `TEAM.md` using the platform-appropriate column (GitHub column for GitHub repos, Forgejo column for Forgejo repos).
3. The ownership areas MUST follow this matrix:

| Area | File Patterns | Reviewer Role(s) |
|------|--------------|-------------------|
| Documentation & content | `docs/`, `specs/`, `blog/`, non-root `*.md` | CPO |
| Infrastructure & Nix | `*.nix`, `flake.*`, `modules/`, `hosts/` | CTO, CEO |
| CI/CD pipelines | `.github/workflows/`, `.forgejo/workflows/`, `Makefile`, `Dockerfile`, `docker-compose.*` | CTO, CEO |
| Application source code | `src/`, `packages/`, `*.ts`, `*.rs`, `*.py`, `*.go` | CTO |
| Agent & root config | `CLAUDE.md`, `TEAM.md`, `SOUL.md`, `AGENTS.md` | CEO |

4. When a file matches multiple ownership areas, ALL matching owners MUST be requested as reviewers.
5. The CPO SHOULD be added as reviewer for any PR that modifies cross-references between documentation files, even if the PR is primarily code.

## CODEOWNERS Files

6. Every repository MUST contain a CODEOWNERS file implementing the ownership matrix.
7. On GitHub, the CODEOWNERS file MUST use glob patterns and be placed at the repo root or in `.github/CODEOWNERS`.
8. On Forgejo, the CODEOWNERS file MUST use Go regex patterns and be placed at the repo root or in `.forgejo/CODEOWNERS`.
9. CODEOWNERS files MUST use usernames resolved from `TEAM.md` for the target platform.
10. CODEOWNERS files MUST be regenerated when `TEAM.md` role assignments or usernames change.
11. CODEOWNERS files SHOULD include a comment header referencing this convention and `TEAM.md` as the source of truth.

## Notification-Driven Discovery

12. On both GitHub and Forgejo, CODEOWNERS MUST be relied upon to auto-request reviews when a PR is created or undrafted.
13. The task loop's pre-fetch phase discovers review requests via the platform notifications API (GitHub: `gh api /notifications`, Forgejo: notifications endpoint), filtering for review-requested notifications — see `process.agent-cronjobs` for task loop details.
14. Agents MUST NOT poll for review assignments outside the task loop.
15. The notification-driven flow via CODEOWNERS is the sole discovery mechanism for PR review requests.

## Interaction with Existing Conventions

16. This convention extends `process.feature-delivery` rules 21-23 by codifying which reviewers are "appropriate" for each file area.
17. Copilot reviews per `process.copilot-agent` remain supplementary and MAY be requested in addition to ownership-based reviewers.
18. The `code-reviewer` role in `archetypes.yaml` SHOULD list this convention so agents in code-review mode have the ownership matrix available.

## Golden Example

### GitHub CODEOWNERS (`.github/CODEOWNERS`)

Usernames resolved from `TEAM.md` GitHub column:

```
# CODEOWNERS — Source of truth: TEAM.md
# Convention: process.code-review-ownership
#
# Roles → GitHub usernames (from TEAM.md):
#   CEO: ncrmro
#   CPO: luce-ncrmro
#   CTO: kdrgo

# Documentation & content — CPO reviews
docs/                    @luce-ncrmro
specs/                   @luce-ncrmro
blog/                    @luce-ncrmro

# Infrastructure & Nix — CTO + CEO review
*.nix                    @kdrgo @ncrmro
flake.*                  @kdrgo @ncrmro
modules/                 @kdrgo @ncrmro
hosts/                   @kdrgo @ncrmro

# CI/CD — CTO + CEO review
.github/                 @kdrgo @ncrmro
Makefile                 @kdrgo @ncrmro
Dockerfile               @kdrgo @ncrmro
docker-compose*          @kdrgo @ncrmro

# Application source — CTO reviews
src/                     @kdrgo
packages/                @kdrgo

# Agent & root config — CEO reviews
/CLAUDE.md               @ncrmro
/TEAM.md                 @ncrmro
/SOUL.md                 @ncrmro
/AGENTS.md               @ncrmro
```

### Forgejo CODEOWNERS (`.forgejo/CODEOWNERS`)

Usernames resolved from `TEAM.md` Forgejo column. Uses Go regex patterns:

```
# CODEOWNERS — Source of truth: TEAM.md
# Convention: process.code-review-ownership
#
# Roles → Forgejo usernames (from TEAM.md):
#   CEO: ncrmro
#   CPO: luce
#   CTO: drago

# Documentation & content — CPO reviews
docs/.* @luce
specs/.* @luce
blog/.* @luce

# Infrastructure & Nix — CTO + CEO review
.*\.nix$ @drago @ncrmro
flake\..* @drago @ncrmro
modules/.* @drago @ncrmro
hosts/.* @drago @ncrmro

# CI/CD — CTO + CEO review
\.forgejo/workflows/.* @drago @ncrmro
Makefile @drago @ncrmro
Dockerfile @drago @ncrmro
docker-compose.* @drago @ncrmro

# Application source — CTO reviews
src/.* @drago
packages/.* @drago

# Agent & root config — CEO reviews
^CLAUDE\.md$ @ncrmro
^TEAM\.md$ @ncrmro
^SOUL\.md$ @ncrmro
^AGENTS\.md$ @ncrmro
```

### End-to-End Flow

```
1. Developer pushes PR touching src/api/handler.ts
2. GitHub reads CODEOWNERS → matches src/ → @kdrgo (CTO)
3. GitHub auto-requests review from @kdrgo
4. GitHub creates notification: reason=review_requested
5. Task loop pre-fetch: gh api /notifications → finds review request
6. Task loop ingest: creates task in TASKS.yaml
7. Agent executes review in code-reviewer role
```
