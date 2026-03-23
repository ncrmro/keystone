# Write Project Summary

## Objective

Synthesize the raw data collected in the previous step into a formatted per-project
status summary with a health assessment, milestone progress, activity level, blockers,
and next actions.

## Task

Read the raw project data and produce a concise, opinionated status summary that can
be aggregated into the portfolio report.

### Process

1. **Assess overall project health**

   Determine the status indicator based on the data:

   - **🟢 On Track** — Active milestones progressing, recent commits, no critical blockers
   - **🟡 At Risk** — Milestones behind schedule, activity declining, or non-critical blockers
   - **🔴 Behind** — Milestones significantly overdue, minimal recent activity, critical blockers
   - **⚪ Not Started / Deferred** — No milestones, no recent activity, or explicitly paused

   The status MUST be justified by citing specific data points (e.g., "At Risk because
   milestone 'Desktop Integration' is at 67% with 12 days until due date and 4 open issues").

2. **Summarize milestones**

   For each open milestone:
   - Title, completion percentage, and due date
   - Highlight any that are overdue or at risk (>80% of time elapsed, <50% complete)
   - Note recently closed milestones (last 30 days) as wins

3. **Assess activity level**

   Based on git log data:
   - **High**: 10+ commits in 30 days
   - **Medium**: 3-9 commits in 30 days
   - **Low**: 1-2 commits in 30 days
   - **Stagnant**: 0 commits in 30 days

   Note the last commit date and any notable recent changes.

4. **Identify blockers**

   From milestones, open issues, and existing status files:
   - List anything blocking progress
   - Note stale PRs (open > 30 days without activity)
   - Flag missing prerequisites

5. **Build milestone Eisenhower matrix** (if project has 2+ milestones)

   Classify each open milestone into the Eisenhower quadrants:
   - **Urgent**: Has a due date approaching (within 30 days), is overdue, or has blockers
     that are time-sensitive
   - **Important**: Core to the project's mission/charter, high user impact, or is a
     dependency for other work
   - Use milestone progress, due dates, and charter alignment to make the classification

   Render as an ASCII box diagram (see Output Format below).

6. **Recommend next actions**

   Based on the data, list 2-4 concrete next actions ordered by priority.
   Actions should be specific (e.g., "Close milestone X" or "Review and merge PR #45")
   not vague (e.g., "Make progress on the project").

6. **Incorporate existing charter/status context**

   If a charter.md or status.md exists, reference it:
   - Are the charter goals still being pursued?
   - Has the status changed since the last review?
   - Any goals that should be added/removed?

## Output Format

### project_summary.md

Formatted status summary for one project.

**Structure**:
```markdown
## [Project Name]

**Status**: [🟢/🟡/🔴/⚪] [On Track/At Risk/Behind/Deferred]
**Activity**: [High/Medium/Low/Stagnant] ([N] commits in 30 days, last: [date])

### Milestones

| Milestone | Progress | Due Date | Health |
|-----------|----------|----------|--------|
| Desktop Integration | 8/12 (67%) | 2026-04-01 | 🟡 |
| v2.0 Release | 2/12 (17%) | — | ⚪ |

**Recently Completed**: Terminal Module (closed 2026-02-15)

### Milestone Priority Matrix

```
                    URGENT                          NOT URGENT
          ┌─────────────────────────┬─────────────────────────┐
          │ DO FIRST                │ SCHEDULE                │
IMPORTANT │ Desktop Integration     │ v2.0 Release            │
          │  67%, due 2026-04-01    │  17%, no due date       │
          ├─────────────────────────┼─────────────────────────┤
          │ DELEGATE                │ ELIMINATE               │
NOT       │                         │                         │
IMPORTANT │                         │                         │
          └─────────────────────────┴─────────────────────────┘
```

### Key Issues & PRs

- 4 open issues, 2 open PRs (1 draft)
- Oldest open PR: #50 (45 days, "Fix installer TUI")

### Blockers

- Installer TUI broken (PR #50, blocking fresh install testing)
- No hibernation support yet (blocks ext4 laptop conversion)

### Next Actions

1. Merge or close PR #50 (installer TUI) — blocking for 45 days
2. Complete desktop integration milestone (67% → 100%)
3. Spec out ext4 + hibernation changes for laptop conversion
```

**Example with minimal data** (no milestones, no local clone):
```markdown
## eonmun

**Status**: ⚪ Deferred
**Activity**: Stagnant (0 commits in 30 days, last: 2025-11-15)

### Milestones

No open milestones.

### Key Issues & PRs

- 0 open issues, 0 open PRs

### Blockers

- No active development

### Next Actions

1. Decide whether to reactivate or archive this project
2. If reactivating, create a milestone with initial scope
```

## Quality Criteria

- The status indicator is justified by specific data points, not gut feeling
- All open milestones are listed with completion percentage and due date
- Recent activity is summarized with commit count and last commit date
- Next actions are concrete and specific, not vague aspirations
- The summary is concise — one screenful per project, not a wall of text

## Context

This step produces the per-project building block of the portfolio report. The format
must be consistent across all projects so the synthesis step can aggregate them into
a coherent portfolio view. Keep summaries tight — the portfolio report reader wants
to scan, not read essays.
