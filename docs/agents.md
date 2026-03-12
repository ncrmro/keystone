---
layout: default
title: Agents
---

# Agents

OS agents are non-interactive NixOS user accounts designed for autonomous LLM-driven operation. See [OS Agents](os-agents.md) for the full system-level reference (provisioning, agent-space, task loop, cronjobs).

This page documents the **human-side tooling** for interacting with agents.

## agentctl

`agentctl` is the unified CLI for managing agent services and mail from the host. It runs systemctl/journalctl commands as the agent user via a hardened sudo helper.

**Usage**:

```bash
agentctl <agent-name> <command> [args...]
```

**Commands**:

| Command | Description |
|---------|-------------|
| `status`, `start`, `stop`, `restart` | Manage agent user services |
| `enable`, `disable` | Enable/disable agent user services |
| `list-units`, `list-timers` | List agent's systemd units/timers |
| `show`, `cat`, `is-active`, `is-enabled`, `is-failed` | Inspect service state |
| `daemon-reload`, `reset-failed` | Reload/reset agent service manager |
| `journalctl` | View agent user service logs |
| `exec` | Run an arbitrary command as the agent (diagnostics) |
| `tasks` | Show agent tasks in a table (pending/in_progress first) |
| `email` | Show the agent's inbox (recent envelopes) |
| `claude` | Start interactive Claude session in agent notes directory |
| `mail` | Send structured email to the agent |
| `vnc` | Open remote-viewer to the agent's VNC desktop |
| `provision` | Generate SSH keypair, mail password, and agenix secrets |

**Examples**:

```bash
agentctl drago status agent-task-loop-drago
agentctl drago journalctl -u agent-task-loop-drago -n 20
agentctl drago restart agent-task-loop-drago
agentctl drago list-timers
agentctl drago tasks
agentctl drago email
agentctl drago mail task --subject "Fix CI pipeline"
agentctl drago provision                  # full flow incl. hwrekey
agentctl drago provision --skip-rekey     # skip hwrekey at end
```

**Security model**: agentctl dispatches through a per-agent Nix-generated helper script that is the sole sudoers target. The helper hardcodes `XDG_RUNTIME_DIR` internally (no `SETENV` needed) and rejects dangerous systemctl verbs (`edit`, `set-environment`, `import-environment`). See the `SECURITY:` comment in `modules/os/agents.nix` for the full threat model.

### Mail Templates

The `mail` command sends structured email templates to agents. It opens a pre-filled template in `$EDITOR`, then sends via `himalaya message send`.

| Template | Subject Tag | Purpose |
|----------|-------------|---------|
| `project.new` | `[project.new]` | New project request (lean canvas format) |
| `spike` | `[spike]` | Technical spike with time box and constraints |
| `task` | `[task]` | Ad-hoc task with acceptance criteria |
| `status` | `[status]` | Status request for a project |
| `research` | `[research]` | Research request with scope and key questions |

**How it works**:

1. Loads template from `$AGENT_MAIL_TEMPLATES/{template}.md`
2. Detects sender from himalaya config (fallback: `git config user.email`)
3. Prepends RFC 2822 headers (From, To, Subject, Date, MIME)
4. Opens `$EDITOR` on the temp `.eml` file
5. Prompts `Send? [y/N]`, pipes to `himalaya message send` on confirm

Subject lines follow the convention `[template-type] Title` (e.g., `[project.new] Plant Caravan`). The agent's task loop parses the tag to determine how to process the email.

## Assigning Work

Use `agentctl <name> mail` to send structured task emails:

```bash
agentctl drago mail task --subject "Fix CI pipeline"
agentctl drago mail spike --subject "ZFS replication feasibility"
agentctl drago mail project.new --subject "Plant Caravan"
```

The agent's task loop picks up emails and processes them based on the `[template-type]` subject tag. See [mail templates](#mail-templates) above for available templates.
