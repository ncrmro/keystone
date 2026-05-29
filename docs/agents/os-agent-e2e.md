---
title: OS agent e2e validation
description: Validate notification-driven Keystone OS agents with email ping/pong
---

# OS agent e2e validation

Keystone OS agents are notification-driven system users. A healthy agent can
receive work through `ks notification`, process it from a systemd user service,
and leave an observable result on the shared communication surface.

The baseline validation is email assignment ping/pong:

1. the harness prepares a scoped worktree in the agent home,
2. the human mailbox sends `[ping] <tag>` to the agent mailbox with an
   `agent-task` block that asks the agent to reply by email,
2. `agent-{name}-pi-task-runner.service` fetches email through
   `ks notification fetch --sources email`,
3. the runner treats the email like any other notification-backed assignment,
   launches Pi, and passes the local tool instructions,
4. Pi uses `himalaya` to send `Re: [pong] <tag>`, and
5. the human mailbox contains the pong reply.

This intentionally tests the installed OS-agent path instead of only testing a
library function: mail credentials, `himalaya`, `ks notification`, systemd user
units, the Pi task runner, local tool instructions, and inbox observability all
have to work.

## Run the smoke test

From a Keystone config repo:

```bash
os-agents-e2e drago email
```

Template-generated config repos include `bin/os-agents-e2e` in their dev
shell. If no OS agents are configured, it exits 0 with a skip message.
Otherwise it runs the requested test. `email` runs `.#agents-e2e --smoke`;
`pr` is reserved for the GitHub/Forgejo assignment check; `all` runs every
implemented check.

By default, smoke mode sends the ping and then starts:

```text
agent-drago-pi-task-runner.service
```

That makes the test immediate instead of waiting for the next timer tick. If
you want to test the timer path only, pass `--no-trigger-agent-runner`.

## Expected result

The report should include:

```text
ping_worktree: pass
ping_send: pass
ping_runner_trigger: pass
ping_pong: pass
```

The user inbox should contain a message from the agent:

```text
Subject: Re: [pong] e2e-...
From: drago@...
```

The runner should record the email source as seen after launching the task.

## Design rule

New OS-agent checks should follow the same pattern:

- use a real external notification source,
- trigger or wait for the agent's systemd user service,
- assert the result from the user's observable surface, and
- avoid special-case handlers in the runner.

Avoid adding new long-lived local queue files for this path. The canonical
coordination surfaces are mail, GitHub/Forgejo notifications, issues, pull
requests, milestones, and boards.
