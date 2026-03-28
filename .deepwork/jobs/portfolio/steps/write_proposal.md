# Write Milestone Proposal

## Objective

Synthesize the repo snapshot into a concrete, actionable milestone proposal. The proposal
must be grounded in actual repo data — not invented — and give the user a clear picture of
what the milestone would accomplish and why it makes sense.

## Task

Read `repo_snapshot.md` and produce a milestone proposal that answers:
1. What is the proposed milestone called?
2. What is its scope (specific issues or work items)?
3. Why does this milestone make sense given the project's current state?
4. When should it be due?

### Decision Framework

Use the following signals to shape the proposal:

**If the project has recent activity (commits within 90 days) and open issues:**
→ Propose a milestone that captures the in-flight work. Title it around the most
  common theme in recent commits (e.g., "v0.2 — stability and polish" if commits
  are mostly bug fixes). Scope it with the existing open issues.

**If the project has a clear version history (releases/tags) but no new release:**
→ Propose the next logical version milestone. If the last release was `v0.1.0`,
  propose `v0.2.0` scoped around the open issues and recent commit themes.

**If the project has a charter with stated goals:**
→ Align the milestone with the charter's stated goals. Propose a milestone that
  moves toward the charter's first or next stated goal.

**If the project has no recent activity (0 commits in 180 days):**
→ Propose a lightweight "project health review" milestone:
  - Scope: decide to continue, pivot, or archive
  - Include: run `project/success` to evaluate viability, update README/charter
  - This avoids inventing work for a project that may be intentionally dormant

**If the project has no issues and no recent commits:**
→ Propose a "scope definition" milestone:
  - Scope: read README, identify 3-5 core feature gaps, create issues for each
  - Title: "[Project] initial scope definition"
  - This gives the project a foundation before assigning real work

### Output Constraints

- Do NOT invent issues that don't exist in the repo — only reference real issues by number
- Do NOT invent commit activity — only reference commits actually in the snapshot
- If no real scope can be derived, say so explicitly and propose the health-review milestone
- Keep the proposal concise — the goal is to create a milestone, not a project plan

## Output Format

### milestone_proposal.md

```markdown
# Milestone Proposal — {project_slug}

## Proposed Milestone

**Title**: v0.2 — Stability and Import Fixes
**Suggested due date**: 2026-05-01 (or: none)

## Scope

Issues to include:
- #12 Crash on large file import (priority: high — affects core functionality)
- #8 Export to PDF broken (priority: medium)
- #11 Add keyboard shortcut for search (priority: low, already in progress)

Additional work (no issue yet):
- Update aiohttp dependency to 3.x (based on commit "chore: update dependencies")

## Rationale

meze has been dormant since November 2025 (102 days ago) but has 3 open issues and
a clear v0.1.0 release baseline. The most recent commits were fixing import handling
and adding a dark mode toggle. A v0.2 stability milestone would consolidate this
work and provide a clear target to reactivate development around.

The charter lists "reliable import/export" as a core goal — this milestone directly
advances that goal.

## Next Steps After Milestone Created

1. Assign open issues to the milestone
2. Run `portfolio/review_one` after 30 days to check progress
3. If no activity after 60 days, run `project/success` to evaluate viability
```

**Example: no-activity project**

```markdown
# Milestone Proposal — eonmun

## Proposed Milestone

**Title**: Project viability review
**Suggested due date**: 2026-04-30

## Scope

- [ ] Run `project/success` workflow to evaluate whether to continue, pivot, or archive
- [ ] Update README with current project status and decision
- [ ] If continuing: identify 3-5 core features and create issues for each

## Rationale

eonmun has had no commits in 220 days and no releases. There are no open issues.
Without a clear viability decision, this project creates ongoing cognitive overhead
without producing value. The recommended first step is an explicit decision, not
new feature work.

## Next Steps After Milestone Created

1. Run `project/success` for eonmun to get a structured viability assessment
2. Based on outcome: either archive the repo or create a scope definition milestone
```

## Quality Criteria

- The milestone title is specific and outcome-oriented
- Scope items reference real issues by number or specific commits from the snapshot
- The rationale explains why this milestone is the right next step
- Proposals for dormant projects recommend a health review, not invented work
