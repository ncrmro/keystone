# Apply Gap Milestones

## Objective

Present the milestone proposals to the user, ask which to create, then create the
approved milestones on GitHub or Forgejo.

## Task

1. **Present the proposals**

   Read `gap_proposals.md` and display a numbered summary of all proposals:

   ```
   Gap Milestone Proposals
   =======================

   1. meze — "v0.2 Stability Release"
      Scope: Fix 3 open issues, update dependencies, improve error handling
      Suggested due date: 2026-05-01

   2. eonmun — "Initial Scope Definition"
      Scope: Define core feature set, create 5-10 issues from README goals
      Suggested due date: none

   3. ncrmro-website — "Content Refresh"
      Scope: Update bio, add project pages for catalyst and keystone
      Suggested due date: 2026-04-15

   Options:
     [A] Create all
     [S] Select specific projects (comma-separated numbers, e.g. "1,3")
     [N] Skip (no milestones created)
   ```

   Use the AskUserQuestion tool to prompt the user for their choice.

2. **Create approved milestones**

   For each approved project, create the milestone on the appropriate platform:

   **GitHub**:
   ```bash
   gh api repos/{owner}/{repo}/milestones \
     --method POST \
     --field title="{milestone_title}" \
     --field description="{milestone_description}" \
     --field due_on="{due_date}T00:00:00Z"  # omit if no due date
   ```

   **Forgejo**:
   ```bash
   fj milestone create {owner}/{repo} \
     --title "{milestone_title}" \
     --description "{milestone_description}"
   # or via tea API:
   tea api POST /repos/{owner}/{repo}/milestones \
     --data '{"title":"{milestone_title}","description":"{milestone_description}"}'
   ```

   The milestone description should be set to the full proposal scope from
   `gap_proposals.md` so the rationale is captured on the platform.

3. **Open issues for scope items (optional)**

   If the proposal includes specific issue titles (not just topics), offer to create
   those issues and assign them to the new milestone:

   ```
   Create scope issues for meze?
     - Fix error handling on import failure
     - Update aiohttp dependency to 3.x
     - Add retry logic for network timeouts
   ```

   Ask the user with AskUserQuestion before creating issues.

   **GitHub**:
   ```bash
   gh issue create --repo {owner}/{repo} \
     --title "{issue_title}" \
     --milestone "{milestone_title}"
   ```

4. **Record what was created**

   After each creation, capture the URL returned by the CLI and log it.

## Output Format

### milestones_created.md

```markdown
# Gap Milestones Created — [Date]

## Created

| Project | Milestone | URL | Issues Created |
|---------|-----------|-----|----------------|
| meze | v0.2 Stability Release | https://github.com/ncrmro/meze/milestone/1 | 3 |
| ncrmro-website | Content Refresh | https://github.com/ncrmro/ncrmro.com/milestone/2 | 0 |

## Skipped

| Project | Reason |
|---------|--------|
| eonmun | User chose to skip |

## Next Steps

- **meze**: 3 issues created and assigned to milestone. Run `portfolio/review_one` to
  track initial progress.
- **ncrmro-website**: Milestone created with no issues. Add issues manually or run
  `milestone/engineering_handoff` to decompose scope.
```

## Quality Criteria

- Every proposal from gap_proposals.md is either created or noted as skipped
- Each created milestone has a URL so the user can navigate directly to it
- The "Next Steps" section gives the user a clear path forward for each project
