# Decompose into Child Issues

## Objective

Break the implementation plan into small, non-blocking child issues — each mapping to a single small PR — with proper type separation, feature flag annotations, and traceability back to the plan issue.

## Task

Read the scope analysis and plan issue report from prior steps, then create individual child issues on the platform. Each issue should be independently implementable with a tight scope targeting 2-3 files max per PR.

### Process

1. **Read prior step outputs**
   - Load `scope_analysis.md` — for the story-to-system map, prerequisites, and system boundaries
   - Load `plan_issue_report.md` — for the plan issue number and implementation order
   - Extract the plan issue number, milestone, platform, and repo slug

2. **Design the decomposition**

   Apply type separation — create distinct issues for each concern:

   - **`chore:` / `refactor:` issues** — Infrastructure prerequisites identified in scope analysis (database migrations, shared utilities, CI config). These come first and unblock feature work.
   - **`feat:` issues** — User story implementation. Each should map to one or two user stories and target a specific system boundary from the scope analysis.
   - **`test:` issues** — Integration or end-to-end test suites that span multiple features. Unit tests should be included in their `feat:` issue, not separated.

   Design for non-blocking PRs:
   - Each issue should be implementable without waiting for other feature PRs
   - Infrastructure issues (`chore:`) can be parallelized when independent
   - Feature issues should depend on infrastructure, not on each other
   - Use feature flags to avoid blocking on deployment order

3. **Scope each child issue tightly**
   - Target 2-3 files max per PR
   - No stretch goals — if something is nice-to-have, create a separate future issue
   - Each issue should be completable in a single focused session
   - If an issue seems too large, split it further

4. **Create child issues**

   For each child issue:

   **Issue title**: Use conventional commit prefix format:
   - `feat: add recipe creation form`
   - `chore: add recipes database migration`
   - `test: add recipe API integration tests`
   - `refactor: extract shared validation utilities`

   **Issue body**:
   ```markdown
   Part of #{plan_issue_number}

   ## Goal
   [1-2 sentence description of what this issue delivers]

   ## Acceptance Criteria
   - [ ] [Specific, verifiable criterion 1]
   - [ ] [Specific, verifiable criterion 2]
   - [ ] [Specific, verifiable criterion 3]

   ## Dependencies
   - Requires #{chore_issue_number} (database migration) — or "None"

   ## Feature Flag
   - Flag: `ENABLE_RECIPE_SHARING` — or "Not applicable"

   ## Files Expected to Change
   - `src/routes/recipes.ts`
   - `src/components/RecipeForm.tsx`
   ```

   **GitHub**:
   ```bash
   gh issue create --repo {owner}/{repo} \
     --title "{type}: {description}" \
     --body "$BODY" \
     --label "{type_label}" \
     --milestone "{milestone title}" \
     --assignee {drago_username}
   ```

   **Forgejo**:
   ```bash
   fj issue create "{type}: {description}" \
     --body "$BODY" \
     --label "{type_label}" \
     -r {owner}/{repo}
   ```
   Then assign and link to milestone via API.

   - Apply the appropriate label (`engineering`, `chore`, `test`, etc.)
   - Assign to Drago (CTO)
   - Link to the milestone

5. **Update the plan issue**
   - Add a phased dependency graph to the plan issue body showing all child issues
   - Group by phase: infrastructure → features → tests

   **GitHub**:
   ```bash
   gh issue edit {plan_issue_number} --repo {owner}/{repo} --body "$UPDATED_BODY"
   ```

   Format the dependency graph as:
   ```markdown
   ## Child Issues

   ### Phase 1: Infrastructure (parallel)
   - [ ] #101 chore: add recipes database migration
   - [ ] #102 chore: set up image upload infrastructure

   ### Phase 2: Features (parallel, depends on Phase 1)
   - [ ] #103 feat: add recipe creation form
   - [ ] #104 feat: add recipe search

   ### Phase 3: Integration Tests (depends on Phase 2)
   - [ ] #105 test: add recipe API integration tests

   ### Future Work (out of scope for this milestone)
   - Recipe ratings and reviews
   - Recipe import from external sites
   ```

6. **Write the decomposition report**

## Output Format

### decomposition_report.md

A report documenting all created child issues with traceability.

**Structure**:
```markdown
# Decomposition Report: [Milestone Title]

## Platform
- **Platform**: [github | forgejo]
- **Repository**: [owner/repo]

## Plan Issue
- **Number**: #[plan_issue_number]
- **URL**: [URL]

## Child Issues Created

### Infrastructure (chore/refactor)

| # | Issue | Title | Dependencies | Stories |
|---|-------|-------|-------------|---------|
| 1 | #101 | chore: add recipes database migration | None | US-001, US-002, US-004 |
| 2 | #102 | chore: set up image upload infrastructure | None | US-001 |

### Features (feat)

| # | Issue | Title | Dependencies | Stories | Feature Flag |
|---|-------|-------|-------------|---------|-------------|
| 3 | #103 | feat: add recipe creation form | #101, #102 | US-001 | — |
| 4 | #104 | feat: add recipe search | #101 | US-002 | — |
| 5 | #105 | feat: add recipe sharing | #101 | US-003 | ENABLE_RECIPE_SHARING |

### Tests (test)

| # | Issue | Title | Dependencies | Stories |
|---|-------|-------|-------------|---------|
| 6 | #106 | test: add recipe API integration tests | #103, #104 | US-001, US-002 |

## Phased Dependency Graph

### Phase 1: Infrastructure (parallel)
- #101, #102

### Phase 2: Features (parallel, depends on Phase 1)
- #103, #104, #105

### Phase 3: Tests (depends on Phase 2)
- #106

## Coverage Matrix

| User Story | Child Issues |
|-----------|-------------|
| US-001 | #101, #102, #103 |
| US-002 | #101, #104 |
| US-003 | #101, #105 |
| US-004 | #101 |

## Future Work (out of milestone scope)
- [Stretch goal 1]
- [Stretch goal 2]

## Statistics
- **Total issues**: [count]
- **Infrastructure**: [count]
- **Features**: [count]
- **Tests**: [count]
- **Avg files per issue**: [estimate]

## Notes
[Any issues encountered or items needing attention]
```

## Quality Criteria

- Every item in the plan issue is covered by at least one child issue
- Each child issue is scoped to a small PR (2-3 files max)
- Issues are designed so their PRs do not block each other
- `feat:` issues are separate from `chore:`/`refactor:` infrastructure issues and `test:` issues
- Feature flag requirements are noted where applicable
- No stretch goals are included in milestone scope; stretch goals are noted as separate future work
- Each child issue references the plan issue with "Part of #N"
- Child issue titles use conventional commit prefixes (feat:, chore:, test:, refactor:)
- The plan issue is updated with a phased dependency graph of all child issues

## Context

This is the final step in the engineering planning workflow. The child issues become the actual work items that get picked up during implementation. Each issue should map directly to one branch and one PR, following the `code.delivery` convention. The decomposition quality directly affects implementation velocity — issues that are too large slow down review, issues that block each other create bottlenecks, and missing infrastructure issues cause surprise blockers during feature work.
