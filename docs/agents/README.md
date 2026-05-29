# Agents

Keystone is the foundation for running **fully agentic OS and infrastructure
under your own control** — operating systems and fleets where autonomous
agents pursue missions on hardware you own, with credentials you hold, against
data you decide to share. The goal is not to glue together hosted AI
services; it is to make personal and organizational infrastructure itself
agentic, so that any mission you can describe in skills and workflows can be
delegated to agents running in your sandbox, on your schedule, with full
auditability.

Concrete missions keystone is designed to host:

- **Business** — sales pipelines, customer outreach, market research, ops
  dashboards maintained by agents instead of staff.
- **Nonprofit** — grant tracking, donor follow-up, programme reporting,
  volunteer coordination — small organizations with too few hands.
- **Science and research** — literature monitoring, experiment scheduling,
  data ingestion, result reproduction across compute resources you control.
- **Home** — calendar and reminder management, mail triage, household
  inventory, security camera summaries, family logistics.
- **Personal knowledge** — notebook curation, daily reports, project status
  rollups, decision archives.

The platform is opinionated about how missions are constructed: as skills and
subagents in your `keystone-config` repo, orchestrated by autonomous OS-level
service accounts, optionally extended by DeepWork workflows for
quality-gated multi-step processes.

## The three layers

| Layer | What | Where to read |
|---|---|---|
| **L1 Terminal agents** | You + your CLI coding agents (Claude Code, Gemini CLI, Codex, OpenCode) + per-tool skills and subagents synced from your consumer flake. | [`tool.cli-coding-agents`](../../conventions/tool.cli-coding-agents.md) convention; [`docs/terminal/cli-coding-agents.md`](../terminal/cli-coding-agents.md) reference |
| **L2 OS agents** | Sandboxed service-account principals (`agent-<name>` users) that inherit L1 skills, identity docs, and subagents into isolated home dirs, run on systemd timers, and process notification-backed assignments. | [`os-agents.md`](os-agents.md) |
| **L3 DeepWork** | Workflow orchestration MCP for advanced multi-step processes with quality gates, layered over L1+L2. Used when basic looping needs richer control flow. | [`process.deepwork-job`](../../conventions/process.deepwork-job.md) convention |

L1 is the substrate. L2 builds on L1 by giving agents their own identity, mail,
and hardware-isolated home. L3 is reached for only when a workflow genuinely
needs orchestration that platform-native skills cannot express.

## How a mission starts

1. **Deploy keystone** on a host (`keystone-config` consumer flake + `ks update`).
2. **Populate the consumer flake** at `<consumer-flake>/agents/<tool>/skills/`
   and `<consumer-flake>/agents/claude/agents/` with the skills and subagents
   the mission needs. Either author them by hand or run `ks sync-agent-assets`
   to materialize the keystone-curated set.
3. **Declare OS agents** that should pursue the mission autonomously:
   `keystone.os.agents.<name> = { fullName = "..."; email = "..."; ... };`.
   Each agent inherits L1 — the same skill and subagent set is symlinked into
   their isolated home.
4. **Reach for DeepWork** only when basic auto-looping needs richer
   orchestration: multi-step workflows, review gates, parallel agents
   coordinated through shared state.

## The consumer flake as audit log

Keystone-generated skill content is materialized into the consumer flake at
`<consumer-flake>/agents/skills/<name>/` (the canonical, spec-compliant
location), with colocated conventions and roles symlinked into each skill
from `agents/_shared/conventions/`. Home-manager activation symlinks
`~/.agents/skills/` and `~/.claude/skills/` to that canonical path. Every
skill upgrade keystone ships becomes a reviewable commit in the user's
`keystone-config` repo: `git log -p agents/skills/ks-notes/` shows the
entire upgrade history of a single skill. Rollback is `git revert`; user
override is just editing the file and committing — keystone's regen will
overwrite on next run, the user's `git checkout` restores their version.

The regen is **manual** (`ks sync-agent-assets`). Home-manager activation
never silently rewrites the user's git tree.

## Agent instruction files

Agent instructions follow the same audit-log rule: Keystone materializes
generated prompt assets into the user's `keystone-config` repo, and the user
commits those files when they accept the generated state.

