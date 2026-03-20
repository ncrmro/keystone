# Set Up Milestone and Link Issue

## Objective

Check if a milestone already exists for this scope, create one if needed, update the issue body with refined user stories, and link the issue to the milestone.

## Task

Using the refined stories and milestone title from the previous step, set up the milestone and issue on the project's platform (GitHub or Forgejo).

### Process

1. **Determine the platform and repo**
   - Use the `project_repo` input to identify the platform and repo slug
   - Read `.agents/TEAM.md` to get the correct agent username for the platform

2. **Check for existing milestone**
   - GitHub: `gh api repos/{owner}/{repo}/milestones --jq '.[] | select(.title == "TITLE") | .number'`
   - Forgejo: `tea api /repos/{owner}/{repo}/milestones` or equivalent curl
   - If a matching milestone exists, use it (record its number and URL)
   - If no match, create a new milestone

3. **Create milestone (if needed)**
   - GitHub: `gh api repos/{owner}/{repo}/milestones -f title="TITLE" -f description="SOURCE_REF"`
   - Forgejo: `tea api -X POST /repos/{owner}/{repo}/milestones` with title and description
   - The milestone description should reference the source (e.g., "From issue #N" or "From freehand scope notes")

4. **Ensure required labels exist**
   - Check that `product` and `engineering` labels exist on the repo
   - Create any missing labels:
     - GitHub: `gh label create "product" --repo owner/repo --description "Product story" --color "0E8A16"`
     - Forgejo: equivalent API call
   - Use sensible default colors if creating

5. **Update or create the issue**
   - If `issue_number` is provided:
     - Read the refined stories from `refined_stories.md`
     - Update the issue body with the refined stories content
     - GitHub: `gh issue edit <number> --repo owner/repo --body "BODY"`
     - Update the issue title to "[Milestone Title]: User Stories for Review"
     - Add the `product` label to the issue
     - Set the milestone on the issue
     - Assign to the business agent's account
   - If `issue_number` is blank:
     - Create a new issue with the refined stories as the body
     - Title: "[Milestone Title]: User Stories for Review"
     - GitHub: `gh issue create --repo owner/repo --title "TITLE" --body "BODY" --label "product" --milestone "MILESTONE"`
     - Assign to the business agent's account

6. **Verify the setup**
   - Confirm the milestone exists and the issue is linked to it
   - Confirm labels are applied
   - Record all URLs and numbers

## Output Format

### setup_report.md

A summary of everything that was created or updated.

**Structure**:
```markdown
# Milestone Setup Report

## Milestone
- **Title**: [milestone title]
- **Number**: [milestone number]
- **URL**: [milestone URL]
- **Status**: [created | already existed]

## Issue
- **Number**: [issue number]
- **Title**: [issue title]
- **URL**: [issue URL]
- **Status**: [updated | created]
- **Labels**: [comma-separated labels applied]
- **Assigned To**: [agent username]

## Actions Taken
1. [Description of each action, e.g., "Created milestone 'Homelab Monitoring Stack'"]
2. [e.g., "Updated issue #42 body with 4 refined user stories"]
3. [e.g., "Added user-story label to issue #42"]
4. [e.g., "Linked issue #42 to milestone #3"]

## Platform
- **Platform**: [github | forgejo]
- **Repository**: [owner/repo]
```

**Concrete example**:
```markdown
# Milestone Setup Report

## Milestone
- **Title**: Homelab Monitoring Stack
- **Number**: 3
- **URL**: https://github.com/ncrmro/homelab/milestone/3
- **Status**: created

## Issue
- **Number**: 42
- **Title**: Homelab Monitoring Stack: User Stories for Review
- **URL**: https://github.com/ncrmro/homelab/issues/42
- **Status**: updated
- **Labels**: product, enhancement
- **Assigned To**: luce-ncrmro

## Actions Taken
1. Created milestone "Homelab Monitoring Stack" (#3)
2. Created labels: product, engineering
3. Updated issue #42 body with 4 refined user stories
4. Added user-story label to issue #42
5. Set milestone on issue #42 to "Homelab Monitoring Stack"
6. Assigned issue #42 to luce-ncrmro

## Platform
- **Platform**: github
- **Repository**: ncrmro/homelab
```

## Quality Criteria

- A milestone was found or created and its title and URL are recorded
- The issue is associated with the milestone
- The issue body was updated with the refined user stories in standard format
- The `product` label is on the issue
- The report includes milestone title, issue number, and URLs
- The `product` and `engineering` labels exist on the repo for future use

## Context

This is the final step that makes everything concrete on the platform. After this step, a human can review the consolidated issue, comment on individual stories, and approve them before agents begin work. The milestone provides the tracking container, and the issue serves as the parent scope document.
