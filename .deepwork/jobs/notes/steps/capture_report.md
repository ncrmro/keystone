# Capture report

## Objective

Create a standardized report note for a project, link it to the latest prior
report in the chain, and update the project hub.

## Task

1. Ensure the project hub exists by searching for the active hub:
   ```bash
   zk list index/ --tag "project/<project_slug>" --tag "status/active" --format json
   ```
   If none exists, create or refresh it first.

2. Find the latest prior report in the same chain:
   ```bash
   zk list reports/ --tag "project/<project_slug>" --tag "report/<report_kind>" \
     --sort created- --limit 1 --format json
   ```

3. Create the new report:
   ```bash
   zk new reports/ --title "<report_title>" --no-input --print-path \
     --extra project="<project_slug>" \
     --extra report_kind="<report_kind>" \
     --extra source_ref="<source_ref>"
   ```

4. Update the created report note:
   - set `type: report`,
   - add tags `project/<project_slug>`, `report/<report_kind>`, and the relevant source tag,
   - set `previous_report` if a prior report exists,
   - summarize the findings, decisions, linked issue/PR references, and next actions.

5. Update the project hub so it links to the new report in `## Reports`.

## Output Format

Write `report_capture.md`:

```markdown
# Report Capture

- Project: keystone
- Report path: reports/202603241230 keystone-fleet-health-2026-03-24.md
- Report kind: fleet-health
- Previous report: 202603221015
- Hub updated: yes
```