| Path | Ownership | Purpose |
|---|---|---|
| `agents/_shared/AGENTS.md` | Generated, committed | Canonical host-rendered instruction file for normal CLI agents. |
| `agents/_shared/TEAM.md` | Generated, committed | Shared team roster linked into each OS-agent home as `~/TEAM.md`. |
| `agents/_shared/SERVICES.md` | Generated, committed | Shared service index linked into each OS-agent home as `~/SERVICES.md`. |
| `agents/<name>/SOUL.md` | Generated, committed | Per-agent identity linked into that OS-agent home as `~/SOUL.md`. |
| `agents/<name>/AGENTS.md` | User-authored, committed | Per-OS-agent instruction file linked into `~/AGENTS.md` and `~/.pi/agent/AGENTS.md`. |
| `agents/<name>/SYSTEM.md` | User-authored, committed | Per-OS-agent system file linked into `~/SYSTEM.md`, `~/.pi/agent/SYSTEM.md`, and `~/.pi/agents/SYSTEM.md`. |
| `~/.pi/agent/AGENTS.md` | Runtime symlink, not committed | Points Pi at the shared file for human users or the per-agent file for OS agents. |

For human users, activation links `~/.pi/agent/AGENTS.md` to
`agents/_shared/AGENTS.md`. For OS agents, activation links
`~/.pi/agent/AGENTS.md` to `agents/<name>/AGENTS.md` and Pi SYSTEM paths to
`agents/<name>/SYSTEM.md`. Other CLI agents continue to read the shared file
through their native paths, for example
`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, and `~/.codex/AGENTS.md`.
OS-agent identity is linked from `ks-config/agents`, not from a notes repo:
`~/SOUL.md`, `~/TEAM.md`, and `~/SERVICES.md` resolve to committed files under
the consumer flake.

Per-agent Pi files are intentionally user-authored. Keystone owns the symlink
topology; the consumer `ks-config` repo owns the instruction content being
tested or deployed.

## L1 → L2 inheritance

OS agents inherit L1 by getting the same `<consumer-flake>/agents/<tool>/`
content symlinked into their own isolated home dirs. A skill you add for
yourself is immediately available to every OS agent on the host — no
per-agent duplication, no separate publishing step. This is the foundation
that lets agents auto-loop on platform-native skills without a DeepWork
dependency: an agent running `claude` with a custom `mission-task-loop` skill
synced from your consumer flake has everything it needs to execute the loop,
and the loop's behaviour is reviewable in git like any other skill.

## Future direction

- **OpenCode joins the symlink set.** `~/.config/opencode/AGENTS.md` and
  `~/.config/opencode/skills/` still write to the home dir directly; future
  scope is to bring them under the same consumer-flake pattern as the other
  three tools.
- **No-DeepWork OS-agent task loop.** Basic auto-looping today depends on the
  DeepWork-driven `task_loop` job. Future work will offer a platform-native
  alternative for fleets that don't want DeepWork — a small skill plus a
  systemd timer plus the agent's own scheduling state. The L1 plumbing this
  PR landed is the precondition.
- **Pi agent harness.** Experimentation with a more constrained agent harness
  for missions with stricter latency, cost, or determinism requirements.
- Several agentic surfaces today (Walker menu entries, notes sync,
  AI-extension overlays for agents with capabilities) are gated behind
  `keystone.experimental = true` while they stabilize.

## Other docs in this directory

- [`agents.md`](agents.md) — human-side tooling: `agentctl` CLI, mail
  templates, and how operators interact with the agent fleet.
- [OS agent e2e validation](os-agent-e2e.md) documents the email ping/pong
  smoke test for installed notification-driven OS agents.
- [`os-agents.md`](os-agents.md) — full reference for the OS-agent system:
  provisioning, identity docs, notification runners, systemd timers, and
  observability.
- [`comparison.md`](comparison.md) — platform comparison: keystone vs hosted
  agentic platforms (Devin, Imbue, etc.).
- [`hooks.md`](hooks.md) — CLI coding agent lifecycle hooks.

Convention sources of truth:
- [`tool.cli-coding-agents`](../../conventions/tool.cli-coding-agents.md) — per-tool paths, consumer-flake source layout, symlink semantics.
- [`process.deepwork-job`](../../conventions/process.deepwork-job.md) — DeepWork job design, skill registration.
- [`process.keystone-development`](../../conventions/process.keystone-development.md) — how to develop keystone itself.
