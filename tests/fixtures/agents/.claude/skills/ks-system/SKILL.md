---
name: ks-system
description: "Keystone system — may start keystone_system/issue or keystone_system/doctor"
---

Help the user get the most out of Keystone.

When invoked as `$ks <route>`, this skill routes to the corresponding DeepWork
workflow and MUST NOT execute the similarly named `ks` CLI command.

## Session context

- Capabilities: ks, notes, project
- Development mode: disabled
- Published commands: ks.system, ks.notes, ks.projects

## Operating rules

- Prefer a direct answer for usage questions about `ks`, keystone modules, repo layout, conventions, or how to configure the system.
- Use DeepWork MCP tools only when the request benefits from a workflow or should create durable artifacts.
- Do not start workflows outside the allowed routes below.
- Treat explicit `$ks ...` invocation as skill routing, not shell command execution.
- Do not execute `ks doctor` or `ks issue` when the user invoked `$ks doctor` or `$ks issue`.
- If workflow startup is blocked by missing runtime prerequisites, report the blocker plainly and do not fall back to the `ks` CLI.
- If the user asks to implement Keystone code changes and `/ks.dev` is available, direct the request through the development route instead of improvising a separate workflow.
- If the user asks for a capability that is not available in this session, say so plainly and explain which capability is missing.
- When work produces durable decisions, findings, or reusable operational context and `ks.notes` is available, direct the user to `ks.notes` so that context is preserved in the notebook.

## Allowed routes

- Explicit `$ks.system doctor`: start `keystone_system/doctor`.
- Explicit `$ks.system issue`: start `keystone_system/issue`.
- Keystone usage help, module discovery, configuration guidance, and workflow recommendations: answer directly when no workflow is needed.
- Feature requests, bug reports, paper cuts, and missing Keystone capabilities: start `keystone_system/issue`.
- Keystone health checks and troubleshooting: start `keystone_system/doctor` when the user wants diagnosis rather than documentation.
- Notes workflows (repair, inbox, init, setup): direct the user to `/ks.notes` instead of starting a notes workflow directly.
- Project workflows (onboard, press release, milestone, engineering handoff, success): direct the user to `/ks.projects` instead of starting a project workflow directly.

## Invocation rules

- `$ks` with no arguments: explain the available Keystone workflow routes and direct-help paths.
- `$ks doctor`: start the `keystone_system/doctor` workflow.
- `$ks issue`: start the `keystone_system/issue` workflow.
- Other `$ks ...` invocations: treat them as Keystone help or routing requests, not as permission to execute the `ks` shell command.