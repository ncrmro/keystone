# Find Gap Projects

## Objective

Scan all active projects in the portfolio and identify those with **no open milestones**
on any of their repos. These are the "gap projects" that need retroactive milestone setup.

## Task

1. **Discover active projects**

   Read the notes repo to find all active projects. Use the same discovery logic as
   the `discover_projects` step in the `review` workflow:

   - Read `{notes_path}/projects/README.md` for the project list
   - Check `{notes_path}/PROJECTS.yaml` if it exists for priority ordering
   - Scan `{notes_path}/projects/*/` directories for project slugs

   Exclude archived or explicitly inactive projects.

2. **Check milestones for each project**

   For each active project, check all its repos for open milestones:

   **GitHub repos** (platform: github):
   ```bash
   gh api repos/{owner}/{repo}/milestones --jq '.[].title'
   ```

   **Forgejo repos** (platform: forgejo):
   ```bash
   fj milestones list {owner}/{repo} 2>/dev/null
   # or via tea API
   tea api GET /repos/{owner}/{repo}/milestones
   ```

   A project is a **gap project** if ALL of its repos have zero open milestones.

3. **Gather basic context for each gap project**

   For each gap project, collect:
   - Last release or tag (most recent `git tag` or GitHub release)
   - Last commit date across all repos
   - Open issue count across all repos
   - Any existing charter/profile notes path

   **GitHub**:
   ```bash
   gh release list --repo {owner}/{repo} --limit 1
   gh api repos/{owner}/{repo}/commits --jq '.[0].commit.author.date'
   gh api repos/{owner}/{repo}/issues?state=open --jq 'length'
   ```

   **Forgejo**:
   ```bash
   fj releases list {owner}/{repo} --limit 1
   tea api GET /repos/{owner}/{repo}/commits
   ```

4. **Check for notes/charter files**

   For each gap project, check if these files exist in the notes repo:
   - `{notes_path}/projects/{slug}/charter.md`
   - `{notes_path}/projects/{slug}/README.md`
   - `{notes_path}/projects/{slug}/status.md`

   Note which files exist — they'll be useful context for the proposal step.

## Output Format

### gap_projects.md

```markdown
# Gap Projects — [Date]

Projects with no open milestones across all repos.

| Project | Repos | Last Release | Last Commit | Open Issues | Notes Files |
|---------|-------|-------------|-------------|-------------|-------------|
| meze | ncrmro/meze:github | v0.1.0 (2025-09-01) | 2025-11-15 | 3 | charter.md |
| eonmun | ncrmro/eonmun:github | — | 2025-08-20 | 0 | — |
| ncrmro-website | ncrmro/ncrmro.com:github | — | 2026-01-05 | 5 | README.md |

---

## meze

- **Repos**: ncrmro/meze (GitHub)
- **Last release**: v0.1.0 (2025-09-01)
- **Last commit**: 2025-11-15 (102 days ago)
- **Open issues**: 3
- **Notes files**: charter.md

## eonmun

- **Repos**: ncrmro/eonmun (GitHub)
- **Last release**: none
- **Last commit**: 2025-08-20 (220 days ago)
- **Open issues**: 0
- **Notes files**: none
```

## Quality Criteria

- Every active project was checked (not just a subset)
- Only projects with zero open milestones on ALL repos are included
- Each entry has repo info, last release/tag, and last commit date
- The list is sorted by last commit date descending (most recently active first)
