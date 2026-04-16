---
description: Start the notes/doctor DeepWork workflow to repair and normalize a zk notebook
argument-hint: <optional scope>
---

Start the notes/doctor DeepWork workflow to repair and normalize a zk notebook.

Use the DeepWork MCP tools to start the workflow:

- job_name: "notes"
- workflow_name: "doctor"
- goal: "$ARGUMENTS" (use the user's arguments as scope or default to "Repair the configured notes dir")

Follow the workflow instructions returned by the MCP server. This audits the
notebook, normalizes frontmatter and tags, repairs project hubs and report
chains, and archives completed project material into the zk-managed archive.

## Safe invocation

Before the workflow begins its migration steps, it will select an execution mode:

- **No-commit mode** (default for agent-space notes): All mutations are applied to the
  working tree without creating any git commits. Reversible via `git checkout -- .`.
  Use this mode when running `notes/doctor` against an agent-space repo (e.g.,
  `/home/agent-*/notes`) that stays on `main`.
- **Logical-batch mode**: Mutations are grouped into phase-based commits (a small
  number, not one per file). Use when working in a dedicated migration branch or
  worktree.
- **Worktree mode**: A separate git worktree is created for the migration; changes
  are submitted as a PR. Use when a reviewable commit history is required.

**Never run `notes/doctor` in a mode that creates one git commit per migrated
file.** That produces commit spam and conflicts with Keystone repo safety rules.

After migration, validate the notebook with:

```bash
zk index
```

Check the `.deepwork/tmp/doctor_report.md` for the full verification output.
