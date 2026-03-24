# Create or refresh project hub

## Objective

Ensure a project has one active hub note that acts as the curated entry point
for its decisions, reports, repos, and next actions.

## Task

1. Search for an existing active hub:
   ```bash
   zk list index/ --tag "project/<project_slug>" --tag "status/active" --format json
   ```

2. If no active hub exists, create one:
   ```bash
   zk new index/ --title "Project: <project_title>" --no-input --print-path \
     --extra project="<project_slug>"
   ```

3. If multiple hubs exist, choose one canonical hub, record the duplication in
   the output, and link the duplicates for manual cleanup.

4. Update the canonical hub so it contains:
   - frontmatter with `project: <project_slug>`,
   - tags `project/<project_slug>` and `status/active`,
   - `## Objective`,
   - `## Current state`,
   - `## Next actions`,
   - `## Knowledge web`,
   - `## Reports`,
   - `## Decisions`,
   - `## Related repos`,
   - `## Queries`.

5. Discover and link related notes:
   ```bash
   zk list --tag "project/<project_slug>" --format json
   ```
   - add the latest reports to `## Reports`,
   - add decision notes to `## Decisions`,
   - add durable notes to `## Knowledge web`,
   - add related repo links or tags to `## Related repos`.

6. Include at least one canonical query snippet in `## Queries`, for example:
   ```bash
   zk list --tag "project/<project_slug>" --format json
   zk list reports/ --tag "project/<project_slug>" --sort created- --format json
   ```

## Output Format

Write `project_hub_report.md`:

```markdown
# Project Hub Report

- Project: keystone
- Hub path: index/202603241200 project-keystone.md
- Action: created

## Linked Reports
- [[202603241230]]

## Linked Decisions
- [[202603231115]]

## Duplicate Hubs
- none
```
