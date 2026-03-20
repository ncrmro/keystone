# Create Implementation Plan Issue

## Objective

Create a master "Plan" issue on the milestone that references the specs PR, documents happy paths and test expectations for each user story, includes design mockups for UI components, and describes expected demo artifacts.

## Task

Read the scope analysis and specs PR report from prior steps, then compose and create a comprehensive plan issue on the project's platform. This issue becomes the single reference point for all implementation work on the milestone.

### Process

1. **Read prior step outputs**
   - Load `scope_analysis.md` — for the story-to-system map and prerequisites
   - Load `specs_pr_report.md` — for the specs PR number/URL and spec file details
   - Extract the milestone title, issue number, and platform

2. **Compose the plan issue body**
   For each user story from the milestone issue, include:

   - **Happy path requirements** — the expected user flow when everything works correctly
   - **Red/green test expectations** — what test should fail before implementation (red) and pass after (green). Be specific about the assertion, not just "it should work."
   - **ASCII art design mockups** — for any new UI components, page layouts, or visual elements. Show the layout, key elements, and user interaction points.
   - **Expected demo artifacts** — describe what screenshots, videos, or preview URLs should be produced when this story is complete. These are used for the press release and human review.

   Also include:
   - **Implementation order** — which stories can be parallelized and which have dependencies
   - **Feature flag requirements** — which stories need feature flags for safe deployment
   - References to the specs PR and the original milestone issue

3. **Create the plan issue**

   **GitHub**:
   ```bash
   gh issue create --repo {owner}/{repo} \
     --title "Plan: {milestone title}" \
     --body "$BODY" \
     --label "engineering" --label "plan" \
     --milestone "{milestone title}" \
     --assignee {drago_username}
   ```

   **Forgejo**:
   ```bash
   fj issue create "Plan: {milestone title}" \
     --body "$BODY" \
     --label "engineering" --label "plan" \
     -r {owner}/{repo}
   ```
   Then link to milestone and assign via API.

   - Ensure `engineering` and `plan` labels exist (create if missing)
   - Assign to Drago (CTO) — read username from `.agents/TEAM.md`
   - Link to the milestone

4. **Write the plan issue report**

## Output Format

### plan_issue_report.md

A report documenting the created plan issue.

**Structure**:
```markdown
# Plan Issue Report: [Milestone Title]

## Platform
- **Platform**: [github | forgejo]
- **Repository**: [owner/repo]

## Plan Issue
- **Number**: #[number]
- **Title**: Plan: [milestone title]
- **URL**: [issue URL]
- **Milestone**: [milestone title]
- **Assignee**: [Drago's username]
- **Labels**: engineering, plan

## References
- **Milestone Issue**: #[milestone_issue_number]
- **Specs PR**: #[specs_pr_number] ([URL])

## Stories Included

| Story | Happy Path | Tests | Mockup | Demo |
|-------|-----------|-------|--------|------|
| US-001: [title] | yes | yes | yes/no | yes |
| US-002: [title] | yes | yes | yes/no | yes |
...

## Implementation Order
[Summary of the phasing — what can be parallel, what must be sequential]

## Feature Flags
[List of stories requiring feature flags, or "None"]

## Notes
[Any issues or items needing attention]
```

### Plan Issue Body Format

The issue body created on the platform should follow this structure:

```markdown
# Plan: [Milestone Title]

**Milestone Issue**: #[milestone_issue_number]
**Specs PR**: #[specs_pr_number]

## Stories

### US-001: [Story title]

**Happy Path**:
1. User navigates to /recipes/new
2. User fills in title, ingredients, and instructions
3. User clicks "Save Recipe"
4. System creates recipe and redirects to /recipes/{id}
5. Recipe appears in the user's recipe list

**Test Expectations**:
- RED: `POST /api/recipes` with valid payload returns 404 (route doesn't exist yet)
- GREEN: `POST /api/recipes` with valid payload returns 201 with recipe ID
- RED: Recipe form component renders without crashing (component doesn't exist yet)
- GREEN: Recipe form component renders with title, ingredients, and save button

**Design Mockup**:
```
┌─────────────────────────────────┐
│  New Recipe                     │
├─────────────────────────────────┤
│  Title: [________________]      │
│                                 │
│  Ingredients:                   │
│  [________________] [+ Add]     │
│  • Flour                        │
│  • Sugar                        │
│                                 │
│  Instructions:                  │
│  [                            ] │
│  [                            ] │
│                                 │
│  [Save Recipe]  [Cancel]        │
└─────────────────────────────────┘
```

**Demo Artifacts**:
- Screenshot: Recipe creation form with sample data filled in
- Screenshot: Successfully created recipe detail page
- Video (optional): Full create flow from empty form to saved recipe

---

### US-002: [Story title]
...

## Implementation Order

### Phase 1 (parallel — no dependencies)
- Chore: Database schema migration
- Chore: Image upload infrastructure

### Phase 2 (parallel — depends on Phase 1)
- US-001: Recipe creation
- US-002: Recipe search

### Phase 3 (depends on Phase 2)
- US-005: Recipe sharing

## Feature Flags

| Story | Flag Name | Reason |
|-------|-----------|--------|
| US-003 | `ENABLE_RECIPE_SHARING` | Social features need gradual rollout |
```

## Quality Criteria

- Every user story from the milestone issue appears in the plan with happy path requirements
- Each story includes red/green test expectations describing what fails before and passes after implementation
- ASCII art mockups are included for new UI components or layouts
- Expected demo artifacts are described for each story (screenshots, videos, preview URLs)
- The specs PR is referenced in the plan issue body
- The plan issue is linked to the milestone
- Implementation order is documented with phasing and parallelization notes

## Context

This step creates the engineering blueprint for the milestone. The plan issue serves three purposes: (1) it's the single reference for all implementation work, (2) it communicates the engineering approach to the CPO and human, and (3) it provides the structure that the next step (decompose_child_issues) will use to create individual issues. The test expectations follow TDD principles — defining what should fail and pass before writing code. The demo artifacts ensure that every story has a verifiable outcome visible to stakeholders.
