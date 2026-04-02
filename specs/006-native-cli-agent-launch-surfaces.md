# Spec: Native CLI agent launch surfaces

## Stories Covered

- US-006: Launch specific OS-agent identities through each CLI's native agent system
- US-007: Launch archetype-specific specialist agents through each CLI's native agent system

## Affected Modules

- `modules/terminal/generated-agent-assets.nix`
- `modules/terminal/scripts/keystone-sync-agent-assets.sh`
- `modules/terminal/cli-coding-agent-configs.nix`
- `modules/os/agents/scripts/agentctl.sh`
- `docs/architecture/coding-cli-agents.md`
- `docs/terminal/terminal.md`
- `conventions/tool.cli-coding-agents.md`

## Data Models

### Generated agent definition record

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | string | yes | Stable generated identifier used by the target CLI |
| `kind` | enum | yes | `os-agent` or `archetype` |
| `displayName` | string | yes | Human-facing label |
| `description` | string | yes | Native tool routing hint |
| `instructionSource` | string | yes | Generated prompt body or referenced instruction file |
| `notesPath` | string | no | Required for `os-agent`; omitted for pure archetype agents |
| `host` | string | no | Required for `os-agent` when known |
| `archetype` | string | no | Required for `os-agent`; optional for archetype aliases |
| `mcpScope` | enum | yes | `global`, `agent-local`, or `unsupported` |
| `launchMode` | enum | yes | `session`, `mention`, `spawn`, or `tool-default` |

### Native launch surface matrix

| CLI | Native definition path | Native selection surface | Notes |
| --- | --- | --- | --- |
| Claude Code | `~/.claude/agents/*.md` | `claude --agent <name>` and native agent selection | Session-wide agent surface is documented |
| Gemini CLI | `~/.gemini/agents/*.md` | Native subagent invocation and explicit `@name` forcing | No Keystone-only synthetic flag |
| Codex | `~/.codex/agents/*.toml` | Native custom-agent workflow | Keystone MUST NOT claim a top-level `codex --agent` flag unless the tool documents one |
| OpenCode | `~/.config/opencode/agents/*.md` | Native primary/subagent selection and explicit `@name` invocation | No Keystone-only synthetic flag |

## Behavioral Requirements

1. Keystone MUST treat tool-native agent definitions as a first-class generated asset family.
2. Keystone MUST distinguish between `os-agent` identities and `archetype` specialist agents.
3. An `os-agent` definition MUST include the agent's notes root, resolved archetype, and host metadata when available.
4. An `archetype` definition MUST describe only the role-specialized behavior and MUST NOT impersonate a concrete OS agent identity.
5. Keystone MUST generate agent definitions at each CLI's native discovery path instead of relying on wrapper-only prompt injection.
6. Keystone MUST use each tool's documented native selection surface when launching a specific agent.
7. Keystone MUST NOT advertise or depend on a Keystone-invented `--agent` flag for tools that do not document one.
8. For Claude Code, Keystone MUST generate native agent files compatible with Claude Code's documented `--agent` session flag.
9. For Gemini CLI, Keystone MUST generate native agent files compatible with Gemini's documented subagent model and explicit `@name` invocation flow.
10. For Codex, Keystone MUST generate native custom-agent definitions and MUST NOT document `codex --agent <name>` unless Codex itself documents that surface.
11. For OpenCode, Keystone MUST generate native agent definitions and MUST use OpenCode's documented primary-agent or `@`-invoked subagent surfaces.
12. Keystone MAY provide helper commands such as `agentctl <name> claude` or repo-local launchers, but those helpers MUST resolve to native agent definitions and native selection syntax rather than custom wrapper semantics.
13. A concrete OS agent MUST be exposed under its direct Keystone name whenever the target CLI allows it, so launch surfaces such as `claude --agent drago` remain valid.
14. Keystone MUST keep generated agent names stable across rebuilds so launch surfaces, saved preferences, and docs remain valid.
15. Keystone MUST define and document a collision strategy when an OS-agent name and an archetype name would otherwise produce the same tool-native identifier.
16. When a collision requires disambiguation, Keystone MUST preserve the bare unprefixed name for the concrete OS agent and disambiguate the non-OS-agent variant instead.
17. Keystone SHOULD use the same semantic identifier across tools when the target CLI allows it.
18. Archetype agents SHOULD also keep bare semantic names such as `engineer` or `product` when the target CLI allows it.
19. Keystone MUST NOT introduce bespoke shortcut flags such as `--engineer` or `--product`; archetypes MUST be selected only through the target CLI's documented native agent-selection surface.
20. If a CLI lacks a native session-wide agent selector, Keystone MUST use that tool's documented task-level or mention-level agent invocation rather than a bespoke prompt format.
21. Agent-specific MCP capability scoping MUST use the tool's native configuration surface when that surface exists.
22. When a CLI cannot scope MCP servers per agent natively, Keystone MAY fall back to global MCP configuration, but the generated agent definition and docs MUST describe that limitation explicitly.
23. Launching a concrete OS agent MUST continue to set `NOTES_DIR` to that agent's notebook root for workflows that depend on durable note storage.
24. Launching a pure archetype agent MUST NOT rewrite `NOTES_DIR` to another principal's notebook.
25. Keystone MUST NOT replace upstream CLI binaries with wrapper shims whose primary purpose is intercepting and reinterpreting `--agent`.
26. Existing repo-local helpers that add non-agent features, such as worktree or spec bootstrapping, MAY remain, but they MUST preserve the underlying tool's native agent semantics.
27. Generated docs MUST include a per-tool mapping from Keystone agent concepts to the tool's native agent definition format and invocation syntax.
28. The documentation set MUST clearly separate stable implemented behavior from planned follow-up work for tools whose native agent features are still being integrated.

## Edge Cases

- If a target CLI supports custom agents but not per-agent MCP configuration, Keystone MUST keep the agent definition functional and MUST document the MCP-scoping limitation.
- If a target CLI supports only task-level agent invocation, helper commands MUST use that documented surface and MUST NOT describe it as a session-wide identity switch.
- If an OS-agent name collides with a built-in tool agent name, Keystone MUST generate a disambiguated identifier rather than shadowing the built-in name implicitly.
- If a user disables agent generation for a specific CLI, Keystone MUST avoid installing stale generated definitions for that CLI.
- If a tool changes its native agent schema, Keystone MUST update the generator and the per-tool docs together.

## Cross-spec dependencies

- `specs/002-repo-backed-terminal-assets.md`
- `specs/005-agent-development-parity.md`
- `specs/REQ-007-os-agents.md`
- `specs/REQ-014-ks-agent.md`
