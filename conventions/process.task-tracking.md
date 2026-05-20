## Task Tracking

**Status:** SHOULD follow (RFC 2119)

## TASKS.yaml

Each agent's runtime state lives in three YAML files in its home
directory: `TASKS.yaml`, `SCHEDULES.yaml`, `ISSUES.yaml`. They are
**symlinks** into the consumer flake (e.g. `nixos-config/agents/<name>/`)
and the source files there are gitignored. Mutations made by a running
agent persist on the deployed host but never travel back into the
operator's repository.

The schema below is what the `task-loop` skill is expected to read and
write. Skill implementations MAY add fields, but the listed ones are the
shared minimum.

```yaml
tasks:
  - name: "slug-style-task-name"
    description: "What the task involves"
    status: pending | completed
    source: email | schedule | issue # where the task originated
    source_ref: "email-23-..."       # reference to the source
    project: "project-name"          # which project this relates to
    needs: ["other-task-name"]       # task dependencies (if any)
```

## See also

- [docs/agents/os-agents.md](../docs/agents/os-agents.md) — agent home
  layout and how the YAML files are symlinked in.
- `process.agent-cronjobs` — the single timer that drives task-loop
  execution.
