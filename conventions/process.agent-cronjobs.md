## Agent Cronjobs

**Status:** SHOULD follow (RFC 2119)

## Overview

Each OS agent receives a single systemd user timer:
`agent-<name>-task-loop`. The previous multi-timer arrangement
(`notes-sync`, `scheduler`, multi-phase `task-loop`) has been removed.

The timer fires on `OnCalendar = keystone.os.agents.<name>.taskLoop.interval`
(default `*:0/15`) and execs the agent's CLI of choice
(`claude` / `codex` / `gemini`) with a named skill. The skill — plain
markdown under `~/.agents/skills/<skill>/SKILL.md` — drives all behavior.
The systemd service holds no state and does no pre-fetch, retry, or
backoff; the skill is responsible for being cheap when there is no work.

## Configuration

```nix
keystone.os.agents.luce = {
  taskLoop = {
    enable = true;
    tool = "claude";       # one of: claude, codex, gemini
    interval = "*:0/15";   # systemd OnCalendar expression
    skill = "task-loop";   # skill name under ~/.agents/skills/<skill>/
  };
};
```

## Debugging

```bash
agentctl <name> status agent-<name>-task-loop
agentctl <name> journalctl -u agent-<name>-task-loop -n 50
agentctl <name> start agent-<name>-task-loop   # manual fire
```

## See also

- [docs/agents/os-agents.md](../docs/agents/os-agents.md) — new layout
  and `taskLoop` option reference.
- `process.task-tracking` — how task state files live in the consumer
  flake and arrive in the agent home via symlinks.
