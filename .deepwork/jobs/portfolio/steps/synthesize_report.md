# Synthesize Portfolio Report

## Objective

Combine all per-project summaries into a single portfolio health report with cross-project
analysis, an overall health assessment, and priority recommendations.

## Task

Read the combined per-project summaries and the project list, then produce a portfolio
report that gives the user a complete picture of where everything stands.

### Process

1. **Calculate portfolio-level metrics**

   From the per-project summaries, compute:
   - Total active projects
   - Projects by status: 🟢 On Track, 🟡 At Risk, 🔴 Behind, ⚪ Deferred
   - Total open milestones across all projects
   - Overall activity trend (how many projects have high/medium/low/stagnant activity)

2. **Build the project status table**

   Create a summary table with one row per project showing:
   - Project name
   - Status indicator
   - Active milestone (most important one) with progress
   - Activity level
   - Top blocker (if any)

   Order by priority (from the project list), or by status severity if no priority exists.

3. **Detail all in-flight milestones**

   Aggregate all open milestones across projects into one table:
   - Project, milestone title, progress, due date, health
   - Highlight overdue milestones
   - Show recently completed milestones as wins

4. **Create the activity heatmap**

   A visual summary of which projects are active vs. stagnant:
   - Rank projects by commit count in last 30 days
   - Flag projects with zero activity that have open milestones (these are at risk)

5. **Build portfolio Eisenhower matrix**

   Classify each active project into the Eisenhower quadrants:
   - **Urgent**: Has overdue milestones, approaching deadlines, critical blockers,
     or time-sensitive external dependencies (e.g., a client deadline)
   - **Important**: Core to the user's mission, revenue-generating, has active
     milestones with momentum, or is a dependency for other projects
   - Projects with no milestones and no activity typically fall in Q4 (eliminate/archive)
   - Projects with high activity and near-complete milestones are Q1 (do first)

   Render as an ASCII box diagram showing all projects in their quadrants.

6. **Identify cross-project concerns**

   Look for patterns across projects:
   - Are multiple projects blocked on the same thing?
   - Is attention too scattered (many projects, low activity each)?
   - Are there resource conflicts (same person/agent needed across projects)?
   - Are any projects drifting without clear direction (no milestones, no charter)?

6. **Write priority recommendations**

   Based on the data, recommend where to focus:
   - Which projects need immediate attention (🔴 Behind or overdue milestones)?
   - Which projects should be explicitly paused/archived to reduce cognitive load?
   - Which milestones are closest to completion and should be finished first?
   - What new milestones or reviews should be initiated?

   Recommendations must be specific and actionable. Each should reference a DeepWork
   workflow to run if applicable (e.g., "Run `project/success` for catalyst to update
   the charter").

7. **Write the report to the notes repo**

   Save the final report to `{notes_path}/projects/portfolio/reviews/YYYY-MM.md`
   where YYYY-MM is the current year-month.

   Create the directory structure if it doesn't exist:
   ```bash
   mkdir -p {notes_path}/projects/portfolio/reviews/
   ```

## Output Format

### portfolio_report.md

The final portfolio review report.

**Structure**:
```markdown
# Portfolio Review — [Month YYYY]

**Date**: [YYYY-MM-DD]
**Active Projects**: [N]
**Open Milestones**: [N]
**Overall Health**: [🟢/🟡/🔴] [summary sentence]

## Portfolio Summary

[2-3 sentence executive summary of where things stand. Highlight the biggest win,
the biggest risk, and the recommended focus area.]

## Project Status

| Project | Status | Active Milestone | Progress | Activity | Top Blocker |
|---------|--------|-----------------|----------|----------|-------------|
| keystone | 🟡 At Risk | Desktop Integration | 67% | High (23) | Installer TUI |
| catalyst | 🟢 On Track | MVP Launch | 45% | Medium (8) | — |
| meze | ⚪ Deferred | — | — | Stagnant (0) | No active work |
| eonmun | ⚪ Deferred | — | — | Stagnant (0) | — |
[...]

## In-Flight Milestones

| Project | Milestone | Open | Closed | Progress | Due Date | Health |
|---------|-----------|------|--------|----------|----------|--------|
| keystone | Desktop Integration | 4 | 8 | 67% | 2026-04-01 | 🟡 |
| catalyst | MVP Launch | 6 | 5 | 45% | 2026-05-01 | 🟢 |
[...]

**Recently Completed**: keystone/Terminal Module (2026-02-15)

## Activity (Last 30 Days)

| Project | Commits | Last Commit | Trend |
|---------|---------|-------------|-------|
| keystone | 23 | 2026-03-19 | High |
| catalyst | 8 | 2026-03-15 | Medium |
| nixos-config | 5 | 2026-03-10 | Medium |
| meze | 0 | 2025-12-01 | Stagnant |
[...]

## Portfolio Priority Matrix

```
                      URGENT                             NOT URGENT
            ┌────────────────────────────┬────────────────────────────┐
            │ Q1: DO FIRST               │ Q2: SCHEDULE               │
 IMPORTANT  │ keystone (TUI 95%)         │ catalyst (Cloud Platform)  │
            │ nixos-config (infra maint) │ obsidian (zk migration)    │
            ├────────────────────────────┼────────────────────────────┤
            │ Q3: DELEGATE               │ Q4: ELIMINATE / ARCHIVE    │
 NOT        │ plant-caravan (0% milestone)│ meze, eonmun, tetrastack  │
 IMPORTANT  │                            │ ks.systems, latinum-space  │
            │                            │ ncrmro-website, ks-hw      │
            └────────────────────────────┴────────────────────────────┘
```

**Reading the matrix**: Q1 projects need your time NOW. Q2 projects are strategic
but not time-pressured — schedule dedicated blocks. Q3 items have urgency signals
(open milestones) but low importance — delegate to agents or deprioritize. Q4 projects
should be explicitly archived to reduce cognitive overhead.

## Cross-Project Concerns

- **Attention spread**: [N] active projects but only [M] have meaningful activity —
  consider pausing projects without clear milestones
- **Stale projects with potential**: meze and eonmun have repos but no recent activity
  or milestones — decide to reactivate or archive

## Recommendations

1. **Finish keystone Desktop Integration** — 67% complete, closest to done. Focus
   remaining effort here. (4 issues remaining)
2. **Archive or reactivate meze** — No activity in 90+ days. Run `project/success`
   to decide: continue, pivot, or archive.
3. **Create milestone for nixos-config** — Active commits but no milestone to track
   against. Run `milestone/setup` to formalize scope.
4. **Pause eonmun** — No activity, no milestones. Explicitly mark as paused in
   PROJECTS.yaml to reduce cognitive load.
```

## Quality Criteria

- The report opens with an overall portfolio health assessment and project count
- A summary table lists every project with status indicator, milestone, and activity
- All open milestones across projects are listed with completion percentages and dates
- Cross-project concerns are identified (resource conflicts, scattered attention, stagnation)
- Recommendations are specific, actionable, and ordered by impact
- All status indicators and assessments cite specific data, not vague assertions
- The report is written to the correct path in the notes repo

## Context

This is the capstone step of the portfolio review. The user reads this report to decide
where to allocate their time and energy. It should be scannable (tables, not paragraphs)
and opinionated (clear recommendations, not just data dumps). The report replaces the
old per-project `status.md` files with a single portfolio-level view.
